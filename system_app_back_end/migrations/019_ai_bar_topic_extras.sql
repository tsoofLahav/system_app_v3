-- Seven workspace-unique fixed AI-bar seats (1–7, keys ⌘2–⌘8 with the agent
-- as ⌘1), plus two extra seats (9–10, keys ⌘9 / ⌘0) that a topic-scoped
-- action occupies only on that topic.

-- Prefer currently pinned topic actions for the extra seats; at most two
-- per topic keep a seat. Unpinned leftovers stay in the menu.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY workspace_id, topic_id
           ORDER BY (bar_slot IS NULL), bar_slot, id
         ) AS rn
  FROM ai_actions
  WHERE topic_id IS NOT NULL
)
UPDATE ai_actions AS a
SET bar_slot = CASE
  WHEN r.rn = 1 THEN 9
  WHEN r.rn = 2 THEN 10
  ELSE NULL
END
FROM ranked AS r
WHERE a.id = r.id;

-- Fixed seats only go to 7 (agent takes the first of the eight spots).
UPDATE ai_actions
SET bar_slot = NULL
WHERE topic_id IS NULL AND bar_slot IS NOT NULL AND bar_slot > 7;

DROP INDEX IF EXISTS ai_actions_workspace_bar_slot_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS ai_actions_workspace_fixed_bar_slot_uidx
  ON ai_actions (workspace_id, bar_slot)
  WHERE bar_slot IS NOT NULL AND topic_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ai_actions_topic_extra_bar_slot_uidx
  ON ai_actions (workspace_id, topic_id, bar_slot)
  WHERE bar_slot IS NOT NULL AND topic_id IS NOT NULL;
