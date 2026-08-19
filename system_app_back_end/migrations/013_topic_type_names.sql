-- Topic types carry an English name and a Hebrew name so the sidebar
-- follows the app language.

ALTER TABLE topic_types
    ADD COLUMN IF NOT EXISTS name_he TEXT;

UPDATE topic_types
SET name_he = CASE name
    WHEN 'project' THEN 'פרויקט'
    WHEN 'process' THEN 'תהליך'
    WHEN 'area' THEN 'תחום'
    WHEN 'other' THEN 'שונות'
    WHEN 'others' THEN 'שונות'
    ELSE name_he
END
WHERE name_he IS NULL;
