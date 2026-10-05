-- Bind the checked capability function at definition time; anon receives no schema USAGE.
CREATE OR REPLACE FUNCTION public.tj_runtime_get_invite_preview(p_code text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' RETURN tj_private.get_invite_preview(p_code);
NOTIFY pgrst,'reload schema';
