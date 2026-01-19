export function toBase64Url(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  const base64 = btoa(binary);
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+/g, '');
}

export function generateRandomBase64Url(size: number): string {
  const array = new Uint8Array(size);
  crypto.getRandomValues(array);
  return toBase64Url(array);
}

export function generateCodeVerifier(): string {
  // 64 bytes → sufficiently random base64url string
  return generateRandomBase64Url(64);
}

export async function computeCodeChallenge(verifier: string): Promise<string> {
  const data = new TextEncoder().encode(verifier);
  const digest = await crypto.subtle.digest('SHA-256', data);
  const bytes = new Uint8Array(digest);
  return toBase64Url(bytes);
}

export function decodeJwt(token: string | null): any {
  if (!token) return null;
  try {
    const { payload } = decodeJwtParts(token);
    return payload ?? null;
  } catch {
    return null;
  }
}

export function decodeJwtExp(token: string | null): number | null {
  const payload = decodeJwt(token);
  return payload && typeof payload.exp === 'number' ? payload.exp : null;
}

// ---------- Basic JWT (HS256) helpers for lab (no external libraries) ----------

function fromBase64Url(b64u: string): Uint8Array {
  const pad = b64u.length % 4 === 2 ? '==' : b64u.length % 4 === 3 ? '=' : '';
  const b64 = b64u.replace(/-/g, '+').replace(/_/g, '/') + pad;
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function toUtf8Bytes(str: string): Uint8Array {
  return new TextEncoder().encode(str);
}

function jsonToBase64Url(obj: any): string {
  const json = JSON.stringify(obj);
  return toBase64Url(toUtf8Bytes(json));
}

export function base64UrlEncodeString(str: string): string {
  return toBase64Url(toUtf8Bytes(str));
}

export function base64UrlDecodeToString(b64u: string): string {
  const bytes = fromBase64Url(b64u);
  let out = '';
  for (let i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i]);
  return out;
}

export function decodeJwtParts(token: string): { header: any | null; payload: any | null; signature: string | null } {
  try {
    const [h, p, s] = token.split('.');
    if (!h || !p || !s) return { header: null, payload: null, signature: null };
    const header = JSON.parse(base64UrlDecodeToString(h));
    const payload = JSON.parse(base64UrlDecodeToString(p));
    return { header, payload, signature: s };
  } catch {
    return { header: null, payload: null, signature: null };
  }
}

function ensureArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const ab = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(ab).set(bytes);
  return ab;
}

async function hmacSignSha256(keyBytes: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const keyAb: ArrayBuffer = ensureArrayBuffer(keyBytes);
  const dataAb: ArrayBuffer = ensureArrayBuffer(data);
  const key = await crypto.subtle.importKey('raw', keyAb, { name: 'HMAC', hash: 'SHA-256' } as HmacImportParams, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, dataAb);
  return new Uint8Array(sig as ArrayBuffer);
}

export async function createJwtHS256(payload: any, secret: string, header: Record<string, any> = {}): Promise<string> {
  const hdr = { alg: 'HS256', typ: 'JWT', ...header };
  const headerB64 = jsonToBase64Url(hdr);
  const payloadB64 = jsonToBase64Url(payload);
  const signingInput = `${headerB64}.${payloadB64}`;
  const sigBytes = await hmacSignSha256(toUtf8Bytes(secret), toUtf8Bytes(signingInput));
  const sigB64 = toBase64Url(sigBytes);
  return `${signingInput}.${sigB64}`;
}

export async function verifyJwtHS256(token: string, secret: string): Promise<{ valid: boolean; header: any | null; payload: any | null }>{
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return { valid: false, header: null, payload: null };
    const [h, p, s] = parts;
    const signingInput = `${h}.${p}`;
    const expected = await hmacSignSha256(toUtf8Bytes(secret), toUtf8Bytes(signingInput));
    const expectedB64 = toBase64Url(expected);
    const { header, payload } = decodeJwtParts(token);
    return { valid: s === expectedB64, header, payload };
  } catch {
    return { valid: false, header: null, payload: null };
  }
}

// ---------- General JWT claim helpers ----------

export function computeExpiresInSeconds(exp: number | null): number | null {
  if (!exp || typeof exp !== 'number') return null;
  const now = Math.floor(Date.now() / 1000);
  return Math.max(0, exp - now);
}

export function normalizeAudience(payload: any): string[] | null {
  if (!payload) return null;
  const aud = payload.aud;
  if (Array.isArray(aud)) return aud as string[];
  if (typeof aud === 'string') return [aud];
  return null;
}

export function extractRoles(payload: any): string[] | null {
  if (!payload) return null;
  const roles = payload?.realm_access?.roles ?? payload?.roles ?? payload?.groups ?? null;
  return Array.isArray(roles) ? roles : null;
}

// ---------- RS256 + JWKS (dev-only) ----------


export async function importRsaPublicKeyJwk(jwk: JsonWebKey): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify']
  );
}

export async function verifyJwtRS256WithJwk(token: string, jwk: JsonWebKey): Promise<{ valid: boolean; header: any | null; payload: any | null }>{
  try {
    const { header, payload, signature } = decodeJwtParts(token);
    if (!header || !payload || !signature) return { valid: false, header, payload };
    if (header.alg !== 'RS256') return { valid: false, header, payload };
    const [h, p] = token.split('.');
    const signingInput = `${h}.${p}`;
    const sigBytes = fromBase64Url(signature);
    const sigAb = ensureArrayBuffer(sigBytes);
    const dataBytes = new TextEncoder().encode(signingInput);
    const key = await importRsaPublicKeyJwk(jwk);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, sigAb, ensureArrayBuffer(dataBytes));
    return { valid: ok, header, payload };
  } catch {
    return { valid: false, header: null, payload: null };
  }
}

export async function fetchRealmJwks(kcBase: string, realm: string): Promise<{ keys: JsonWebKey[] }>{
  const url = `${kcBase}/realms/${realm}/protocol/openid-connect/certs`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`JWKS fetch failed: ${res.status}`);
  return res.json();
}
