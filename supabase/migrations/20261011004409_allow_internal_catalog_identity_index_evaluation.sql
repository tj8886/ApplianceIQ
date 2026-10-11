-- Index expressions execute as the catalog writer, including source status updates.
-- This immutable text-only normalizer reads no data and conveys no publication authority.
GRANT EXECUTE ON FUNCTION tj_private.pim_web_key(text) TO authenticated,service_role;
