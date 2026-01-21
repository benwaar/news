export function pkceKey(realm: string, clientId: string): string {
  return `pkce:${realm}:${clientId}`;
}

export function tokenKey(realm: string, clientId: string): string {
  return `token:${realm}:${clientId}`;
}

export function refreshKey(realm: string, clientId: string): string {
  return `refresh:${realm}:${clientId}`;
}
