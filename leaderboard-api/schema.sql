-- MacWispr public leaderboard (opt-in, anonymous).
-- token_hash = SHA-256 of a client-only secret. Maintainers cannot reverse it.
-- display_name is server-derived from the hash (never a real name / email / GitHub).

CREATE TABLE IF NOT EXISTS participants (
  token_hash TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  dictations INTEGER NOT NULL DEFAULT 0,
  words INTEGER NOT NULL DEFAULT 0,
  time_saved_minutes REAL NOT NULL DEFAULT 0,
  streak_days INTEGER NOT NULL DEFAULT 0,
  is_seed INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_participants_rank
  ON participants (time_saved_minutes DESC, words DESC, dictations DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_participants_display_name
  ON participants (display_name);
