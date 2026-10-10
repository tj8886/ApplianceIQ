-- US East handoff uses fresh private tickets, never imported Canadian tickets.
CREATE TABLE tj_private.platform_handoff_tickets (
 ticket_hash text PRIMARY KEY CHECK(ticket_hash ~ '^[0-9a-f]{64}$'),
 source_user_id uuid NOT NULL REFERENCES tj.source_auth_users(id) ON DELETE CASCADE,
 target_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 organization_id uuid REFERENCES tj.organizations(id) ON DELETE CASCADE,
 location_id uuid REFERENCES tj.org_locations(id) ON DELETE CASCADE,
 target_module_key text NOT NULL,
 context jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL DEFAULT (clock_timestamp()+interval '2 minutes'),
 consumed_at timestamptz,
 CHECK(expires_at>created_at AND expires_at<=created_at+interval '121 seconds')
);
ALTER TABLE tj_private.platform_handoff_tickets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.platform_handoff_tickets FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX platform_handoff_expiry_idx ON tj_private.platform_handoff_tickets(expires_at);
CREATE INDEX platform_handoff_source_idx ON tj_private.platform_handoff_tickets(source_user_id);
CREATE INDEX platform_handoff_target_idx ON tj_private.platform_handoff_tickets(target_user_id);
CREATE INDEX platform_handoff_org_idx ON tj_private.platform_handoff_tickets(organization_id);
CREATE INDEX platform_handoff_location_idx ON tj_private.platform_handoff_tickets(location_id);

CREATE FUNCTION tj_private.handoff_source_user(p_target_user_id uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT CASE WHEN count(*)=1 THEN min(m.source_user_id::text)::uuid ELSE NULL END
FROM tj.source_user_identity_map m JOIN tj.source_auth_users s ON s.id=m.source_user_id
JOIN auth.users u ON u.id=m.target_user_id
WHERE m.target_user_id=p_target_user_id AND m.identity_verified IS TRUE
AND m.mapping_status IN ('approved_map','approved_create','approved_invite')
AND m.approved_at IS NOT NULL AND nullif(btrim(m.approved_by),'') IS NOT NULL
AND m.activation_status='activated' AND m.activated_at IS NOT NULL
AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now())
AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false); $$;

CREATE FUNCTION tj_private.issue_platform_handoff(p_user_id uuid,p_ticket_hash text,
 p_target_module_key text,p_context jsonb DEFAULT '{}') RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE uid uuid:=tj_private.handoff_source_user(p_user_id); org uuid; loc uuid;
BEGIN
 IF uid IS NULL OR p_ticket_hash IS NULL OR p_ticket_hash !~ '^[0-9a-f]{64}$'
 OR p_context IS NULL OR jsonb_typeof(p_context)<>'object'
 OR NOT EXISTS(SELECT 1 FROM tj.platform_modules m WHERE m.key=p_target_module_key AND m.is_active IS TRUE)
 THEN RETURN false; END IF;
 org:=nullif(p_context->>'organization_id','')::uuid;
 loc:=nullif(p_context->>'location_id','')::uuid;
 IF org IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE m.organization_id=org AND m.user_id=uid AND m.status='active') THEN RETURN false; END IF;
 IF loc IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l
 WHERE l.id=loc AND l.organization_id=org AND l.is_active IS TRUE) THEN RETURN false; END IF;
 INSERT INTO tj_private.platform_handoff_tickets(ticket_hash,source_user_id,target_user_id,
 organization_id,location_id,target_module_key,context)
 VALUES(p_ticket_hash,uid,p_user_id,org,loc,p_target_module_key,p_context);
 RETURN true;
END $$;

CREATE FUNCTION tj_private.consume_platform_handoff(p_ticket_hash text,p_target_module_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE t tj_private.platform_handoff_tickets; uid uuid;
BEGIN
 SELECT * INTO t FROM tj_private.platform_handoff_tickets
 WHERE ticket_hash=p_ticket_hash AND target_module_key=p_target_module_key
 AND consumed_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE;
 IF t.ticket_hash IS NULL THEN RETURN NULL; END IF;
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
END $$;

-- Service-only endpoints in the existing public API avoid exposing tj before cutover.
CREATE FUNCTION public.issue_tj_platform_handoff(p_user_id uuid,p_ticket_hash text,
 p_target_module_key text,p_context jsonb DEFAULT '{}') RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.issue_platform_handoff(p_user_id,p_ticket_hash,p_target_module_key,p_context); $$;
CREATE FUNCTION public.consume_tj_platform_handoff(p_ticket_hash text,p_target_module_key text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.consume_platform_handoff(p_ticket_hash,p_target_module_key); $$;
REVOKE ALL ON FUNCTION tj_private.handoff_source_user(uuid),
 tj_private.issue_platform_handoff(uuid,text,text,jsonb),tj_private.consume_platform_handoff(text,text),
 public.issue_tj_platform_handoff(uuid,text,text,jsonb),public.consume_tj_platform_handoff(text,text)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT USAGE ON SCHEMA tj_private TO service_role;
GRANT EXECUTE ON FUNCTION tj_private.issue_platform_handoff(uuid,text,text,jsonb),
 tj_private.consume_platform_handoff(text,text),public.issue_tj_platform_handoff(uuid,text,text,jsonb),
 public.consume_tj_platform_handoff(text,text) TO service_role;
NOTIFY pgrst,'reload schema';
