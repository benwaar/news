const express = require('express');
const helmet = require('helmet');
const app = express();
const PORT = process.env.PORT || 9002;

app.use(helmet());

app.get('/healthz', (req, res) => {
  res.json({ status: 'ok', service: 'rss-mcp' });
});

// Minimal RSS endpoint (stubbed data)
app.get('/rss', (req, res) => {
  const feed = {
    title: 'Sample RSS Feed',
    source: 'rss-mcp',
    items: [
      { title: 'Hello News', link: 'https://example.com/news/hello', pubDate: new Date().toISOString() },
      { title: 'Breaking: Minimal Stack', link: 'https://example.com/news/minimal', pubDate: new Date().toISOString() }
    ],
    fetchedAt: new Date().toISOString()
  };
  res.json(feed);
});

app.listen(PORT, () => {
  console.log(`[rss-mcp] listening on port ${PORT}`);
});
