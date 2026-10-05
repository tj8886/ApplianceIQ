CREATE OR REPLACE FUNCTION tj_private.consume_platform_handoff(p_ticket_hash text, p_target_module_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ DECLARE t tj_private.platform_handoff_tickets; uid uuid;
BEGIN
 SELECT * INTO t FROM tj_private.platform_handoff_tickets
 WHERE ticket_hash=p_ticket_hash AND target_module_key=p_target_module_key
 AND consumed_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE;
 IF t.ticket_hash IS NULL OR t.expires_at<=clock_timestamp() THEN RETURN NULL; END IF;
 uid:=tj_private.handoff_source_user(t.target_user_id);
 IF uid IS NULL OR uid<>t.source_user_id THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_modules m WHERE m.key=t.target_module_key AND m.is_active IS TRUE)
 THEN RETURN NULL; END IF;
 IF t.organization_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE m.organization_id=t.organization_id AND m.user_id=uid AND m.status='active') THEN RETURN NULL; END IF;
 IF t.location_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l
 WHERE l.id=t.location_id AND l.organization_id=t.organization_id AND l.is_active IS TRUE) THEN RETURN NULL; END IF;
 UPDATE tj_private.platform_handoff_tickets SET consumed_at=clock_timestamp() WHERE ticket_hash=t.ticket_hash;
 RETURN jsonb_build_object('user_id',t.target_user_id,'context',t.context);
END $function$
