-- Fresh US invitations only. Imported invitation codes and direct browser writes stay private.
CREATE TABLE tj_private.manufacturer_invite_registry (
 invite_id uuid PRIMARY KEY REFERENCES tj.mfr_invites(id),
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 created_native uuid NOT NULL REFERENCES auth.users(id),
 created_actor uuid NOT NULL REFERENCES tj.source_auth_users(id),
 vendor_id uuid NOT NULL REFERENCES tj.mfr_vendors(id),
 email text NOT NULL,
 code_hash text NOT NULL UNIQUE,
 expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE tj_private.manufacturer_invite_registry ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.manufacturer_invite_registry FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX manufacturer_invite_org_idx ON tj_private.manufacturer_invite_registry(organization_id);
CREATE INDEX manufacturer_invite_native_idx ON tj_private.manufacturer_invite_registry(created_native);
CREATE INDEX manufacturer_invite_actor_idx ON tj_private.manufacturer_invite_registry(created_actor);
CREATE INDEX manufacturer_invite_vendor_idx ON tj_private.manufacturer_invite_registry(vendor_id);

CREATE FUNCTION tj_private.manufacturer_invite_admin(p_actor uuid,p_org uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p_actor IS NOT NULL AND EXISTS (
  SELECT 1 FROM tj.product_iq_platform_roles r WHERE r.user_id=p_actor
   AND r.organization_id IS NULL AND r.role IN('product_iq_super_admin','super_admin')
   AND r.status='active' AND (r.expires_at IS NULL OR r.expires_at>now())
 ) AND EXISTS (
  SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id
  WHERE m.user_id=p_actor AND m.status='active' AND m.role IN('owner','admin')
   AND o.status='active' AND o.deleted_at IS NULL AND (p_org IS NULL OR o.id=p_org)
 );
$$;
REVOKE ALL ON FUNCTION tj_private.manufacturer_invite_admin(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.manufacturer_invites(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 native uuid:=auth.uid(); actor uuid; recipient text; action text; is_admin boolean;
 org uuid; vid uuid; iid uuid; raw_code text; hash text; expiry timestamptz;
 v tj.mfr_vendors%ROWTYPE; inv tj.mfr_invites%ROWTYPE;
 reg tj_private.manufacturer_invite_registry%ROWTYPE; mem tj.mfr_members%ROWTYPE;
 items jsonb;
BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>8192
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','email','vendor_id','code','invite_id')) THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_request');
 END IF;
 action:=p_body->>'action';
 IF action IS NULL OR action NOT IN('context','create','list','accept','revoke') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 actor:=tj_private.microsoft_actor(native);
 IF actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_review_required'); END IF;
 SELECT lower(btrim(u.email)) INTO recipient FROM auth.users u WHERE u.id=native AND u.email_confirmed_at IS NOT NULL;
 IF recipient IS NULL OR recipient='' THEN RETURN jsonb_build_object('ok',false,'error','email_confirmation_required'); END IF;
 is_admin:=tj_private.manufacturer_invite_admin(actor);
 IF action='context' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',v1.id,'slug',v1.slug,'name',v1.name,'tier',v1.tier,'status',v1.status) ORDER BY v1.name),'[]'::jsonb)
   INTO items FROM tj.mfr_members m JOIN tj.mfr_vendors v1 ON v1.id=m.vendor_id
   WHERE m.user_id=actor AND m.status='active' AND (m.expires_at IS NULL OR m.expires_at>now()) AND v1.status='active';
  RETURN jsonb_build_object('ok',true,'role',jsonb_build_object('is_admin',is_admin,'is_manufacturer',jsonb_array_length(items)>0),'vendors',items);
 END IF;
 IF action IN('create','list','revoke') AND NOT is_admin THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
 IF action='list' THEN
  SELECT coalesce(jsonb_agg(x.row ORDER BY x.created_at DESC),'[]'::jsonb) INTO items FROM (
   SELECT jsonb_build_object('id',i.id,'email',r.email,'vendor_id',r.vendor_id,'vendor_name',v1.name,
    'status',CASE WHEN i.status='pending' AND r.expires_at<=now() THEN 'expired' ELSE i.status END,
    'created_at',r.created_at,'expires_at',r.expires_at,'accepted_at',i.accepted_at) AS row,r.created_at
   FROM tj_private.manufacturer_invite_registry r JOIN tj.mfr_invites i ON i.id=r.invite_id JOIN tj.mfr_vendors v1 ON v1.id=r.vendor_id
   WHERE tj_private.manufacturer_invite_admin(actor,r.organization_id) ORDER BY r.created_at DESC LIMIT 100
  ) x;
  RETURN jsonb_build_object('ok',true,'invites',items,'vendors',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) ORDER BY a.name),'[]'::jsonb) FROM tj.mfr_vendors a WHERE a.status='active'));
 END IF;
 IF action='create' THEN
  recipient:=lower(btrim(p_body->>'email'));
  IF recipient IS NULL OR length(recipient)>254 OR recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR coalesce(p_body->>'vendor_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
  vid:=(p_body->>'vendor_id')::uuid;
  SELECT * INTO v FROM tj.mfr_vendors WHERE id=vid AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','vendor_unavailable'); END IF;
  SELECT o.id INTO org FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id
   WHERE m.user_id=actor AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL ORDER BY o.id LIMIT 1;
  raw_code:=encode(extensions.gen_random_bytes(32),'hex'); hash:=encode(extensions.digest(raw_code,'sha256'),'hex'); expiry:=now()+interval '7 days';
  INSERT INTO tj.mfr_invites(email,vendor_id,vendor_slug,vendor_name,code,status,invited_by,invite_role,persona,scope_type,expires_at)
   VALUES(recipient,vid,v.slug,v.name,'US-'||hash,'pending',actor,'product_editor','manufacturer','brand',expiry) RETURNING id INTO iid;
  INSERT INTO tj_private.manufacturer_invite_registry(invite_id,organization_id,created_native,created_actor,vendor_id,email,code_hash,expires_at)
   VALUES(iid,org,native,actor,vid,recipient,hash,expiry);
  RETURN jsonb_build_object('ok',true,'id',iid,'code',raw_code,'email',recipient,'vendor_name',v.name,'expires_at',expiry);
 END IF;
 IF action='revoke' THEN
  IF coalesce(p_body->>'invite_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
  SELECT * INTO reg FROM tj_private.manufacturer_invite_registry WHERE invite_id=(p_body->>'invite_id')::uuid;
  IF NOT FOUND OR NOT tj_private.manufacturer_invite_admin(actor,reg.organization_id) THEN RETURN jsonb_build_object('ok',false,'error','invite_unavailable'); END IF;
  SELECT * INTO inv FROM tj.mfr_invites WHERE id=reg.invite_id FOR UPDATE;
  IF inv.status='pending' THEN UPDATE tj.mfr_invites SET status='revoked' WHERE id=inv.id; END IF;
  RETURN jsonb_build_object('ok',true,'status',CASE WHEN inv.status='pending' THEN 'revoked' ELSE inv.status END);
 END IF;
 -- Capability is bound to the confirmed native recipient and fresh US provenance.
 raw_code:=lower(btrim(p_body->>'code'));
 IF raw_code IS NULL OR raw_code !~ '^[0-9a-f]{64}$' THEN RETURN jsonb_build_object('ok',false,'error','invite_unavailable'); END IF;
 SELECT * INTO reg FROM tj_private.manufacturer_invite_registry WHERE code_hash=encode(extensions.digest(raw_code,'sha256'),'hex');
 IF NOT FOUND OR reg.email<>recipient OR reg.expires_at<=now() THEN RETURN jsonb_build_object('ok',false,'error','invite_unavailable'); END IF;
 SELECT * INTO inv FROM tj.mfr_invites WHERE id=reg.invite_id FOR UPDATE;
 IF NOT FOUND OR inv.status IS DISTINCT FROM 'pending' OR inv.expires_at IS DISTINCT FROM reg.expires_at
  OR inv.email IS DISTINCT FROM reg.email OR inv.vendor_id IS DISTINCT FROM reg.vendor_id OR inv.invited_by IS DISTINCT FROM reg.created_actor
  OR inv.code IS DISTINCT FROM 'US-'||reg.code_hash OR inv.persona IS DISTINCT FROM 'manufacturer'
  OR inv.scope_type IS DISTINCT FROM 'brand' OR inv.invite_role IS DISTINCT FROM 'product_editor'
  OR tj_private.microsoft_actor(reg.created_native) IS DISTINCT FROM reg.created_actor
  OR NOT tj_private.manufacturer_invite_admin(reg.created_actor,reg.organization_id) THEN RETURN jsonb_build_object('ok',false,'error','invite_unavailable'); END IF;
 SELECT * INTO v FROM tj.mfr_vendors WHERE id=reg.vendor_id FOR UPDATE;
 IF NOT FOUND OR v.status IS DISTINCT FROM 'active' THEN RETURN jsonb_build_object('ok',false,'error','invite_unavailable'); END IF;
 SELECT * INTO mem FROM tj.mfr_members WHERE user_id=actor AND vendor_id=reg.vendor_id FOR UPDATE;
 IF FOUND THEN
  IF mem.status IS DISTINCT FROM 'active' OR mem.role IS NULL OR mem.approved_by IS NULL OR mem.approved_at IS NULL OR mem.activated_at IS NULL OR (mem.expires_at IS NOT NULL AND mem.expires_at<=now()) THEN
   RETURN jsonb_build_object('ok',false,'error','membership_review_required');
  END IF;
 ELSE
  INSERT INTO tj.mfr_members(user_id,vendor_id,member_role,role,status,invited_by,approved_by,invitation_id,approved_at,activated_at,created_by,updated_by,updated_at)
   VALUES(actor,reg.vendor_id,'editor','product_editor','active',reg.created_actor,reg.created_actor,inv.id,now(),now(),reg.created_actor,actor,now());
 END IF;
 INSERT INTO tj.mfr_user_roles(user_id,is_manufacturer) VALUES(actor,true) ON CONFLICT(user_id) DO UPDATE SET is_manufacturer=true;
 UPDATE tj.mfr_invites SET status='accepted',accepted_at=now(),accepted_by=actor WHERE id=inv.id;
 RETURN jsonb_build_object('ok',true,'vendor_id',v.id,'vendor_name',v.name);
END;
$$;
REVOKE ALL ON FUNCTION tj_private.manufacturer_invites(jsonb) FROM PUBLIC,anon,authenticated,service_role;
-- Private implementation is not an exposed PostgREST schema; authenticated needs EXECUTE for the invoker wrapper.
GRANT EXECUTE ON FUNCTION tj_private.manufacturer_invites(jsonb) TO authenticated;
CREATE FUNCTION public.tj_runtime_manufacturer_invites(p_body jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.manufacturer_invites(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_manufacturer_invites(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_manufacturer_invites(jsonb) TO authenticated;
