-- Table objects: grid payload type; migrate chart graphs into tables with chart quality.
ALTER TABLE objects DROP CONSTRAINT IF EXISTS objects_type_check;
ALTER TABLE objects DROP CONSTRAINT IF EXISTS objects_entity_check;

-- Map legacy graph payloads → rows + chart, then flip type to table.
UPDATE objects
SET payload = jsonb_build_object(
  'rows',
  jsonb_build_array(
    COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_object('text', COALESCE(elem, '')))
        FROM jsonb_array_elements_text(COALESCE(payload->'labels', '[]'::jsonb)) AS elem
      ),
      '[{"text":""},{"text":""}]'::jsonb
    ),
    COALESCE(
      (
        SELECT jsonb_agg(jsonb_build_object('text', COALESCE(elem, '')))
        FROM jsonb_array_elements_text(COALESCE(payload->'values', '[]'::jsonb)) AS elem
      ),
      '[{"text":""},{"text":""}]'::jsonb
    )
  ),
  'chart',
  jsonb_strip_nulls(
    jsonb_build_object(
      'enabled', true,
      'chartType', COALESCE(payload->>'chartType', payload->>'chart_type', 'bar'),
      'colors', COALESCE(
        payload->'colors',
        CASE
          WHEN payload ? 'color' THEN jsonb_build_array(payload->>'color')
          ELSE '[]'::jsonb
        END
      )
    )
  )
)
WHERE type = 'graph';

UPDATE objects SET type = 'table' WHERE type = 'graph';

-- Remap link endpoints that still say source/target type graph.
UPDATE links SET source_type = 'table' WHERE source_type = 'graph';
UPDATE links SET target_type = 'table' WHERE target_type = 'graph';

ALTER TABLE objects ADD CONSTRAINT objects_type_check
    CHECK (type IN ('task_list', 'info', 'image', 'table'));

ALTER TABLE objects ADD CONSTRAINT objects_entity_check
    CHECK (
        (type = 'task_list' AND task_list_id IS NOT NULL AND information_id IS NULL)
        OR (type = 'info' AND information_id IS NOT NULL AND task_list_id IS NULL)
        OR (type IN ('image', 'table') AND task_list_id IS NULL AND information_id IS NULL)
    );
