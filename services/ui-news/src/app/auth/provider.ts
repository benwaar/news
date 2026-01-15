import { AuthMode } from './modes';
import { PlainAuthProvider } from './plain.provider';

export interface AuthConfig {
  realm: string;
  kcBase: string;
  clientId: string;
  redirectUri: string;
}

export interface AuthState {
  loggedIn: boolean;
  accessToken: string | null;
  accessTokenExp: number | null;
  tokenPayload: any;
  error?: string;
}

export interface AuthProvider {
  init(config: AuthConfig): Promise<AuthState>;
  login(): Promise<void> | void;
  logout(): Promise<void> | void;
  getAccessToken(): string | null;
  validateToken(): Promise<any>;
  fetchRss(): Promise<any>;
  adminPing(): Promise<{ status: number; body: any }>;
  subscribe(listener: (state: AuthState) => void): void;
}

export function createAuthProvider(mode: AuthMode): AuthProvider {
  switch (mode) {
    case 'plain':
      return new PlainAuthProvider();
    case 'oidc-client-ts':
    case 'angular-auth-oidc-client':
    case 'angular-oauth2-oidc':
      return new NotImplementedProvider(mode);
    default:
      return new NotImplementedProvider('plain');
  }
}

class NotImplementedProvider implements AuthProvider {
  constructor(private mode: AuthMode) {}
  async init(_config: AuthConfig): Promise<AuthState> {
    return { loggedIn: false, accessToken: null, accessTokenExp: null, tokenPayload: null, error: `Auth mode \"${this.mode}\" not implemented yet.` };
  }
  login(): void { /* no-op */ }
  logout(): void { /* no-op */ }
  getAccessToken(): string | null { return null; }
  async validateToken(): Promise<any> { throw new Error(`Auth mode \"${this.mode}\" not implemented`); }
  async fetchRss(): Promise<any> { throw new Error(`Auth mode \"${this.mode}\" not implemented`); }
  async adminPing(): Promise<{ status: number; body: any }> { throw new Error(`Auth mode \"${this.mode}\" not implemented`); }
  subscribe(_listener: (state: AuthState) => void): void { /* no-op */ }
}
