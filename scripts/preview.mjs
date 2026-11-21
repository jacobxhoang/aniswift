import { createServer } from 'node:http';
import { spawnSync } from 'node:child_process';

const production = process.argv.includes('--production');
if (!production) {
  const build = spawnSync(process.execPath, ['scripts/build.mjs'], { stdio: 'inherit' });
  if (build.status !== 0) process.exit(build.status || 1);
}
const { default: worker } = await import('../dist/server/index.js');
const port = Number(process.env.PORT || 4173);
const publicOrigin = process.env.APP_ORIGIN || process.env.RENDER_EXTERNAL_URL;
if (production && !publicOrigin) throw new Error('Set APP_ORIGIN to the public HTTPS origin of AniLedger.');
const pinnedOrigin = production ? new URL(publicOrigin) : null;
if (pinnedOrigin && pinnedOrigin.protocol !== 'https:') throw new Error('Set APP_ORIGIN to the public HTTPS origin of AniLedger.');

const authority = /^(?:\[[0-9a-f:.]+\]|[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?)(?::\d{1,5})?$/i;
const firstHeader = (incoming, name) => {
  const value = incoming.headers[name];
  return typeof value === 'string' ? value.split(',')[0].trim() : '';
};

// Production folds every request onto APP_ORIGIN. Development answers whatever
// hostname it is reached at, so tunnels, preview hostnames and LAN addresses all
// work; the worker still rejects writes addressed to another host.
function requestOrigin(incoming) {
  if (pinnedOrigin) return pinnedOrigin;
  const requested = firstHeader(incoming, 'x-forwarded-host') || firstHeader(incoming, 'host');
  const host = authority.test(requested) ? requested : `localhost:${port}`;
  let secure = firstHeader(incoming, 'x-forwarded-proto').toLowerCase() === 'https';
  if (!secure) {
    try {
      const browser = new URL(firstHeader(incoming, 'origin'));
      secure = browser.host === host && browser.protocol === 'https:';
    } catch {
      // A scheme-less request keeps http; only a matching Origin may upgrade it.
    }
  }
  return new URL(`${secure ? 'https' : 'http'}://${host}`);
}

createServer(async (incoming, outgoing) => {
  try {
    const origin = requestOrigin(incoming);
    const url = new URL(incoming.url, origin);
    if (url.origin !== origin.origin) {
      outgoing.writeHead(400).end('Invalid request URL');
      return;
    }
    const acceptsBody = incoming.method !== 'GET' && incoming.method !== 'HEAD';
    const request = new Request(url, {
      method: incoming.method,
      headers: incoming.headers,
      body: acceptsBody ? incoming : undefined,
      duplex: acceptsBody ? 'half' : undefined,
    });
    const response = await worker.fetch(request, process.env);
    for (const [key, value] of response.headers) {
      if (key !== 'set-cookie') outgoing.setHeader(key, value);
    }
    const cookies = response.headers.getSetCookie();
    if (cookies.length) outgoing.setHeader('set-cookie', cookies);
    outgoing.writeHead(response.status).end(Buffer.from(await response.arrayBuffer()));
  } catch (error) {
    console.error(error);
    outgoing.writeHead(500).end('Preview error');
  }
}).listen(port, '0.0.0.0', () => console.log(production ? `Serving ${pinnedOrigin.origin}` : `Local: http://localhost:${port}`));
