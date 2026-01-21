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
    if (this.inFlight) {
      return this.inFlight;
    }
    const p = this.performRefresh().finally(() => {
      this.inFlight = null;
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
      return access;
    } catch (_) {
      return null;
    }
  }
}
