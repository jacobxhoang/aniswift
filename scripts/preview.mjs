import { createServer } from 'node:http';
import { spawnSync } from 'node:child_process';

const build = spawnSync(process.execPath, ['scripts/build.mjs'], { stdio: 'inherit' });
if (build.status !== 0) process.exit(build.status || 1);
const { default: worker } = await import('../dist/server/index.js');
const port = Number(process.env.PORT || 4173);

createServer(async (incoming, outgoing) => {
  try {
    const chunks = [];
    for await (const chunk of incoming) chunks.push(chunk);
    const body = Buffer.concat(chunks);
    const request = new Request(`http://localhost:${port}${incoming.url}`, {
      method: incoming.method,
      headers: incoming.headers,
      body: body.length ? body : undefined,
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
}).listen(port, '127.0.0.1', () => console.log(`Local: http://localhost:${port}`));
