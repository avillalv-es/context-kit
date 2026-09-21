CREATE TABLE sites (
  site_id      TEXT PRIMARY KEY,
  name         TEXT NOT NULL,
  capacity_kva NUMERIC NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE readings (
  site_id TEXT NOT NULL REFERENCES sites(site_id),
  bucket  TIMESTAMPTZ NOT NULL,
  wh      BIGINT NOT NULL,
  PRIMARY KEY (site_id, bucket)
);
