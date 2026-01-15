import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AUTH_MODES, AUTH_MODE_STORAGE_KEY, AuthMode } from './auth/modes';
import { AuthProvider, createAuthProvider, AuthConfig } from './auth/provider';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule],
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
  private provider!: AuthProvider;
  private realm = 'news';
  private kcBase = 'https://localhost:8443';
  private clientId = 'news-web';
  private redirectUri = 'https://localhost/';
  accountUrl = `${this.kcBase}/realms/${this.realm}/account`;

  constructor(){
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
}
