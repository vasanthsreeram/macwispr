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

  // is_custom_name may be missing on very old rows — COALESCE to 0.
  const rows = await env.DB.prepare(
    `SELECT display_name, dictations, words, time_saved_minutes, streak_days, is_seed,
            COALESCE(is_custom_name, 0) AS is_custom_name, updated_at
     FROM participants
     ORDER BY words DESC, dictations DESC, time_saved_minutes DESC
     LIMIT ?`
  )
    .bind(limit)
    .all();

  const entries = (rows.results || []).map((row, i) => publicEntry(row, i + 1));

  return json(
    {
      entries,
      count: entries.length,
      // Spec: primary sort words dictated, then dictations, then time saved.
      sort: ["words", "dictations", "time_saved_minutes"],
      metrics: ["words", "dictations", "streak_days", "time_saved_minutes"],
      generated_at: new Date().toISOString(),
    },
    200,
    request,
    { "Cache-Control": "public, max-age=30" }
  );
}

/** Public row shape — counts only + display + avatar key. */
function publicEntry(row, rank) {
  const custom = row.is_custom_name === 1 || row.is_custom_name === true;
  return {
    rank,
    display_name: row.display_name,
    short_name: custom ? String(row.display_name || "") : shortName(row.display_name),
    animal: animalFromDisplayName(row.display_name, row.avatar_animal),
    avatar_key: avatarKeyFromDisplayName(row.display_name),
    is_custom_name: custom,
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

function animalFromDisplayName(displayName, fallbackAnimal) {
  const m = /^Anonymous\s+(\S+)/i.exec(String(displayName || ""));
  if (m) return m[1];
  if (fallbackAnimal) return fallbackAnimal;
  // Named players still get a stable cute animal for the avatar art.
  const h = avatarKeyFromDisplayName(displayName);
  const idx = parseInt(h.slice(0, 8), 16) % ANIMALS.length;
  return ANIMALS[idx];
}

/**
 * Optional competitive public name.
 * null/empty → stay fully anonymous (server-derived animal).
 * Valid string → show on the board (user chose to be identifiable by that label).
 */
function sanitizePublicName(raw) {
  if (raw == null) return { name: null };
  if (typeof raw !== "string") return { error: "invalid_name" };
  let s = raw.normalize("NFKC").trim().replace(/\s+/g, " ");
  if (s.length === 0) return { name: null };
  if (s.length < 2 || s.length > 24) return { error: "invalid_name_length" };
  // Letters / numbers / common separators — no URLs, @handles, or control junk.
  if (!/^[\p{L}\p{N} _.\-·'’]+$/u.test(s)) return { error: "invalid_name_chars" };
  if (/^anonymous\b/i.test(s)) return { error: "reserved_name" };
  if (/^seed\b/i.test(s)) return { error: "reserved_name" };
  if (/(https?:|www\.|@)/i.test(s)) return { error: "invalid_name_chars" };
  return { name: s };
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
    `SELECT display_name, dictations, words, time_saved_minutes, streak_days, is_seed,
            COALESCE(is_custom_name, 0) AS is_custom_name
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
       WHERE (p2.words > p.words)
          OR (p2.words = p.words AND p2.dictations > p.dictations)
          OR (p2.words = p.words AND p2.dictations = p.dictations AND p2.time_saved_minutes > p.time_saved_minutes)
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

  // Optional competitive name. Omit / empty → stay anonymous animal.
  const nameField =
    body.public_name !== undefined ? body.public_name : body.display_name;
  const cleaned = sanitizePublicName(nameField);
  if (cleaned.error) {
    return json({ error: cleaned.error }, 400, request);
  }
  const isCustom = cleaned.name != null;
  const tokenHash = await sha256Hex(token);
  const anonName = await displayNameFromToken(token);
  const now = new Date().toISOString();

  // Unique display_name: custom names 409 on clash; anon names re-tag.
  let name = isCustom ? cleaned.name : anonName;
  let lastErr = null;
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      await env.DB.prepare(
        `INSERT INTO participants
           (token_hash, display_name, dictations, words, time_saved_minutes, streak_days,
            is_seed, is_custom_name, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
         ON CONFLICT(token_hash) DO UPDATE SET
           display_name = excluded.display_name,
           -- Never let a partial/empty client sync wipe a higher board score
           -- (e.g. fresh launch before history loads, or maintainer seed floor).
           -- Bare column names = existing row; excluded.* = incoming payload.
           dictations = MAX(excluded.dictations, dictations),
           words = MAX(excluded.words, words),
           time_saved_minutes = MAX(excluded.time_saved_minutes, time_saved_minutes),
           streak_days = MAX(excluded.streak_days, streak_days),
           is_custom_name = excluded.is_custom_name,
           updated_at = excluded.updated_at
         WHERE participants.is_seed = 0`
      )
        .bind(
          tokenHash,
          name,
          dictations,
          words,
          timeSaved,
          streak,
          isCustom ? 1 : 0,
          now,
          now
        )
        .run();
      lastErr = null;
      break;
    } catch (e) {
      lastErr = e;
      if (isCustom) {
        // Someone else already has this public name.
        return json({ error: "name_taken" }, 409, request);
      }
      const salt = (attempt + 1).toString(16);
      name = anonName.replace(
        /·\s*[a-f0-9]+$/i,
        `· ${salt}${tokenHash.slice(8, 11)}`
      );
      if (attempt === 4) throw e;
    }
  }
  if (lastErr) throw lastErr;

  // Re-read after upsert — MAX() may keep higher stored scores than the payload.
  const stored = await env.DB.prepare(
    `SELECT display_name, dictations, words, time_saved_minutes, streak_days, is_seed,
            COALESCE(is_custom_name, 0) AS is_custom_name
     FROM participants WHERE token_hash = ? AND is_seed = 0`
  )
    .bind(tokenHash)
    .first();

  const row = stored || {
    display_name: name,
    dictations,
    words,
    time_saved_minutes: timeSaved,
    streak_days: streak,
    is_seed: 0,
    is_custom_name: isCustom ? 1 : 0,
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
