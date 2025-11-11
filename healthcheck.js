// Simple health check script for Docker HEALTHCHECK
// Checks the /mcp endpoint on WEBSITES_PORT -> PORT -> 8080
const http = require('http');

const port = process.env.WEBSITES_PORT || process.env.PORT || '8080';
const path = '/mcp';
const timeout = 4000; // ms

const options = {
  hostname: 'localhost',
  port: Number(port),
  path,
  method: 'GET',
  timeout,
};

const req = http.request(options, (res) => {
  const code = res.statusCode || 0;
  if (code >= 200 && code < 300) {
    process.exit(0);
  } else {
    // Not ready if non-2xx
    process.exit(1);
  }
});

req.on('timeout', () => {
  req.destroy(new Error('timeout'));
});
req.on('error', () => process.exit(1));
req.end();
