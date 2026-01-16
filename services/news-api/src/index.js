const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const app = express();
const PORT = process.env.PORT || 9000;

// Config for token validation
const ISSUER = process.env.OIDC_ISSUER || 'https://localhost:8443/realms/news';
const AUDIENCE = process.env.OIDC_AUDIENCE || 'news-api';
// Use internal HTTP JWKS URL to avoid TLS/cert issues in-container
const JWKS_URI = process.env.OIDC_JWKS_URI || 'http://keycloak:8080/realms/news/protocol/openid-connect/certs';

const client = jwksClient({
  jwksUri: JWKS_URI,
  cache: true,
  cacheMaxEntries: 5,
  cacheMaxAge: 10 * 60 * 1000, // 10 minutes
  rateLimit: true,
  jwksRequestsPerMinute: 10,
});

function getKey(header, callback) {
  if (!header || !header.kid) {
    return callback(new Error('Missing kid in token header'));
  }
  client.getSigningKey(header.kid, (err, key) => {
    if (err) return callback(err);
    const signingKey = key.getPublicKey();
    callback(null, signingKey);
  });
}

function authenticateToken(req, res, next) {
  const auth = req.headers.authorization || '';
  const [, token] = auth.split(' ');
  if (!token) {
    return res.status(401).json({ error: 'missing bearer token' });
  }
  // Verify signature, issuer, audience, expiration
  jwt.verify(
    token,
    getKey,
    {
      algorithms: ['RS256'],
      issuer: ISSUER,
      audience: AUDIENCE,
      clockTolerance: 5, // seconds
    },
    (err, decoded) => {
      if (err) {
        return res.status(401).json({ error: 'invalid token', detail: err.message });
      }
      req.user = decoded;
      next();
    }
  );
}

function requireRealmRole(role) {
  return function (req, res, next) {
    const roles = (req.user && req.user.realm_access && req.user.realm_access.roles) || [];
    if (!Array.isArray(roles)) {
      return res.status(403).json({ error: 'forbidden', detail: 'no realm roles present' });
    }
    if (!roles.includes(role)) {
      return res.status(403).json({ error: 'forbidden', detail: `missing realm role: ${role}` });
    }
    next();
  };
}

app.use(helmet());
// Enable CORS for local dev (Angular dev server and UI gateway)
app.use(cors({
  origin: [
    'https://localhost',
    'https://localhost:4200',
    'https://localhost:4443'
  ],
  credentials: true,
  methods: ['GET', 'HEAD', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type']
}));
// Respond to CORS preflight requests
app.options('*', cors());

app.get('/healthz', (req, res) => {
  res.json({ status: 'ok', service: 'news-api' });
});

// Token validation probe: reports whether token passed standard checks
app.get('/token/validate', authenticateToken, (req, res) => {
  const now = Math.floor(Date.now() / 1000);
  const issOk = req.user && req.user.iss === ISSUER;
  const audClaim = req.user && req.user.aud;
  const audOk = Array.isArray(audClaim)
    ? audClaim.includes(AUDIENCE)
    : audClaim === AUDIENCE;
  const expOk = typeof req.user?.exp === 'number' ? req.user.exp > now : true;
  // Signature is guaranteed by jwt.verify in authenticateToken
  const signatureOk = true;

  res.json({
    valid: issOk && audOk && expOk && signatureOk,
    expected: { issuer: ISSUER, audience: AUDIENCE },
    token: {
      iss: req.user?.iss,
      aud: req.user?.aud,
      sub: req.user?.sub,
      iat: req.user?.iat,
      exp: req.user?.exp,
      realm_roles: req.user?.realm_access?.roles || [],
    },
    checks: {
      issuer: issOk,
      audience: audOk,
      signature: signatureOk,
      exp: expOk,
    },
  });
});

// Protected example: Proxy RSS from rss-mcp
app.get('/rss', authenticateToken, async (req, res) => {
  try {
    const resp = await fetch('http://rss-mcp:9002/rss');
    const data = await resp.json();
    res.json({ service: 'news-api', rss: data, sub: req.user && req.user.sub });
  } catch (e) {
    res.status(502).json({ error: 'rss-mcp unavailable', detail: String(e) });
  }
});

// Admin-only endpoint example: requires realm role 'news:admin'
app.get('/admin/ping', authenticateToken, requireRealmRole('news:admin'), (req, res) => {
  res.json({ ok: true, message: 'admin pong', sub: req.user?.sub });
});

app.listen(PORT, () => {
  console.log(`[news-api] listening on port ${PORT}`);
  console.log(`[news-api] expecting issuer ${ISSUER}, audience ${AUDIENCE}`);
});
