import { createServer } from 'node:http';
import { spawnSync } from 'node:child_process';

const production = process.argv.includes('--production');
if (!production) {
  const build = spawnSync(process.execPath, ['scripts/build.mjs'], { stdio: 'inherit' });
  if (build.status !== 0) process.exit(build.status || 1);
}
const { default: worker } = await import('../dist/server/index.js');
const port = Number(process.env.PORT || 4173);
const host = production ? '0.0.0.0' : '127.0.0.1';
const publicOrigin = process.env.APP_ORIGIN || process.env.RENDER_EXTERNAL_URL;
if (production && !publicOrigin) throw new Error('Set APP_ORIGIN to the public HTTPS origin of AniLedger.');
const origin = new URL(production ? publicOrigin : `http://localhost:${port}`);

if (production && origin.protocol !== 'https:') throw new Error('Set APP_ORIGIN to the public HTTPS origin of AniLedger.');

createServer(async (incoming, outgoing) => {
  try {
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
}).listen(port, host, () => console.log(production ? `Serving ${origin.origin}` : `Local: ${origin.origin}`));
