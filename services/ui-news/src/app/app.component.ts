import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule],
  template: `
    <h1>News UI (Angular)</h1>
    <div class="badge">Realm: <strong>news</strong>
      <button (click)="login()" *ngIf="!loggedIn">Login</button>
      <button (click)="logout()" *ngIf="loggedIn">Logout</button>
    </div>
    <p>API health via UI proxy:</p>
    <pre>{{ health | json }}</pre>
    <div *ngIf="loggedIn">
      <p style="margin: 8px 0;">
        <a [href]="accountUrl" target="_blank" rel="noopener noreferrer">Open Account Console</a>
      </p>
      <p>
        <button (click)="validateToken()" [disabled]="!accessToken">Validate Token</button>
        <button (click)="fetchRss()" [disabled]="!accessToken">Fetch RSS</button>
        <button (click)="toggleToken()" [disabled]="!accessToken">{{ showToken ? 'Hide' : 'Show' }} Token</button>
        <button (click)="copyToken()" [disabled]="!accessToken">Copy Token</button>
        <button (click)="adminPing()" [disabled]="!accessToken">Admin Ping</button>
      </p>
      <p *ngIf="accessTokenExp">
        Token expires at: {{ accessTokenExp * 1000 | date:'medium' }}
      </p>
      <div *ngIf="showToken && accessToken">
        <h3>Access Token (debug)</h3>
        <textarea rows="6" style="width:100%;font-family:monospace" readonly>{{ accessToken }}</textarea>
        <h4>Decoded Claims</h4>
        <pre>{{ tokenPayload | json }}</pre>
      </div>
      <div *ngIf="tokenValidation">
        <h3>Token Validation</h3>
        <pre>{{ tokenValidation | json }}</pre>
      </div>
      <div *ngIf="rss">
        <h3>RSS (via API)</h3>
        <pre>{{ rss | json }}</pre>
      </div>
      <div *ngIf="adminPingStatus !== null">
        <h3>Admin Ping</h3>
        <p>Status: {{ adminPingStatus }}</p>
        <pre>{{ adminPingResponse | json }}</pre>
      </div>
    </div>
    <div *ngIf="error" class="error">{{ error }}</div>
  `
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
  private realm = 'news';
  private kcBase = 'https://localhost:8443';
  private clientId = 'news-web';
  private redirectUri = 'https://localhost/';
  accountUrl = `${this.kcBase}/realms/${this.realm}/account`;

  constructor(){
    fetch('/api/healthz').then(r => r.json()).then(j => this.health = j).catch(e => this.health = { error: String(e) });
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    if (code) {
      this.exchangeCodeForToken(code).catch(err => {
        this.error = 'Token exchange failed: ' + String(err);
      }).finally(() => {
        // Clean up URL after handling login
        history.replaceState({}, document.title, window.location.origin + window.location.pathname);
      });
    } else {
      // Load any existing token from session storage (manual testing convenience)
      const stored = sessionStorage.getItem(this.tokenKey());
      if (stored) {
        this.loggedIn = true;
        this.accessToken = stored;
        this.accessTokenExp = this.decodeJwtExp(this.accessToken);
        this.tokenPayload = this.decodeJwt(this.accessToken);
      }
    }
  }

  async login() {
    const codeVerifier = this.generateCodeVerifier();
    const codeChallenge = await this.computeCodeChallenge(codeVerifier);
    try {
      sessionStorage.setItem(`pkce:${this.realm}:${this.clientId}`, codeVerifier);
    } catch (_) {}
    const url = `${this.kcBase}/realms/${this.realm}/protocol/openid-connect/auth` +
      `?client_id=${encodeURIComponent(this.clientId)}` +
      `&redirect_uri=${encodeURIComponent(this.redirectUri)}` +
      `&response_type=code&scope=${encodeURIComponent('openid profile email')}` +
      `&code_challenge_method=S256&code_challenge=${encodeURIComponent(codeChallenge)}`;
    window.location.href = url;
  }

  logout() {
    try {
      sessionStorage.removeItem(this.pkceKey());
      sessionStorage.removeItem(this.tokenKey());
    } catch (_) {}
    const url = `${this.kcBase}/realms/${this.realm}/protocol/openid-connect/logout` +
      `?client_id=${encodeURIComponent(this.clientId)}` +
      `&post_logout_redirect_uri=${encodeURIComponent(this.redirectUri)}`;
    window.location.href = url;
  }

  async validateToken() {
    this.error = '';
    this.tokenValidation = null;
    if (!this.accessToken) return;
    try {
      const resp = await fetch('/api/token/validate', {
        headers: { 'Authorization': `Bearer ${this.accessToken}` }
      });
      this.tokenValidation = await resp.json();
    } catch (e) {
      this.error = 'Validate failed: ' + String(e);
    }
  }

  async fetchRss() {
    this.error = '';
    this.rss = null;
    if (!this.accessToken) return;
    try {
      const resp = await fetch('/api/rss', {
        headers: { 'Authorization': `Bearer ${this.accessToken}` }
      });
      this.rss = await resp.json();
    } catch (e) {
      this.error = 'RSS failed: ' + String(e);
    }
  }

  async adminPing() {
    this.error = '';
    this.adminPingStatus = null;
    this.adminPingResponse = null;
    if (!this.accessToken) return;
    try {
      const resp = await fetch('/api/admin/ping', {
        headers: { 'Authorization': `Bearer ${this.accessToken}` }
      });
      this.adminPingStatus = resp.status;
      // Try JSON first, fall back to text
      try {
        this.adminPingResponse = await resp.json();
      } catch (_) {
        this.adminPingResponse = await resp.text();
      }
    } catch (e) {
      this.error = 'Admin ping failed: ' + String(e);
    }
  }

  private generateCodeVerifier(): string {
    const array = new Uint8Array(64);
    crypto.getRandomValues(array);
    return this.toBase64Url(array);
  }

  private async computeCodeChallenge(verifier: string): Promise<string> {
    const data = new TextEncoder().encode(verifier);
    const digest = await crypto.subtle.digest('SHA-256', data);
    const bytes = new Uint8Array(digest);
    return this.toBase64Url(bytes);
  }

  private toBase64Url(bytes: Uint8Array): string {
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64 = btoa(binary);
    return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+/g, '');
  }

  private pkceKey(): string { return `pkce:${this.realm}:${this.clientId}`; }
  private tokenKey(): string { return `token:${this.realm}:${this.clientId}`; }

  private async exchangeCodeForToken(code: string) {
    const verifier = sessionStorage.getItem(this.pkceKey());
    if (!verifier) throw new Error('Missing PKCE verifier');
    const body = new URLSearchParams();
    body.set('grant_type', 'authorization_code');
    body.set('client_id', this.clientId);
    body.set('code', code);
    body.set('redirect_uri', this.redirectUri);
    body.set('code_verifier', verifier);
    const tokenUrl = `${this.kcBase}/realms/${this.realm}/protocol/openid-connect/token`;
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
    this.accessToken = json.access_token || null;
    this.loggedIn = !!this.accessToken;
    this.accessTokenExp = this.decodeJwtExp(this.accessToken);
    this.tokenPayload = this.decodeJwt(this.accessToken);
    this.startTokenExpiryWatcher();
    try {
      if (this.accessToken) sessionStorage.setItem(this.tokenKey(), this.accessToken);
    } catch (_) {}
  }

  private decodeJwtExp(token: string | null): number | null {
    if (!token) return null;
    try {
      const parts = token.split('.');
      if (parts.length !== 3) return null;
      const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
      return typeof payload.exp === 'number' ? payload.exp : null;
    } catch {
      return null;
    }
  }

  private decodeJwt(token: string | null): any {
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

  toggleToken() { this.showToken = !this.showToken; }
  async copyToken() {
    if (!this.accessToken) return;
    try {
      await navigator.clipboard.writeText(this.accessToken);
    } catch (e) {
      this.error = 'Copy failed: ' + String(e);
    }
  }

  private startTokenExpiryWatcher() {
    if (this.tokenTimer) clearInterval(this.tokenTimer);
    this.tokenTimer = setInterval(() => {
      if (!this.accessTokenExp) return;
      const now = Math.floor(Date.now() / 1000);
      if (now >= this.accessTokenExp) {
        this.accessToken = null;
        this.accessTokenExp = null;
        this.loggedIn = false;
        this.tokenValidation = null;
        this.rss = null;
        try {
          sessionStorage.removeItem(this.tokenKey());
        } catch (_) {}
        this.error = 'Session expired — please login again.';
        clearInterval(this.tokenTimer);
        this.tokenTimer = null;
      }
    }, 1000);
  }
}
