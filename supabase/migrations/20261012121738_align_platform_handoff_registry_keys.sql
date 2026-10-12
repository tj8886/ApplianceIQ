-- Align existing US catalogue rows and handoff keys with the deployment registry.
-- Preserve legacy keys, memberships and all current organization checks.
UPDATE tj.platform_modules m SET
 manifest=coalesce(m.manifest,'{}'::jsonb)||jsonb_build_object('registry_key',r.registry_key),
 app_url=r.production_url,updated_at=now()
FROM (VALUES
('platform','applianceiq-platform','https://appliance-iq-platform.netlify.app'),
('crm','crm','https://applianceiq-crm.netlify.app'),
('command-center','command-center','https://applianceiq-command-center.netlify.app'),
('intelligence_group','intelligence-group','https://applianceiq-intelligence-group.netlify.app'),
('product-iq','product-iq','https://applianceiq-product-iq-pim.netlify.app'),
('pim-scraper','pim-scraper','https://applianceiq-pim-scraper.netlify.app'),
('spec-iq','spec-iq','https://appliance-spec-iq.netlify.app'),
('academy','academy','https://iqacademy-appliance-training.netlify.app'),
('ai-coach','ai-coach','https://ai-iq-coach.netlify.app'),
('up-system','up-system','https://applianceiq-iq-up-system.netlify.app'),
('field','iq-field','https://applianceiq-ai-field.netlify.app'),
('brand_marketing','field-report-analytics','https://iq-field-report-analytics.netlify.app'),
('iq-build','iq-build','https://project-builder-iq.netlify.app'),
('mdf-coop','mdf-coop','https://applianceiq-mdf-coop-vr.netlify.app')
) AS r(module_key,registry_key,production_url) WHERE m.key=r.module_key;

CREATE OR REPLACE FUNCTION tj_private.issue_platform_handoff(p_user_id uuid,p_ticket_hash text,
 p_target_module_key text,p_context jsonb DEFAULT '{}') RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE uid uuid:=tj_private.handoff_source_user(p_user_id); org uuid; loc uuid;
BEGIN
 IF uid IS NULL OR p_ticket_hash IS NULL OR p_ticket_hash !~ '^[0-9a-f]{64}$'
 OR p_context IS NULL OR jsonb_typeof(p_context)<>'object'
 OR NOT EXISTS(SELECT 1 FROM tj.platform_modules m WHERE (m.key=p_target_module_key OR m.manifest->>'registry_key'=p_target_module_key) AND m.is_active IS TRUE)
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

CREATE OR REPLACE FUNCTION tj_private.consume_platform_handoff(p_ticket_hash text,p_target_module_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE t tj_private.platform_handoff_tickets; uid uuid;
BEGIN
 SELECT * INTO t FROM tj_private.platform_handoff_tickets
 WHERE ticket_hash=p_ticket_hash AND target_module_key=p_target_module_key
 AND consumed_at IS NULL AND expires_at>clock_timestamp() FOR UPDATE;
 IF t.ticket_hash IS NULL THEN RETURN NULL; END IF;
 uid:=tj_private.handoff_source_user(t.target_user_id);
 IF uid IS NULL OR uid<>t.source_user_id THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_modules m WHERE (m.key=t.target_module_key OR m.manifest->>'registry_key'=t.target_module_key) AND m.is_active IS TRUE)
 THEN RETURN NULL; END IF;
 IF t.organization_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE m.organization_id=t.organization_id AND m.user_id=uid AND m.status='active') THEN RETURN NULL; END IF;
 IF t.location_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l
 WHERE l.id=t.location_id AND l.organization_id=t.organization_id AND l.is_active IS TRUE) THEN RETURN NULL; END IF;
 UPDATE tj_private.platform_handoff_tickets SET consumed_at=clock_timestamp() WHERE ticket_hash=t.ticket_hash;
 RETURN jsonb_build_object('user_id',t.target_user_id,'context',t.context);
END $$;


NOTIFY pgrst,'reload schema';
