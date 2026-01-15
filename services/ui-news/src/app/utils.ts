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
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const json = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'));
    return JSON.parse(json);
  } catch {
    return null;
  }
}

export function decodeJwtExp(token: string | null): number | null {
  const payload = decodeJwt(token);
  return payload && typeof payload.exp === 'number' ? payload.exp : null;
}
