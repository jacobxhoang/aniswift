import { readFile, mkdir, copyFile, writeFile } from 'node:fs/promises';

const webFiles = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/style.css': ['style.css', 'text/css; charset=utf-8'],
  '/catalog.js': ['catalog.js', 'text/javascript; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
};
const assets = {};
for (const [path, [file, type]] of Object.entries(webFiles)) {
  assets[path] = { type, body: await readFile(new URL(`../web/${file}`, import.meta.url), 'utf8') };
}
const worker = await readFile(new URL('../worker.js', import.meta.url), 'utf8');
await mkdir('dist/server', { recursive: true });
await mkdir('dist/.openai', { recursive: true });
await writeFile('dist/server/index.js', `const ASSETS = ${JSON.stringify(assets)};\n${worker}`);
await copyFile('.openai/hosting.json', 'dist/.openai/hosting.json');
