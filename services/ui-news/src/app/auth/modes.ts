export type AuthMode = 'plain' | 'oidc-client-ts' | 'angular-auth-oidc-client' | 'angular-oauth2-oidc';

export const AUTH_MODES: AuthMode[] = [
  'plain',
  'oidc-client-ts',
  'angular-auth-oidc-client',
  'angular-oauth2-oidc'
];

export const AUTH_MODE_STORAGE_KEY = 'authMode:news-web';
