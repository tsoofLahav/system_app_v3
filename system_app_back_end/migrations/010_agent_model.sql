-- The agent model belongs to the deployment, not to a row nobody edited.
--
-- agent_configs.model defaulted to 'gpt-4o-mini', and the runner prefers the
-- stored value over OPENAI_MODEL. So every workspace was silently pinned to a
-- mini model that no one chose, and changing the environment did nothing.
-- Empty now means "use OPENAI_MODEL"; a value means someone meant it.

ALTER TABLE agent_configs ALTER COLUMN model SET DEFAULT '';

UPDATE agent_configs SET model = '' WHERE model IN ('gpt-4o-mini', 'gpt-4o');
