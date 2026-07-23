# MacWispr leaderboard API

Cloudflare Worker + D1 backend for the **opt-in, anonymous** public leaderboard (GitHub #11).

## Privacy

| Stored | Not stored |
|--------|------------|
| `SHA-256(client_token)` | Client secret (only on device) |
| Server-derived display name (`Anonymous Otter · a1f2`) | Real names, handles, emails |
| Aggregate counts (dictations, words, time saved, streak) | Transcripts, audio, install UUID |
| `is_seed` for demo rows | IP addresses, device IDs |

Maintainers with DB access **cannot** identify a real person from a row.

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `GET` | `/v1/leaderboard?limit=50` | none | Public ranked list |
| `PUT` | `/v1/me` | `Bearer <token>` | Upsert aggregates |
| `DELETE` | `/v1/me` | `Bearer <token>` | Leave the board |

## Deploy

```bash
cd leaderboard-api
wrangler d1 execute macwispr-leaderboard --remote --file=schema.sql
wrangler d1 execute macwispr-leaderboard --remote --file=seed.sql
wrangler deploy
```

## Local

```bash
wrangler d1 execute macwispr-leaderboard --local --file=schema.sql
wrangler d1 execute macwispr-leaderboard --local --file=seed.sql
wrangler dev
```
