-- Section-mode and topic-mode each keep their own task order in a view.
-- order_index stays section-mode; topic_order_index is copied from it so
-- existing views keep their order until the two modes diverge.

ALTER TABLE view_task_memberships
    ADD COLUMN IF NOT EXISTS topic_order_index INTEGER NOT NULL DEFAULT 0;

UPDATE view_task_memberships
SET topic_order_index = order_index
WHERE topic_order_index = 0 AND order_index <> 0;
