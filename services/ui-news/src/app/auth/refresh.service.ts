import { Injectable } from '@angular/core';
import { AuthTokenService } from './token.service';
import { tokenKey, refreshKey } from './storage';

// Dev-only constants to match AppComponent config
const REALM = 'news';
const CLIENT_ID = 'news-web';
const KC_BASE = 'https://localhost:8443';

@Injectable({ providedIn: 'root' })
export class RefreshService {
  private inFlight: Promise<string | null> | null = null;

  constructor(private tokenSvc: AuthTokenService) {}

  async refresh(): Promise<string | null> {
    // Cross-tab refresh lock to avoid multiple tabs refreshing at once
    const REALM = 'news';
    const CLIENT_ID = 'news-web';
    const tKey = tokenKey(REALM, CLIENT_ID);
    const lockKey = 'auth:refresh:lock';
    const now = Date.now();
    try {
      const lockTs = Number(localStorage.getItem(lockKey) || '0');
      if (lockTs && now - lockTs < 10000) {
        // Another tab is refreshing. Wait briefly for sessionStorage to update.
        const waited = await this.waitForExternalRefresh(tKey, 5000);
        if (waited) {
          this.tokenSvc.setToken(waited);
          return waited;
        }
      }
      // Acquire lock for this tab
      localStorage.setItem(lockKey, String(now));
    } catch (_) {}

    if (this.inFlight) {
      return this.inFlight;
    }
    const p = this.performRefresh().finally(() => {
      this.inFlight = null;
      try { localStorage.removeItem(lockKey); } catch {}
    });
    this.inFlight = p;
    return p;
  }

  private async performRefresh(): Promise<string | null> {
    try {
      const rKey = refreshKey(REALM, CLIENT_ID);
      const tKey = tokenKey(REALM, CLIENT_ID);
      const refresh = sessionStorage.getItem(rKey);
      if (!refresh) return null;
      const body = new URLSearchParams();
      body.set('grant_type', 'refresh_token');
      body.set('client_id', CLIENT_ID);
      body.set('refresh_token', refresh);
      const tokenUrl = `${KC_BASE}/realms/${REALM}/protocol/openid-connect/token`;
      const resp = await fetch(tokenUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      });
      if (!resp.ok) return null;
      const json = await resp.json();
      const access = json.access_token || null;
      const newRefresh = json.refresh_token || null;
      if (!access) return null;
      try {
        sessionStorage.setItem(tKey, access);
        if (newRefresh) sessionStorage.setItem(rKey, newRefresh);
      } catch (_) {}
      this.tokenSvc.setToken(access);
      // Broadcast refresh to other tabs (localStorage event)
      try {
        localStorage.setItem('auth:bc', JSON.stringify({ from: 'refresh-service', type: 'refresh', payload: { access }, at: Date.now() }));
      } catch {}
      return access;
    } catch (_) {
      return null;
    }
  }

  private async waitForExternalRefresh(tKey: string, timeoutMs: number): Promise<string | null> {
    const start = Date.now();
    const initial = sessionStorage.getItem(tKey);
    while (Date.now() - start < timeoutMs) {
      await new Promise((r) => setTimeout(r, 250));
      try {
        const current = sessionStorage.getItem(tKey);
        if (current && current !== initial) {
          return current;
        }
      } catch {}
    }
    return null;
  }
}
