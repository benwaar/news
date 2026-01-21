import { AuthConfig, AuthProvider, AuthState } from './provider';
import { computeCodeChallenge, decodeJwt, decodeJwtExp, generateCodeVerifier } from '../utils';
import { pkceKey, tokenKey, refreshKey } from './storage';

export class PlainAuthProvider implements AuthProvider {
  private cfg!: AuthConfig;
  private apiBase: string = '';
  private accessToken: string | null = null;
  private accessTokenExp: number | null = null;
  private tokenPayload: any = null;
  private tokenTimer: any = null;
  private subscribers: Array<(s: AuthState) => void> = [];
  // Dev-only PKCE + flow debug
  private pkceVerifier: string | null = null;
  private pkceChallenge: string | null = null;
  private lastAuthUrl: string | null = null;
  private lastTokenRequest: Record<string, string> | null = null;
  private lastTokenResponse: any = null;

  async init(config: AuthConfig): Promise<AuthState> {
    this.cfg = config;
    // Use UI gateway directly in dev to avoid proxy SSL issues
    try {
      const port = window.location.port || (window.location.protocol === 'https:' ? '443' : '80');
      this.apiBase = port === '4200' ? 'https://localhost' : '';
    } catch (_) { this.apiBase = ''; }
    // Load PKCE verifier (if present) and compute challenge for display
    try {
      const storedVerifier = sessionStorage.getItem(pkceKey(this.cfg.realm, this.cfg.clientId));
      if (storedVerifier) {
        this.pkceVerifier = storedVerifier;
        // compute challenge for lab display
        computeCodeChallenge(storedVerifier).then(ch => { this.pkceChallenge = ch; }).catch(() => {});
      }
    } catch (_) {}
    try {
      const params = new URLSearchParams(window.location.search);
      const code = params.get('code');
      if (code) {
        await this.exchangeCodeForToken(code);
        // Clean URL after handling login
        history.replaceState({}, document.title, window.location.origin + window.location.pathname);
      } else {
        // Load from session storage for dev convenience
        const stored = sessionStorage.getItem(tokenKey(this.cfg.realm, this.cfg.clientId));
        if (stored) {
          this.accessToken = stored;
        }
      }
    } catch (e) {
      return { loggedIn: false, accessToken: null, accessTokenExp: null, tokenPayload: null, error: String(e) };
    }
    this.accessTokenExp = decodeJwtExp(this.accessToken);
    this.tokenPayload = decodeJwt(this.accessToken);
    this.startTokenExpiryWatcher();
    const state = {
      loggedIn: !!this.accessToken,
      accessToken: this.accessToken,
      accessTokenExp: this.accessTokenExp,
      tokenPayload: this.tokenPayload
    };
    this.emit(state);
    return state;
  }

  login(): void {
    const codeVerifier = generateCodeVerifier();
    this.pkceVerifier = codeVerifier;
    computeCodeChallenge(codeVerifier).then(codeChallenge => {
      this.pkceChallenge = codeChallenge;
      try { sessionStorage.setItem(pkceKey(this.cfg.realm, this.cfg.clientId), codeVerifier); } catch (_) {}
      const url = `${this.cfg.kcBase}/realms/${this.cfg.realm}/protocol/openid-connect/auth` +
        `?client_id=${encodeURIComponent(this.cfg.clientId)}` +
        `&redirect_uri=${encodeURIComponent(this.cfg.redirectUri)}` +
        `&response_type=code&scope=${encodeURIComponent('openid profile email')}` +
        `&code_challenge_method=S256&code_challenge=${encodeURIComponent(codeChallenge)}`;
      this.lastAuthUrl = url;
      window.location.href = url;
    });
  }

  logout(): void {
    this.stopTokenExpiryWatcher();
    try {
      sessionStorage.removeItem(pkceKey(this.cfg.realm, this.cfg.clientId));
      sessionStorage.removeItem(tokenKey(this.cfg.realm, this.cfg.clientId));
      sessionStorage.removeItem(refreshKey(this.cfg.realm, this.cfg.clientId));
    } catch (_) {}
    const url = `${this.cfg.kcBase}/realms/${this.cfg.realm}/protocol/openid-connect/logout` +
      `?client_id=${encodeURIComponent(this.cfg.clientId)}` +
      `&post_logout_redirect_uri=${encodeURIComponent(this.cfg.redirectUri)}`;
    window.location.href = url;
  }

  getAccessToken(): string | null { return this.accessToken; }

  async validateToken(): Promise<any> {
    if (!this.accessToken) return null;
    const resp = await fetch(`${this.apiBase}/api/token/validate`, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    const ct = resp.headers.get('content-type') || '';
    if (ct.includes('application/json')) {
      return await resp.json();
    }
    const text = await resp.text();
    return { status: resp.status, contentType: ct, body: text };
  }

  async fetchRss(): Promise<any> {
    if (!this.accessToken) return null;
    const resp = await fetch(`${this.apiBase}/api/rss`, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    return await resp.json();
  }

  async adminPing(): Promise<{ status: number; body: any }> {
    if (!this.accessToken) return { status: 0, body: null };
    const resp = await fetch(`${this.apiBase}/api/admin/ping`, {
      headers: { 'Authorization': `Bearer ${this.accessToken}` }
    });
    let body: any;
    try { body = await resp.json(); } catch (_) { body = await resp.text(); }
    return { status: resp.status, body };
  }

  subscribe(listener: (state: AuthState) => void): void {
    this.subscribers.push(listener);
  }

  private emit(state?: AuthState) {
    const s: AuthState = state ?? {
      loggedIn: !!this.accessToken,
      accessToken: this.accessToken,
      accessTokenExp: this.accessTokenExp,
      tokenPayload: this.tokenPayload
    };
    for (const fn of this.subscribers) {
      try { fn(s); } catch (_) {}
    }
  }


  private async exchangeCodeForToken(code: string) {
    const verifier = sessionStorage.getItem(pkceKey(this.cfg.realm, this.cfg.clientId));
    if (!verifier) throw new Error('Missing PKCE verifier');
    const body = new URLSearchParams();
    body.set('grant_type', 'authorization_code');
    body.set('client_id', this.cfg.clientId);
    body.set('code', code);
    body.set('redirect_uri', this.cfg.redirectUri);
    body.set('code_verifier', verifier);
    this.lastTokenRequest = {
      grant_type: 'authorization_code',
      client_id: this.cfg.clientId,
      code,
      redirect_uri: this.cfg.redirectUri,
      code_verifier: verifier,
    };
    const tokenUrl = `${this.cfg.kcBase}/realms/${this.cfg.realm}/protocol/openid-connect/token`;
    const resp = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString()
    });
    if (!resp.ok) {
      const txt = await resp.text();
      throw new Error(`Token endpoint ${resp.status}: ${txt}`);
    }
    const json = await resp.json();
    this.lastTokenResponse = json;
    this.accessToken = json.access_token || null;
    const refresh = json.refresh_token || null;
    this.accessTokenExp = decodeJwtExp(this.accessToken);
    this.tokenPayload = decodeJwt(this.accessToken);
    try {
      if (this.accessToken) sessionStorage.setItem(tokenKey(this.cfg.realm, this.cfg.clientId), this.accessToken);
      if (refresh) sessionStorage.setItem(refreshKey(this.cfg.realm, this.cfg.clientId), refresh);
    } catch (_) {}
    this.startTokenExpiryWatcher();
    this.emit();
  }

  private startTokenExpiryWatcher() {
    this.stopTokenExpiryWatcher();
    this.tokenTimer = setInterval(() => {
      if (!this.accessTokenExp) return;
      const now = Math.floor(Date.now() / 1000);
      if (now >= this.accessTokenExp) {
        this.accessToken = null;
        this.accessTokenExp = null;
        this.tokenPayload = null;
        try { sessionStorage.removeItem(tokenKey(this.cfg.realm, this.cfg.clientId)); } catch (_) {}
        this.emit({ loggedIn: false, accessToken: null, accessTokenExp: null, tokenPayload: null, error: 'Session expired — please login again.' });
        this.stopTokenExpiryWatcher();
      }
    }, 1000);
  }

  private stopTokenExpiryWatcher() {
    if (this.tokenTimer) {
      clearInterval(this.tokenTimer);
      this.tokenTimer = null;
    }
  }

  // Dev-only: expose PKCE and flow details for the lab UI
  getPkceDebug(): any {
    return {
      mode: 'plain',
      verifier: this.pkceVerifier,
      challenge: this.pkceChallenge,
      challenge_method: this.pkceChallenge ? 'S256' : null,
      auth_url: this.lastAuthUrl,
      token_request: this.lastTokenRequest,
      token_response: this.lastTokenResponse,
    };
  }
}
