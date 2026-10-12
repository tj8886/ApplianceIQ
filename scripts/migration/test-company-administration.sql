BEGIN;
DO $$ DECLARE admin_u uuid; member_u uuid; org uuid; owner_source uuid; BEGIN
 SELECT im.target_user_id INTO admin_u FROM tj.source_user_identity_map im JOIN tj.platform_admins a ON a.user_id=im.source_user_id WHERE im.activation_status='activated' LIMIT 1;
 SELECT im.target_user_id,m.organization_id INTO member_u,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id WHERE im.activation_status='activated' AND m.status='active' AND m.role NOT IN ('owner','admin') AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 IF admin_u IS NULL OR member_u IS NULL THEN RAISE EXCEPTION 'Admin/member fixtures unavailable'; END IF;
 PERFORM set_config('test.admin',admin_u::text,true);PERFORM set_config('test.member',member_u::text,true);PERFORM set_config('test.member_org',org::text,true);
 PERFORM set_config('request.jwt.claim.sub',admin_u::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; org uuid; loc uuid; loc2 uuid; position uuid; owner uuid; old_count int; BEGIN
 r:=public.tj_runtime_company_admin(NULL,'bootstrap');IF r->>'platform_admin'<>'true' THEN RAISE EXCEPTION 'Admin identity resolution failed'; END IF;
 r:=public.tj_runtime_company_admin(NULL,'company_create',jsonb_build_object('name','Rollback company','slug','rollback-'||gen_random_uuid()::text));org:=(r->>'organization_id')::uuid;PERFORM set_config('test.new_org',org::text,true);
 r:=public.tj_runtime_company_admin(org,'snapshot');owner:=(r->'mems'->0->>'id')::uuid;
 PERFORM set_config('test.owner',owner::text,true);PERFORM set_config('test.owner_source',r->'mems'->0->>'user_id',true);
 r:=public.tj_runtime_company_admin(org,'company_save','{"name":"Updated company"}');IF r->'record'->>'name'<>'Updated company' THEN RAISE EXCEPTION 'Company update failed'; END IF;
 PERFORM public.tj_runtime_company_admin(org,'provision_roles');PERFORM public.tj_runtime_company_admin(org,'provision_roles');
 r:=public.tj_runtime_company_admin(org,'snapshot');IF jsonb_array_length(r->'roles')<>7 THEN RAISE EXCEPTION 'Role provisioning not idempotent'; END IF;
 r:=public.tj_runtime_company_admin(org,'role_save','{"role_name":"Fixture role","role_level":5}');position:=(r->'record'->>'id')::uuid;
 r:=public.tj_runtime_company_admin(org,'location_save','{"name":"Corporate","location_type":"corporate"}');loc:=(r->'record'->>'id')::uuid;
 r:=public.tj_runtime_company_admin(org,'location_save',jsonb_build_object('name','Store','location_type','store','parent_id',loc));loc2:=(r->'record'->>'id')::uuid;
 PERFORM set_config('test.location',loc2::text,true);
 PERFORM public.tj_runtime_company_admin(org,'member_save',jsonb_build_object('id',owner,'org_role_id',position,'visibility_scope','all'));
 BEGIN PERFORM public.tj_runtime_company_admin(org,'member_save',jsonb_build_object('id',owner,'status','removed'));RAISE EXCEPTION 'Last owner removal accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'last_owner_required' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(org,'member_save',jsonb_build_object('id',owner,'manager_id',owner));RAISE EXCEPTION 'Manager cycle accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'manager_cycle' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(org,'location_save',jsonb_build_object('id',loc,'parent_id',loc2));RAISE EXCEPTION 'Location cycle accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'location_cycle' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(org,'role_archive',jsonb_build_object('id',position));RAISE EXCEPTION 'Assigned role archived';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'role_in_use' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(org,'member_save',jsonb_build_object('id',owner,'organization_id',current_setting('test.member_org')));RAISE EXCEPTION 'Protected field accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'unsupported_field' THEN RAISE;END IF;END;
 PERFORM public.tj_runtime_company_admin(org,'member_locations',jsonb_build_object('user_id',current_setting('test.owner_source'),'location_ids',jsonb_build_array(loc2),'primary_location_id',loc2));
 r:=public.tj_runtime_company_admin(org,'snapshot');IF jsonb_array_length(r->'locmems')<>1 THEN RAISE EXCEPTION 'Atomic assignments failed';END IF;
 BEGIN PERFORM public.tj_runtime_company_admin(org,'member_locations',jsonb_build_object('user_id',current_setting('test.owner_source'),'location_ids',jsonb_build_array(loc2),'primary_location_id',loc));RAISE EXCEPTION 'Unchecked primary accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'primary_location_not_selected' THEN RAISE;END IF;END;
 PERFORM public.tj_runtime_company_admin(org,'entitlement_save','{"app_key":"crm","seats_included":5,"price_cents_monthly":4900}');
 PERFORM public.tj_runtime_company_admin(org,'location_archive',jsonb_build_object('id',loc2));r:=public.tj_runtime_company_admin(org,'snapshot');IF jsonb_array_length(r->'locmems')<>0 THEN RAISE EXCEPTION 'Archived assignments retained';END IF;
 IF has_table_privilege(current_user,'tj.organization_members','UPDATE') OR has_table_privilege(current_user,'tj.org_locations','INSERT') OR has_table_privilege(current_user,'tj_private.company_admin_audit','SELECT') THEN RAISE EXCEPTION 'Broad table privileges';END IF;
END $$;
RESET ROLE;
-- Turn the regular fixture into an admin of its own company only for this transaction.
UPDATE tj.organization_members SET role='admin' WHERE organization_id=current_setting('test.member_org')::uuid AND user_id=(SELECT source_user_id FROM tj.source_user_identity_map WHERE target_user_id=current_setting('test.member')::uuid AND activation_status='activated');
SELECT set_config('request.jwt.claim.sub',current_setting('test.member'),true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; org uuid:=current_setting('test.member_org')::uuid; BEGIN
 r:=public.tj_runtime_company_admin(NULL,'bootstrap');IF r->>'platform_admin'<>'false' THEN RAISE EXCEPTION 'Admin privilege escalation';END IF;
 r:=public.tj_runtime_company_admin(org,'location_save',jsonb_build_object('name','Own company fixture','location_type','store'));
 PERFORM public.tj_runtime_company_admin(org,'location_archive',jsonb_build_object('id',r->'record'->>'id'));
 BEGIN PERFORM public.tj_runtime_company_admin(current_setting('test.new_org')::uuid,'snapshot');RAISE EXCEPTION 'Foreign company read accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'company_admin_required' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(current_setting('test.new_org')::uuid,'location_save','{"name":"Bad","location_type":"store"}');RAISE EXCEPTION 'Foreign write accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'company_admin_required' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(NULL,'company_create','{"name":"Bad"}');RAISE EXCEPTION 'Company creation escalation';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'platform_admin_required' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(org,'entitlement_save','{"app_key":"crm"}');RAISE EXCEPTION 'Self-granted paid entitlement';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'platform_admin_required' THEN RAISE;END IF;END;
 BEGIN PERFORM public.tj_runtime_company_admin(org,'location_save',jsonb_build_object('name','Bad','location_type','store','parent_id',current_setting('test.location')));RAISE EXCEPTION 'Foreign location parent accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invalid_location_parent' THEN RAISE;END IF;END;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.member_org')::uuid AND user_id=(SELECT source_user_id FROM tj.source_user_identity_map WHERE target_user_id=current_setting('test.member')::uuid AND activation_status='activated');
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.tj_runtime_company_admin(current_setting('test.member_org')::uuid,'snapshot');RAISE EXCEPTION 'Member admin access';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'company_admin_required' THEN RAISE;END IF;END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN PERFORM public.tj_runtime_company_admin(NULL,'bootstrap');RAISE EXCEPTION 'Unmapped access accepted';EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'authentication_required' THEN RAISE;END IF;END;
 IF has_function_privilege('anon','public.tj_runtime_company_admin(uuid,text,jsonb)','EXECUTE') OR has_function_privilege('service_role','tj_private.company_admin(uuid,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Unexpected RPC grant';END IF;
END $$;
RESET ROLE;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM tj_private.company_admin_audit WHERE organization_id=current_setting('test.new_org')::uuid) THEN RAISE EXCEPTION 'No private audit trail'; END IF;END $$;
ROLLBACK;
SELECT 'Company administration: scoped reads/writes, hierarchy, owner protection, atomic assignments, entitlements and private audit passed; rolled back' result;
