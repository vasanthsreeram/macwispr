// Serves release artifacts from R2 (Pages caps static files at 25 MiB).
const ALLOWED = /^MacWispr-[0-9][0-9A-Za-z.\-]*-macos-arm64\.(dmg|zip)$/;

export async function onRequest({ params, env, request }) {
  const name = Array.isArray(params.path) ? params.path.join("/") : params.path;
  if (!name || !ALLOWED.test(name)) return new Response("Not found", { status: 404 });
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405 });
  }
  const obj = request.method === "HEAD"
    ? await env.DOWNLOADS.head(name)
    : await env.DOWNLOADS.get(name, { range: request.headers });
  if (!obj) return new Response("Not found", { status: 404 });
  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set("Content-Type", name.endsWith(".dmg") ? "application/x-apple-diskimage" : "application/zip");
  headers.set("Content-Disposition", `attachment; filename="${name}"`);
  headers.set("Cache-Control", "public, max-age=3600");
  headers.set("ETag", obj.httpEtag);
  headers.set("Accept-Ranges", "bytes");
  if (obj.range && request.method === "GET" && request.headers.has("range")) {
    const start = obj.range.offset ?? 0;
    const len = obj.range.length ?? obj.size - start;
    headers.set("Content-Range", `bytes ${start}-${start + len - 1}/${obj.size}`);
    headers.set("Content-Length", String(len));
    return new Response(obj.body, { status: 206, headers });
  }
  headers.set("Content-Length", String(obj.size));
  return new Response(request.method === "HEAD" ? null : obj.body, { status: 200, headers });
}
