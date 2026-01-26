import { Component, NgZone } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClient } from '@angular/common/http';
import { AUTH_MODES, AUTH_MODE_STORAGE_KEY, AuthMode } from './auth/modes';
import { AuthTokenService } from './auth/token.service';
import { tokenKey, refreshKey, STORAGE_STRATEGY_KEY } from './auth/storage';
import { AuthProvider, createAuthProvider, AuthConfig } from './auth/provider';
import { RefreshService } from './auth/refresh.service';
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
    { id: 'oidc-pkce', label: 'OIDC Code+PKCE', ready: true },
    { id: 'interceptor', label: 'Interceptor: Attach', ready: true },
    { id: 'refresh', label: '401→Refresh→Retry', ready: true },
    { id: 'storage', label: 'Storage Options', ready: true },
    { id: 'idle', label: 'Idle vs Expiry', ready: true },
    { id: 'multitab', label: 'Multi-Tab Sync', ready: true },
    { id: 'silent', label: 'Silent Re-auth', ready: false },
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

  // OIDC Code + PKCE (lab) debug state
  pkceDebug: any = null;

  // Interceptor lab state
  intTokenAttached = false; // quick probe after a call
  intValidation: any = null;
  intRss: any = null;
  intAdminStatus: number | null = null;
  intAdminBody: any = null;
  // Interceptor debug panel
  intAttached: boolean = false;
  intLastUrl: string | null = null;
  intLastHeader: string | null = null;
  intHealthz: any = null;
  intLastToken: string | null = null;
  intShowAttachedToken: boolean = false;
  // Refresh tab token view
  refreshAccessToken: string | null = null;
  refreshRefreshToken: string | null = null;
  // Storage tab state
  storageStrategy: 'memory' | 'session' | 'local' = 'session';
  storageMemToken: string | null = null;
  storageSessionToken: string | null = null;
  storageLocalToken: string | null = null;

  // Idle monitor state
  idleEnabled = false;
  idleTimeoutSec = 10; // default idle timeout seconds
  idleWarnSeconds = 10; // show warning when remaining <= this
  idleRemainingSec: number | null = null;
  idleAutoLogout = false;
  lastActivityAt: Date | null = null;
  private idleTimer: any = null;
  // Lab toggle: disable provider auto-logout on access expiry
  disableExpiryLogout = true;
  // Toast/banner for expiry notice
  expiryToastVisible = false;
  expiryToastMessage = 'Access token expired — will refresh on next API call.';

  // Multi-tab sync (BroadcastChannel + storage fallback)
  multitabEnabled = false;
  tabId: string = Math.random().toString(36).slice(2) + '-' + Date.now();
  private bc: BroadcastChannel | null = null;
  private bcPollTimer: any = null;
  private bcLastRaw: string | null = null;
  multiLastEvent: any = null;
  multiLog: Array<{ at: Date; from: string; type: string; payload?: any }> = [];

  constructor(private http: HttpClient, private authTokenSvc: AuthTokenService, private refreshSvc: RefreshService, private zone: NgZone){
    // Determine environment by port (dev: 4200, prod: 80)
    this.currentPort = window.location.port || (window.location.protocol === 'https:' ? '443' : '80');
    this.isDev = this.currentPort === '4200';
    this.envLabel = this.isDev ? `DEV (${this.currentPort})` : `PROD (${this.currentPort})`;
    this.apiLabel = this.isDev ? 'API: localhost:9000' : 'API: via /api';
    fetch('/api/healthz').then(r => r.json()).then(j => this.health = j).catch(e => this.health = { error: String(e) });
    // Load selected auth mode (default 'plain')
    const savedMode = sessionStorage.getItem(AUTH_MODE_STORAGE_KEY) as AuthMode | null;
    if (savedMode && this.authModes.includes(savedMode)) this.authMode = savedMode;
    // Load saved storage strategy preference
    try {
      const savedStrategy = sessionStorage.getItem(STORAGE_STRATEGY_KEY) as 'memory' | 'session' | 'local' | null;
      if (savedStrategy === 'memory' || savedStrategy === 'session' || savedStrategy === 'local') {
        this.storageStrategy = savedStrategy;
      }
    } catch (_) {}
    // Initialize provider based on mode
    this.provider = createAuthProvider(this.authMode);
    const cfg: AuthConfig = { realm: this.realm, kcBase: this.kcBase, clientId: this.clientId, redirectUri: this.redirectUri };
    this.provider.init(cfg).then(state => {
      this.loggedIn = state.loggedIn;
      this.accessToken = state.accessToken;
      this.authTokenSvc.setToken(this.accessToken);
      this.accessTokenExp = state.accessTokenExp;
      this.tokenPayload = state.tokenPayload;
      this.error = state.error || '';
      this.loadPkceDebug();
      this.refreshInterceptorDebug();
    }).catch(err => {
      this.error = String(err);
    });
    // Subscribe to provider state changes (e.g., expiry)
    this.provider.subscribe(state => {
      this.loggedIn = state.loggedIn;
      this.accessToken = state.accessToken;
      this.authTokenSvc.setToken(this.accessToken);
      this.accessTokenExp = state.accessTokenExp;
      this.tokenPayload = state.tokenPayload;
      this.error = state.error || '';
      this.updateBasicsDerived();
      this.loadPkceDebug();
      this.refreshInterceptorDebug();
    });
    // Load lab toggle from sessionStorage
    try {
      const v = sessionStorage.getItem('lab:disable-expiry-logout');
      if (v === '0') this.disableExpiryLogout = false;
      else if (v === '1') this.disableExpiryLogout = true;
      else sessionStorage.setItem('lab:disable-expiry-logout', this.disableExpiryLogout ? '1' : '0');
    } catch {}
    // Fallback storage listener for multi-tab (Safari or disabled BroadcastChannel)
    window.addEventListener('storage', (e) => {
      try {
        if (e.key !== 'auth:bc' || !e.newValue) return;
        const msg = JSON.parse(e.newValue || '{}');
        this.zone.run(() => this.multiHandle(msg));
      } catch {}
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
      this.loadPkceDebug();
      this.refreshInterceptorDebug();
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
      this.loadPkceDebug();
      this.refreshInterceptorDebug();
    });
  }

  async login() { this.provider.login(); }

  logout() {
    try { if (this.multitabEnabled) this.multiBroadcast('logout'); } catch {}
    this.provider.logout();
  }

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

  // ----- OIDC Code + PKCE (lab) -----
  loadPkceDebug() {
    try {
      const anyProvider: any = this.provider as any;
      if (typeof anyProvider.getPkceDebug === 'function') {
        this.pkceDebug = anyProvider.getPkceDebug();
      }
    } catch (e) {
      this.error = 'PKCE debug failed: ' + String(e);
    }
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
    // Toggle expiry toast when using lab mode (no auto-logout)
    const remaining = this.accessTokenExpiresIn;
    if (this.disableExpiryLogout && this.loggedIn && remaining === 0) {
      this.expiryToastVisible = true;
    } else if (typeof remaining === 'number' && remaining > 0) {
      this.expiryToastVisible = false;
    } else if (!this.loggedIn) {
      this.expiryToastVisible = false;
    }
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

  // ----- Interceptor lab: call APIs via Angular HttpClient -----
  async intValidateToken() {
    try {
      const resp = await this.http.get('/api/token/validate', { observe: 'response' }).toPromise();
      this.intTokenAttached = !!resp?.headers.get('x-token-attached'); // optional if API echoes; else keep false
      this.intValidation = resp?.body ?? null;
    } catch (e: any) {
      this.intValidation = { error: String(e?.message ?? e) };
    }
    this.refreshInterceptorDebug();
  }

  async intFetchRss() {
    try {
      const body = await this.http.get('/api/rss').toPromise();
      this.intRss = body ?? null;
    } catch (e: any) {
      this.intRss = { error: String(e?.message ?? e) };
    }
    this.refreshInterceptorDebug();
  }
  // ----- Refresh demo helpers -----
  forceExpireToken() {
    // Simulate an expired/invalid access token so interceptor attaches it,
    // receives 401, then triggers refresh using the stored refresh_token.
    try {
      const key = 'token:news:news-web';
      sessionStorage.setItem(key, 'invalid');
      this.authTokenSvc.setToken('invalid');
      this.error = '';
    } catch (_) {}
    this.refreshInterceptorDebug();
  }

  async intFetchRssRefreshDemo() {
    // Same endpoint as intFetchRss, but leave state separate for clarity
    try {
      const body = await this.http.get('/api/rss').toPromise();
      this.intRss = body ?? null;
    } catch (e: any) {
      this.intRss = { error: String(e?.message ?? e) };
    }
    this.refreshInterceptorDebug();
  }

  async rotateRefreshTokenNow() {
    // Proactively call refresh grant to rotate tokens without forcing a 401
    try {
      await this.refreshSvc.refresh();
    } catch (_) {}
    this.refreshInterceptorDebug();
  }

  async intAdminPing() {
    this.intAdminStatus = null;
    this.intAdminBody = null;
    try {
      const resp = await this.http.get('/api/admin/ping', { observe: 'response' }).toPromise();
      this.intAdminStatus = resp?.status ?? null;
      this.intAdminBody = resp?.body ?? null;
    } catch (e: any) {
      // Angular throws on non-2xx; capture status/body if present
      if (e?.status) {
        this.intAdminStatus = e.status;
        this.intAdminBody = e.error ?? e.message;
      } else {
        this.intAdminBody = { error: String(e?.message ?? e) };
      }
    }
    this.refreshInterceptorDebug();
  }

  async intHealthzHttp() {
    try {
      const body = await this.http.get('/api/healthz').toPromise();
      this.intHealthz = body ?? null;
    } catch (e: any) {
      this.intHealthz = { error: String(e?.message ?? e) };
    }
    this.refreshInterceptorDebug();
  }

  private refreshInterceptorDebug() {
    this.intAttached = this.authTokenSvc.getLastAttached();
    this.intLastUrl = this.authTokenSvc.getLastUrl();
    this.intLastHeader = this.authTokenSvc.getLastAuthHeader();
    this.intLastToken = this.authTokenSvc.getLastToken();
    // Update Refresh tab token view
    try {
      const tKey = tokenKey(this.realm, this.clientId);
      const rKey = refreshKey(this.realm, this.clientId);
      this.refreshAccessToken = sessionStorage.getItem(tKey);
      this.refreshRefreshToken = sessionStorage.getItem(rKey);
    } catch (_) {}
  }

  // Dev helper: hook XHR header setting to demonstrate attacker capture of Authorization
  headerHookEnabled = false;
  runHeaderHook() {
    if (this.headerHookEnabled) return;
    try {
      const xhrProto: any = (XMLHttpRequest as any).prototype;
      if (!xhrProto || !xhrProto.setRequestHeader) return;
      const original = xhrProto.setRequestHeader;
      const self = this;
      xhrProto.setRequestHeader = function(k: any, v: any) {
        try {
          if ((k || '').toString().toLowerCase() === 'authorization') {
            // eslint-disable-next-line no-console
            console.log('[demo-xhr-hook] captured header:', v);
            self.intLastHeader = `Authorization: ${v}`;
          }
        } catch {}
        return original.apply(this, arguments as any);
      };
      // Also hook fetch for completeness (if HttpClient ever uses fetch)
      try {
        const wAny: any = window as any;
        const origFetch = wAny.fetch?.bind(window);
        if (origFetch) {
          wAny.fetch = function(input: any, init: any) {
            try {
              // Inspect headers from init or Request object
              let headers: any = null;
              if (init && init.headers) headers = init.headers;
              else if (input && input.headers) headers = input.headers;
              let auth: string | null = null;
              if (headers) {
                try {
                  if (headers instanceof Headers) {
                    auth = headers.get('Authorization');
                  } else if (Array.isArray(headers)) {
                    for (const [k, v] of headers) { if ((k || '').toLowerCase() === 'authorization') { auth = String(v); break; } }
                  } else if (typeof headers === 'object') {
                    for (const k of Object.keys(headers)) { if (k.toLowerCase() === 'authorization') { auth = String((headers as any)[k]); break; } }
                  }
                } catch {}
              }
              if (auth) {
                // eslint-disable-next-line no-console
                console.log('[demo-fetch-hook] captured header:', auth);
                self.intLastHeader = `Authorization: ${auth}`;
              }
            } catch {}
            return origFetch(input, init);
          };
        }
      } catch {}
      this.headerHookEnabled = true;
      // Prepare environment for the demo: use memory, clear others, set in-memory token
      try {
        const key = tokenKey(this.realm, this.clientId);
        try { sessionStorage.removeItem(key); } catch {}
        try { localStorage.removeItem(key); } catch {}
        this.storageStrategy = 'memory';
        try { sessionStorage.setItem(STORAGE_STRATEGY_KEY, 'memory'); } catch {}
        // Seed a token into memory from best available source
        let seed: string | null = this.accessToken || null;
        try { if (!seed) seed = this.authTokenSvc.getToken(); } catch {}
        try { if (!seed) seed = sessionStorage.getItem(key); } catch {}
        try { if (!seed) seed = localStorage.getItem(key); } catch {}
        if (seed) this.authTokenSvc.setToken(seed);
        this.storageRefreshView();
      } catch {}
    } catch {}
  }

  // Convenience: trigger a safe call to show the hook capturing Authorization
  runHookTestCall() {
    if (!this.headerHookEnabled) this.runHeaderHook();
    this.intHealthzHttp();
  }

  // ---------- Storage tab helpers ----------
  storageSelect(strategy: 'memory' | 'session' | 'local') {
    this.storageStrategy = strategy;
    try { sessionStorage.setItem(STORAGE_STRATEGY_KEY, strategy); } catch (_) {}
    this.storageRefreshView();
  }

  storageSaveToSelected() {
    const token = this.accessToken;
    if (!token) return;
    const key = tokenKey(this.realm, this.clientId);
    try {
      if (this.storageStrategy === 'memory') {
        this.authTokenSvc.setToken(token);
      } else if (this.storageStrategy === 'session') {
        sessionStorage.setItem(key, token);
      } else if (this.storageStrategy === 'local') {
        localStorage.setItem(key, token);
      }
    } catch (_) {}
    this.storageRefreshView();
  }

  storageClearSelected() {
    const key = tokenKey(this.realm, this.clientId);
    try {
      if (this.storageStrategy === 'memory') {
        this.authTokenSvc.setToken(null);
      } else if (this.storageStrategy === 'session') {
        sessionStorage.removeItem(key);
      } else if (this.storageStrategy === 'local') {
        localStorage.removeItem(key);
      }
    } catch (_) {}
    this.storageRefreshView();
  }

  storageRefreshView() {
    try {
      const key = tokenKey(this.realm, this.clientId);
      this.storageMemToken = this.authTokenSvc.getToken();
      this.storageSessionToken = sessionStorage.getItem(key);
      this.storageLocalToken = localStorage.getItem(key);
    } catch (_) {}
  }

  // ---------- Idle monitor helpers ----------
  private startIdleTimer() {
    this.stopIdleTimer();
    this.lastActivityAt = new Date();
    this.idleRemainingSec = this.idleTimeoutSec;
    this.idleTimer = setInterval(() => {
      if (!this.lastActivityAt) return;
      const elapsed = Math.floor((Date.now() - this.lastActivityAt.getTime()) / 1000);
      const remaining = Math.max(this.idleTimeoutSec - elapsed, 0);
      this.idleRemainingSec = remaining;
      if (remaining === 0) {
        this.stopIdleTimer();
        if (this.idleAutoLogout && this.loggedIn) {
          // Trigger provider logout once
          try { this.logout(); } catch {}
        }
      }
    }, 1000);
  }

  private stopIdleTimer() {
    if (this.idleTimer) {
      try { clearInterval(this.idleTimer); } catch {}
      this.idleTimer = null;
    }
  }

  private bindIdleActivityListeners() {
    const handler = () => this.recordActivity();
    window.addEventListener('mousemove', handler);
    window.addEventListener('keydown', handler);
    window.addEventListener('click', handler);
    window.addEventListener('scroll', handler, { passive: true } as any);
    window.addEventListener('touchstart', handler, { passive: true } as any);
    // Store a reference to remove later
    (this as any)._idleHandler = handler;
  }

  private unbindIdleActivityListeners() {
    const handler = (this as any)._idleHandler;
    if (!handler) return;
    try {
      window.removeEventListener('mousemove', handler);
      window.removeEventListener('keydown', handler);
      window.removeEventListener('click', handler);
      window.removeEventListener('scroll', handler as any);
      window.removeEventListener('touchstart', handler as any);
    } catch {}
    (this as any)._idleHandler = null;
  }

  idleToggle() {
    this.idleEnabled = !this.idleEnabled;
    if (this.idleEnabled) {
      this.startIdleTimer();
      this.bindIdleActivityListeners();
    } else {
      this.stopIdleTimer();
      this.unbindIdleActivityListeners();
      this.idleRemainingSec = null;
    }
  }

  recordActivity() {
    if (!this.idleEnabled) return;
    this.lastActivityAt = new Date();
    this.idleRemainingSec = this.idleTimeoutSec;
  }

  recordActivitySimulate() { this.recordActivity(); }

  applyExpiryLogoutSetting() {
    try { sessionStorage.setItem('lab:disable-expiry-logout', this.disableExpiryLogout ? '1' : '0'); } catch {}
  }

  dismissExpiryToast() { this.expiryToastVisible = false; }

  // ---------- Multi-tab sync helpers ----------
  multitabToggle(value?: boolean) {
    // Explicitly accept new value from ngModelChange and apply
    if (typeof value === 'boolean') this.multitabEnabled = value;
    if (this.multitabEnabled) this.multiInit(); else this.multiClose();
  }

  private multiInit() {
    try {
      if ('BroadcastChannel' in window) {
        this.bc = new (window as any).BroadcastChannel('news-auth');
        const bcAny: any = this.bc as any;
        bcAny.onmessage = (ev: MessageEvent) => {
          try { this.zone.run(() => this.multiHandle(ev.data)); } catch {}
        };
      } else {
        this.bc = null;
      }
      // Poll fallback: detect localStorage changes even if 'storage' events don't fire
      if (!this.bcPollTimer) {
        this.bcLastRaw = null;
        this.bcPollTimer = setInterval(() => {
          try {
            const raw = localStorage.getItem('auth:bc');
            if (raw && raw !== this.bcLastRaw) {
              this.bcLastRaw = raw;
              const msg = JSON.parse(raw);
              this.zone.run(() => this.multiHandle(msg));
            }
          } catch {}
        }, 1000);
      }
      // Announce presence
      this.multiBroadcast('ping');
    } catch {}
  }

  private multiClose() {
    try { if (this.bc) { this.bc.close(); this.bc = null; } } catch {}
    try { if (this.bcPollTimer) { clearInterval(this.bcPollTimer); this.bcPollTimer = null; } } catch {}
  }

  multiBroadcast(type: 'logout' | 'refresh' | 'ping', payload?: any) {
    const msg = { from: this.tabId, type, payload, at: Date.now() };
    try { if (this.bc) this.bc.postMessage(msg); } catch {}
    try { localStorage.setItem('auth:bc', JSON.stringify(msg)); } catch {}
    this.multiRecord(msg);
  }

  private multiHandle(msg: any) {
    if (!msg || !this.multitabEnabled) return;
    const { from, type, payload } = msg;
    // Ignore self
    if (from === this.tabId) return;
    this.multiLastEvent = { type, from, payload, at: new Date() };
    this.multiRecord(msg);
    if (type === 'logout') {
      try { this.provider.logout(); } catch {}
    }
    if (type === 'refresh' && payload && payload.access) {
      const access: string = payload.access;
      try {
        const tKey = tokenKey(this.realm, this.clientId);
        sessionStorage.setItem(tKey, access);
      } catch {}
      // Update interceptor source and local state
      try { this.authTokenSvc.setToken(access); } catch {}
      try {
        const parts = decodeJwtParts(access);
        this.accessToken = access;
        this.accessTokenExp = (typeof parts.payload?.exp === 'number') ? parts.payload.exp : null;
        this.tokenPayload = parts.payload || null;
        this.loggedIn = !!access;
        this.error = '';
        this.updateBasicsDerived();
        this.refreshInterceptorDebug();
      } catch {}
    }
    // Future: handle 'refresh' coordination here
  }

  private multiRecord(msg: any) {
    try {
      this.multiLog.unshift({ at: new Date(), from: msg?.from, type: msg?.type, payload: msg?.payload });
      if (this.multiLog.length > 10) this.multiLog.pop();
    } catch {}
  }
}
