const express = require('express');
const helmet = require('helmet');
const app = express();
const PORT = process.env.PORT || 9000;

app.use(helmet());

app.get('/healthz', (req, res) => {
  res.json({ status: 'ok', service: 'news-api' });
});

// Proxy RSS from rss-mcp
app.get('/rss', async (req, res) => {
  try {
    const resp = await fetch('http://rss-mcp:9002/rss');
    const data = await resp.json();
    res.json({ service: 'news-api', rss: data });
  } catch (e) {
    res.status(502).json({ error: 'rss-mcp unavailable', detail: String(e) });
  }
});

app.listen(PORT, () => {
  console.log(`[news-api] listening on port ${PORT}`);
});
