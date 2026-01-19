import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AUTH_MODES, AUTH_MODE_STORAGE_KEY, AuthMode } from './auth/modes';
import { AuthProvider, createAuthProvider, AuthConfig } from './auth/provider';
import { createJwtHS256, decodeJwtParts, verifyJwtHS256, computeExpiresInSeconds, normalizeAudience, extractRoles, fetchRealmJwks, verifyJwtRS256WithJwk } from './utils';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent {
  health: any = { loading: true };
  loggedIn = false;
  accessToken: string | null = null;
  accessTokenExp: number | null = null;
  tokenPayload: any = null;
  tokenTimer: any = null;
  tokenValidation: any = null;
  rss: any = null;
  adminPingStatus: number | null = null;
  adminPingResponse: any = null;
  error: string = '';
  showToken = false;
  authMode: AuthMode = 'plain';
  authModes = AUTH_MODES;
  // Environment indicator
  isDev = false;
  currentPort = '';
  envLabel = '';
  apiLabel = '';
  private provider!: AuthProvider;
  private realm = 'news';
  private kcBase = 'https://localhost:8443';
  private clientId = 'news-web';
  private redirectUri = window.location.origin + '/';
  accountUrl = `${this.kcBase}/realms/${this.realm}/account`;

  // JWT Lab (basic) state
  labSecret = 'secret';
  labPayloadText = '{"sub":"123","name":"Alice","iat":' + Math.floor(Date.now()/1000) + '}';
  labGenerated = '';
  labInput = '';
  labDecodedHeader: any = null;
  labDecodedPayload: any = null;
  labVerify: boolean | null = null;
  labError = '';
  labTtl = 120; // default TTL seconds for lab-generated tokens
  labExpiresIn: number | null = null;
  private labTimer: any = null;

  // JWT Lab tabs
  labTabs = [
    { id: 'hs256-basic', label: 'HS256 (basic)', ready: true },
    { id: 'rs256-jwks', label: 'RS256 + JWKS', ready: true },
    { id: 'oidc-pkce', label: 'OIDC Code+PKCE', ready: false },
    { id: 'interceptor', label: 'Interceptor: Attach', ready: false },
    { id: 'refresh', label: '401→Refresh→Retry', ready: false },
    { id: 'storage', label: 'Storage Options', ready: false },
    { id: 'idle', label: 'Idle vs Expiry', ready: false },
    { id: 'multitab', label: 'Multi-Tab Sync', ready: false },
  ];
  selectedLabTab = 'hs256-basic';

  // Main tabs (Basics / JWT Lab)
  mainTabs = [
    { id: 'basics', label: 'Basics' },
    { id: 'jwt-lab', label: 'JWT Lab' },
  ];
  selectedMainTab = 'basics';
  accessTokenExpiresIn: number | null = null;
  accessHeader: any = null;
  basicsClaims: {
    alg?: string;
    issOk?: boolean;
    aud?: string[] | null;
    expOk?: boolean;
    subOk?: boolean;
    roles?: string[] | null;
  } = {};

  // RS256 + JWKS (dev-only) state
  rsTokenInput = '';
  rsDecodedHeader: any = null;
  rsDecodedPayload: any = null;
  rsKid: string | null = null;
  rsVerify: boolean | null = null;
  rsError = '';
  rsJwks: JsonWebKey[] = [];

  constructor(){
    // Determine environment by port (dev: 4200, prod: 80)
    this.currentPort = window.location.port || (window.location.protocol === 'https:' ? '443' : '80');
    this.isDev = this.currentPort === '4200';
    this.envLabel = this.isDev ? `DEV (${this.currentPort})` : `PROD (${this.currentPort})`;
    this.apiLabel = this.isDev ? 'API: localhost:9000' : 'API: via /api';
    fetch('/api/healthz').then(r => r.json()).then(j => this.health = j).catch(e => this.health = { error: String(e) });
    // Load selected auth mode (default 'plain')
    const savedMode = sessionStorage.getItem(AUTH_MODE_STORAGE_KEY) as AuthMode | null;
    if (savedMode && this.authModes.includes(savedMode)) this.authMode = savedMode;
    // Initialize provider based on mode
    this.provider = createAuthProvider(this.authMode);
    const cfg: AuthConfig = { realm: this.realm, kcBase: this.kcBase, clientId: this.clientId, redirectUri: this.redirectUri };
    this.provider.init(cfg).then(state => {
      this.loggedIn = state.loggedIn;
      this.accessToken = state.accessToken;
      this.accessTokenExp = state.accessTokenExp;
      this.tokenPayload = state.tokenPayload;
      this.error = state.error || '';
    }).catch(err => {
      this.error = String(err);
    });
    // Subscribe to provider state changes (e.g., expiry)
    this.provider.subscribe(state => {
      this.loggedIn = state.loggedIn;
      this.accessToken = state.accessToken;
      this.accessTokenExp = state.accessTokenExp;
      this.tokenPayload = state.tokenPayload;
      this.error = state.error || '';
      this.updateBasicsDerived();
    });
  }

  onModeChange(evt: Event) {
    const value = (evt.target as HTMLSelectElement).value as AuthMode;
    this.setAuthMode(value);
  }

  setAuthMode(mode: AuthMode) {
    if (!this.authModes.includes(mode)) return;
    this.authMode = mode;
    try { sessionStorage.setItem(AUTH_MODE_STORAGE_KEY, mode); } catch (_) {}
    // Clear transient errors when switching modes
    this.error = '';
    // Recreate provider for new mode
    this.provider = createAuthProvider(this.authMode);
    const cfg: AuthConfig = { realm: this.realm, kcBase: this.kcBase, clientId: this.clientId, redirectUri: this.redirectUri };
    this.provider.init(cfg).then(state => {
      this.loggedIn = state.loggedIn;
      this.accessToken = state.accessToken;
      this.accessTokenExp = state.accessTokenExp;
      this.tokenPayload = state.tokenPayload;
      this.error = state.error || '';
    }).catch(err => {
      this.error = String(err);
    });
    this.provider.subscribe(state => {
      this.loggedIn = state.loggedIn;
      this.accessToken = state.accessToken;
      this.accessTokenExp = state.accessTokenExp;
      this.tokenPayload = state.tokenPayload;
      this.error = state.error || '';
      this.updateBasicsDerived();
    });
  }

  async login() { this.provider.login(); }

  logout() { this.provider.logout(); }

  async validateToken() {
    this.error = '';
    this.tokenValidation = null;
    try {
      this.tokenValidation = await this.provider.validateToken();
    } catch (e) {
      this.error = 'Validate failed: ' + String(e);
    }
  }

  async fetchRss() {
    this.error = '';
    this.rss = null;
    try {
      this.rss = await this.provider.fetchRss();
    } catch (e) {
      this.error = 'RSS failed: ' + String(e);
    }
  }

  async adminPing() {
    this.error = '';
    this.adminPingStatus = null;
    this.adminPingResponse = null;
    try {
      const { status, body } = await this.provider.adminPing();
      this.adminPingStatus = status;
      this.adminPingResponse = body;
    } catch (e) {
      this.error = 'Admin ping failed: ' + String(e);
    }
  }

  toggleToken() { this.showToken = !this.showToken; }
  async copyToken() {
    if (!this.accessToken) return;
    try {
      await navigator.clipboard.writeText(this.accessToken);
    } catch (e) {
      this.error = 'Copy failed: ' + String(e);
    }
  }

  // ---------- JWT Lab (basic, HS256) ----------
  async labGenerate() {
    this.labError = '';
    try {
      const payload = JSON.parse(this.labPayloadText || '{}');
      const now = Math.floor(Date.now()/1000);
      if (typeof payload.exp !== 'number') {
        payload.exp = now + (this.labTtl || 0);
      }
      this.labGenerated = await createJwtHS256(payload, this.labSecret || '');
      this.labInput = this.labGenerated;
      const parts = decodeJwtParts(this.labGenerated);
      this.labDecodedHeader = parts.header;
      this.labDecodedPayload = parts.payload;
      const v = await verifyJwtHS256(this.labGenerated, this.labSecret || '');
      this.labVerify = v.valid;
      this.updateLabExpires();
    } catch (e) {
      this.labError = 'Generate failed: ' + String(e);
    }
  }

  labDecode() {
    this.labError = '';
    try {
      const parts = decodeJwtParts(this.labInput || '');
      this.labDecodedHeader = parts.header;
      this.labDecodedPayload = parts.payload;
      this.updateLabExpires();
    } catch (e) {
      this.labError = 'Decode failed: ' + String(e);
    }
  }

  async labVerifyNow() {
    this.labError = '';
    try {
      const v = await verifyJwtHS256(this.labInput || '', this.labSecret || '');
      this.labVerify = v.valid;
      this.labDecodedHeader = v.header;
      this.labDecodedPayload = v.payload;
      this.updateLabExpires();
    } catch (e) {
      this.labError = 'Verify failed: ' + String(e);
    }
  }

  selectLabTab(id: string) {
    this.selectedLabTab = id;
  }

  selectMainTab(id: string) {
    this.selectedMainTab = id;
  }

  private stopAccessCountdown() {
    if (this.tokenTimer) {
      try { clearInterval(this.tokenTimer); } catch {}
      this.tokenTimer = null;
    }
  }

  private startAccessCountdown() {
    this.stopAccessCountdown();
    this.accessTokenExpiresIn = computeExpiresInSeconds(this.accessTokenExp);
    if (this.accessTokenExp) {
      this.tokenTimer = setInterval(() => {
        this.accessTokenExpiresIn = computeExpiresInSeconds(this.accessTokenExp);
        if (this.accessTokenExpiresIn === 0) this.stopAccessCountdown();
      }, 1000);
    }
  }

  private updateBasicsDerived() {
    // Update countdown
    this.startAccessCountdown();
    // Update header/claims
    this.accessHeader = this.accessToken ? decodeJwtParts(this.accessToken).header : null;
    const payload: any = this.tokenPayload || null;
    const audNorm: string[] | null = normalizeAudience(payload);
    const roles: string[] | null = extractRoles(payload);
    const expOk = typeof this.accessTokenExp === 'number' ? (computeExpiresInSeconds(this.accessTokenExp) || 0) > 0 : false;
    this.basicsClaims = {
      alg: this.accessHeader?.alg,
      issOk: typeof payload?.iss === 'string' && payload.iss.length > 0,
      aud: audNorm,
      expOk,
      subOk: typeof payload?.sub === 'string' && payload.sub.length > 0,
      roles: Array.isArray(roles) ? roles : null,
    };
  }

  private stopLabCountdown() {
    if (this.labTimer) {
      try { clearInterval(this.labTimer); } catch {}
      this.labTimer = null;
    }
  }

  private updateLabExpires() {
    const exp = this.labDecodedPayload && typeof this.labDecodedPayload.exp === 'number' ? this.labDecodedPayload.exp : null;
    this.labExpiresIn = computeExpiresInSeconds(exp);
    this.stopLabCountdown();
    if (exp) {
      this.labTimer = setInterval(() => {
        this.labExpiresIn = computeExpiresInSeconds(exp);
        if (this.labExpiresIn === 0) this.stopLabCountdown();
      }, 1000);
    }
  }

  // ---------- RS256 + JWKS (dev-only) ----------
  rsDecodeToken() {
    this.rsError = '';
    try {
      const parts = decodeJwtParts(this.rsTokenInput || '');
      this.rsDecodedHeader = parts.header;
      this.rsDecodedPayload = parts.payload;
      this.rsKid = parts.header?.kid || null;
      this.rsVerify = null;
    } catch (e) {
      this.rsError = 'Decode failed: ' + String(e);
    }
  }

  async rsFetchJwks() {
    this.rsError = '';
    try {
      const jwks = await fetchRealmJwks(this.kcBase, this.realm);
      this.rsJwks = jwks.keys || [];
    } catch (e) {
      this.rsError = 'JWKS fetch failed: ' + String(e);
    }
  }

  async rsVerifyWithJwks() {
    this.rsError = '';
    this.rsVerify = null;
    try {
      if (!this.rsKid) throw new Error('Token header missing kid');
      if (!this.rsJwks || this.rsJwks.length === 0) throw new Error('JWKS not loaded');
      const jwk = this.rsJwks.find(k => (k as any).kid === this.rsKid);
      if (!jwk) throw new Error('Matching JWK not found for kid=' + this.rsKid);
      const result = await verifyJwtRS256WithJwk(this.rsTokenInput || '', jwk);
      this.rsVerify = result.valid;
      this.rsDecodedHeader = result.header;
      this.rsDecodedPayload = result.payload;
    } catch (e) {
      this.rsError = 'Verify failed: ' + String(e);
    }
  }
}
