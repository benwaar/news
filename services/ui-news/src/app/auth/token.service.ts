import { Injectable } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class AuthTokenService {
  private token: string | null = null;
  private lastAttached = false;
  private lastUrl: string | null = null;
  private lastToken: string | null = null;

  setToken(token: string | null) {
    this.token = token || null;
  }

  getToken(): string | null {
    return this.token;
  }

  markAttached(url: string, token: string) {
    this.lastAttached = true;
    this.lastUrl = url || null;
    this.lastToken = token || null;
  }

  markSkipped(url: string) {
    this.lastAttached = false;
    this.lastUrl = url || null;
    this.lastToken = null;
  }

  getLastAttached(): boolean { return this.lastAttached; }
  getLastUrl(): string | null { return this.lastUrl; }
  getLastToken(): string | null { return this.lastToken; }
  getLastAuthHeader(): string | null {
    return this.lastToken ? `Authorization: Bearer ${this.lastToken}` : null;
  }
}
