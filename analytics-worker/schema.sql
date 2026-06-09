-- Idempotent schema for the portfolio analytics events table.
-- Applied automatically by deploy-worker.yml before each worker deploy.

CREATE TABLE IF NOT EXISTS events (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  ts         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  session_id TEXT NOT NULL,
  visitor_id TEXT NOT NULL DEFAULT '',
  name       TEXT NOT NULL,
  src        TEXT NOT NULL DEFAULT '',
  referrer   TEXT NOT NULL DEFAULT '',
  device     TEXT NOT NULL DEFAULT '',
  country    TEXT NOT NULL DEFAULT '',
  city       TEXT NOT NULL DEFAULT '',
  region     TEXT NOT NULL DEFAULT '',
  org        TEXT NOT NULL DEFAULT '',
  props      TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_events_name_ts ON events(name, ts);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_visitor ON events(visitor_id);
CREATE INDEX IF NOT EXISTS idx_events_ts      ON events(ts);
