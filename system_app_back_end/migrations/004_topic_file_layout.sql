-- Which files a topic shows is decided by its layout, not by a flag on the file.
--
-- The layout holds a fixed number of slots (single 1, split 2, hero 3; row and
-- grid take everything). Files fill those slots in order_index order; files past
-- the last slot are not on screen and are reached only from the arrange dialog.
--
-- files.is_essence is dropped: order_index already carries the same information,
-- because arranging always wrote the shown files first.

ALTER TABLE topics
    ADD COLUMN file_layout TEXT NOT NULL DEFAULT 'single';

ALTER TABLE files
    DROP COLUMN is_essence;
