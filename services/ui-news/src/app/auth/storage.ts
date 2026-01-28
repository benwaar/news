export function pkceKey(realm: string, clientId: string): string {
  return `pkce:${realm}:${clientId}`;
}

export function tokenKey(realm: string, clientId: string): string {
  return `token:${realm}:${clientId}`;
}

export function refreshKey(realm: string, clientId: string): string {
  return `refresh:${realm}:${clientId}`;
}

// Persisted UI preference for where to read/write access tokens for demos
export const STORAGE_STRATEGY_KEY = 'storage:strategy';
