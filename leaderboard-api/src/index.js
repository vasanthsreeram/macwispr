/**
 * MacWispr public leaderboard API
 *
 * Privacy contract:
 * - Participants are identified only by a client-held secret token.
 * - We store SHA-256(token) only — maintainers cannot reverse to the secret.
 * - Display names are server-derived ("Anonymous <Animal> · <tag>").
 * - No install UUID, email, device IDs, IPs, transcripts, or audio are stored.
 * - Separate from product telemetry (PostHog).
 */

const ANIMALS = [
  "Otter", "Fox", "Wren", "Lynx", "Heron", "Pika", "Moth", "Seal",
  "Badger", "Crane", "Dove", "Elk", "Finch", "Gecko", "Hare", "Ibis",
  "Jay", "Koala", "Lark", "Mink", "Newt", "Orca", "Puffin", "Quail",
  "Raven", "Swan", "Teal", "Urchin", "Vole", "Wolf", "Yak", "Zebu",
];

const CORS_ORIGINS = new Set([
  "https://fuckwisprflow.com",
  "https://www.fuckwisprflow.com",
  "https://macwispr.lintware.com",
  "https://macwispr.pages.dev",
  "https://fuckwisprflow.pages.dev",
  "http://localhost:8787",
  "http://127.0.0.1:8787",
  "http://localhost:4173",
  "null", // file:// / some local previews
]);

const MAX_LIMIT = 100;
const MAX_DICTATIONS = 5_000_000;
const MAX_WORDS = 500_000_000;
const MAX_TIME_SAVED = 50_000_000; // minutes
const MAX_STREAK = 10_000;

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (err) {
      console.error("leaderboard error", err?.message || err);
      return json({ error: "internal_error" }, 500, request);
    }
  },
};

async function handle(request, env) {
  const url = new URL(request.url);

  if (request.method === "OPTIONS") {
    return corsPreflight(request);
  }

  // Health
  if (url.pathname === "/" || url.pathname === "/health") {
    return json({ ok: true, service: "macwispr-leaderboard" }, 200, request);
  }

  if (url.pathname === "/v1/leaderboard" && request.method === "GET") {
    return getLeaderboard(request, env, url);
  }

  if (url.pathname === "/v1/me" && request.method === "GET") {
    return getMe(request, env);
  }

  if (url.pathname === "/v1/me" && request.method === "PUT") {
    return putMe(request, env);
  }

  if (url.pathname === "/v1/me" && request.method === "DELETE") {
    return deleteMe(request, env);
  }

  return json({ error: "not_found" }, 404, request);
}

async function getLeaderboard(request, env, url) {
  let limit = Number(url.searchParams.get("limit") || "50");
  if (!Number.isFinite(limit) || limit < 1) limit = 50;
  limit = Math.min(MAX_LIMIT, Math.floor(limit));

  const rows = await env.DB.prepare(
    `SELECT display_name, dictations, words, time_saved_minutes, streak_days, is_seed, updated_at
     FROM participants
     ORDER BY time_saved_minutes DESC, words DESC, dictations DESC
     LIMIT ?`
  )
    .bind(limit)
    .all();

  const entries = (rows.results || []).map((row, i) => publicEntry(row, i + 1));

  return json(
    {
      entries,
      count: entries.length,
      // Spec: primary sort time_saved, then words, then dictations.
      sort: ["time_saved_minutes", "words", "dictations"],
      metrics: ["time_saved_minutes", "words", "dictations", "streak_days"],
      generated_at: new Date().toISOString(),
    },
    200,
    request,
    { "Cache-Control": "public, max-age=30" }
  );
}

/** Public row shape — counts only + anonymous display + avatar key. */
function publicEntry(row, rank) {
  return {
    rank,
    display_name: row.display_name,
    short_name: shortName(row.display_name),
    animal: animalFromDisplayName(row.display_name),
    avatar_key: avatarKeyFromDisplayName(row.display_name),
    dictations: row.dictations,
    words: row.words,
    time_saved_minutes: row.time_saved_minutes,
    streak_days: row.streak_days,
    is_seed: row.is_seed === 1,
  };
}

function shortName(displayName) {
  // "Anonymous Otter · a1f2" → "Otter · a1f2"
  return String(displayName || "").replace(/^Anonymous\s+/i, "").trim();
}

function animalFromDisplayName(displayName) {
  const m = /^Anonymous\s+(\S+)/i.exec(String(displayName || ""));
  return m ? m[1] : "Otter";
}

function avatarKeyFromDisplayName(displayName) {
  // Stable, non-identifying key for cute avatar art (not a person ID).
  let h = 2166136261;
  const s = String(displayName || "");
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}

async function getMe(request, env) {
  const token = bearerToken(request);
  if (!token || token.length < 32 || token.length > 200) {
    return json({ error: "invalid_token" }, 401, request);
  }
  const tokenHash = await sha256Hex(token);
  const row = await env.DB.prepare(
    `SELECT display_name, dictations, words, time_saved_minutes, streak_days, is_seed
     FROM participants WHERE token_hash = ? AND is_seed = 0`
  )
    .bind(tokenHash)
    .first();

  if (!row) {
    return json({ error: "not_found", enrolled: false }, 404, request);
  }

  const rank = await rankForHash(env, tokenHash);
  return json(
    {
      ok: true,
      enrolled: true,
      ...publicEntry(row, rank),
    },
    200,
    request,
    { "Cache-Control": "no-store" }
  );
}

async function rankForHash(env, tokenHash) {
  const rankRow = await env.DB.prepare(
    `SELECT 1 + (
       SELECT COUNT(*) FROM participants p2
       WHERE (p2.time_saved_minutes > p.time_saved_minutes)
          OR (p2.time_saved_minutes = p.time_saved_minutes AND p2.words > p.words)
          OR (p2.time_saved_minutes = p.time_saved_minutes AND p2.words = p.words AND p2.dictations > p.dictations)
     ) AS rank
     FROM participants p
     WHERE p.token_hash = ?`
  )
    .bind(tokenHash)
    .first();
  return rankRow?.rank ?? null;
}

async function putMe(request, env) {
  const token = bearerToken(request);
  if (!token || token.length < 32 || token.length > 200) {
    return json({ error: "invalid_token" }, 401, request);
  }
  // Reject seed-looking / non-client tokens
  if (token.startsWith("seed")) {
    return json({ error: "invalid_token" }, 401, request);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400, request);
  }

  const dictations = intField(body.dictations, 0, MAX_DICTATIONS);
  const words = intField(body.words, 0, MAX_WORDS);
  const timeSaved = floatField(body.time_saved_minutes, 0, MAX_TIME_SAVED);
  const streak = intField(body.streak_days, 0, MAX_STREAK);
  if (
    dictations === null ||
    words === null ||
    timeSaved === null ||
    streak === null
  ) {
    return json({ error: "invalid_stats" }, 400, request);
  }

  const tokenHash = await sha256Hex(token);
  const displayName = await displayNameFromToken(token);
  const now = new Date().toISOString();

  // Ensure unique display_name on first insert; if collision, retry with tag salt.
  let name = displayName;
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      await env.DB.prepare(
        `INSERT INTO participants
           (token_hash, display_name, dictations, words, time_saved_minutes, streak_days, is_seed, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
         ON CONFLICT(token_hash) DO UPDATE SET
           dictations = excluded.dictations,
           words = excluded.words,
           time_saved_minutes = excluded.time_saved_minutes,
           streak_days = excluded.streak_days,
           updated_at = excluded.updated_at
         WHERE participants.is_seed = 0`
      )
        .bind(tokenHash, name, dictations, words, timeSaved, streak, now, now)
        .run();
      break;
    } catch (e) {
      // Unique display_name collision — re-tag
      const salt = (attempt + 1).toString(16);
      name = displayName.replace(/·\s*[a-f0-9]+$/i, `· ${salt}${tokenHash.slice(8, 11)}`);
      if (attempt === 4) throw e;
    }
  }

  const row = {
    display_name: name,
    dictations,
    words,
    time_saved_minutes: timeSaved,
    streak_days: streak,
    is_seed: 0,
  };
  const rank = await rankForHash(env, tokenHash);

  return json(
    {
      ok: true,
      ...publicEntry(row, rank),
    },
    200,
    request
  );
}

async function deleteMe(request, env) {
  const token = bearerToken(request);
  if (!token || token.length < 32) {
    return json({ error: "invalid_token" }, 401, request);
  }
  const tokenHash = await sha256Hex(token);
  await env.DB.prepare(
    `DELETE FROM participants WHERE token_hash = ? AND is_seed = 0`
  )
    .bind(tokenHash)
    .run();
  return json({ ok: true }, 200, request);
}

// ── helpers ──────────────────────────────────────────────────────────

function bearerToken(request) {
  const h = request.headers.get("Authorization") || "";
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m ? m[1].trim() : null;
}

function intField(v, min, max) {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  const n = Math.floor(v);
  if (n < min || n > max) return null;
  return n;
}

function floatField(v, min, max) {
  if (typeof v !== "number" || !Number.isFinite(v)) return null;
  if (v < min || v > max) return null;
  return Math.round(v * 100) / 100;
}

async function sha256Hex(text) {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function displayNameFromToken(token) {
  const hash = await sha256Hex(token);
  const animalIdx = parseInt(hash.slice(0, 8), 16) % ANIMALS.length;
  const tag = hash.slice(8, 12);
  return `Anonymous ${ANIMALS[animalIdx]} · ${tag}`;
}

function corsHeaders(request, extra = {}) {
  const origin = request.headers.get("Origin") || "";
  const allow =
    CORS_ORIGINS.has(origin) || origin.endsWith(".pages.dev")
      ? origin
      : "https://fuckwisprflow.com";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Methods": "GET, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
    ...extra,
  };
}

function corsPreflight(request) {
  return new Response(null, { status: 204, headers: corsHeaders(request) });
}

function json(body, status, request, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(request, extraHeaders),
    },
  });
}
