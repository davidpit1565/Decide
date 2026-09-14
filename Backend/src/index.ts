import { createServer } from "node:http";
import { handle } from "./handler.js";
import { resolveClientKey } from "./rateLimit.js";

/**
 * Standalone server. Behind TLS termination in production — the app refuses any
 * endpoint that is not https.
 */
const port = Number(process.env.PORT ?? 8787);

const server = createServer((req, res) => {
  const chunks: Buffer[] = [];
  let size = 0;

  req.on("data", (chunk: Buffer) => {
    size += chunk.length;
    if (size > 64_000) {
      res.writeHead(413, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "payload_too_large" }));
      req.destroy();
      return;
    }
    chunks.push(chunk);
  });

  req.on("end", () => {
    if (res.writableEnded) return;

    const headers: Record<string, string | undefined> = {};
    for (const [key, value] of Object.entries(req.headers)) {
      headers[key.toLowerCase()] = Array.isArray(value) ? value[0] : value;
    }

    const clientKey = resolveClientKey(headers, req.socket.remoteAddress);
    const path = new URL(req.url ?? "/", "http://localhost").pathname;

    handle({
      method: req.method ?? "GET",
      path,
      headers,
      body: Buffer.concat(chunks).toString("utf8"),
      clientKey,
    })
      .then((response) => {
        res.writeHead(response.status, response.headers);
        res.end(response.body);
      })
      .catch(() => {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "internal_error" }));
      });
  });
});

server.listen(port, () => {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.warn("ANTHROPIC_API_KEY is not set — analysis requests will fail.");
  }
  console.log(`DECIDE backend listening on :${port}`);
});
