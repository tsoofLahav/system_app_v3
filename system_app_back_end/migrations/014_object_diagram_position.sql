-- Persist objects-map coordinates. Null = never placed; the client lays those out.
ALTER TABLE objects
    ADD COLUMN IF NOT EXISTS diagram_x DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS diagram_y DOUBLE PRECISION;
