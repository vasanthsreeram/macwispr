-- Optional competitive public names (is_custom_name = 1).
-- Safe to re-run: ADD COLUMN fails only if already present — run once remotely.

ALTER TABLE participants ADD COLUMN is_custom_name INTEGER NOT NULL DEFAULT 0;
