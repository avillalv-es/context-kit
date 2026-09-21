CREATE TABLE tariffs (
  id         BIGSERIAL PRIMARY KEY,
  site_id    TEXT NOT NULL REFERENCES sites(site_id),
  kind       TEXT NOT NULL CHECK (kind IN ('fixed','timeOfUse','capacity')),
  rate       NUMERIC NOT NULL,
  valid_from TIMESTAMPTZ NOT NULL,
  valid_to   TIMESTAMPTZ
);
