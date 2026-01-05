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
  `
})
export class AppComponent {
  health: any = { loading: true };
  loggedIn = false;
  private realm = 'news';
  private kcBase = 'https://localhost:8443';
  private clientId = 'news-web';
  private redirectUri = 'https://localhost/';

  constructor(){
    fetch('/api/healthz').then(r => r.json()).then(j => this.health = j).catch(e => this.health = { error: String(e) });
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    if (code) {
      this.loggedIn = true;
      // Clean up URL after detecting login
      history.replaceState({}, document.title, window.location.origin + window.location.pathname);
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
      `&response_type=code&scope=openid` +
      `&code_challenge_method=S256&code_challenge=${encodeURIComponent(codeChallenge)}`;
    window.location.href = url;
  }

  logout() {
    const url = `${this.kcBase}/realms/${this.realm}/protocol/openid-connect/logout` +
      `?client_id=${encodeURIComponent(this.clientId)}` +
      `&post_logout_redirect_uri=${encodeURIComponent(this.redirectUri)}`;
    window.location.href = url;
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
}
