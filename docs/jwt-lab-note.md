current

Core approach: Client-side SPA using angular-auth-oidc-client (v10) with Code Flow + silent renew. No BFF pattern is present.
Token storage: Managed by angular-auth-oidc-client, which by default uses browser storage (localStorage) unless overridden. This project doesn’t set a custom storage provider in the OIDC config.


-> session to localstorage

localStorage: persists across tabs and browser restarts on the same origin.

-> silent renew refresh token to Iframe-based silent renew via silent_renew_url pointing to silent-renew.html (OIDC prompt=none flow), not a BFF/cookie refresh.

new

angular-oauth2-oidc