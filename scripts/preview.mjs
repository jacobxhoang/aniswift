import { createServer } from "node:http";

const message = "The AniLedger web app has been retired. iOS releases: https://github.com/jacobxhoang/ani-ledger/releases\n";

createServer((request, response) => {
  response.writeHead(410, {
    "Cache-Control": "no-store",
    "Content-Type": "text/plain; charset=utf-8"
  });
  response.end(request.method === "HEAD" ? undefined : message);
}).listen(Number(process.env.PORT ?? 4173), "0.0.0.0");
