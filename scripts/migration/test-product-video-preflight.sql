begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback product video gate','rollback-product-video-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign product video gate','rollback-product-video-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.video.native',native::text,true);perform set_config('test.video.actor',actor::text,true);perform set_config('test.video.org',org::text,true);perform set_config('test.video.other',other::text,true);
 perform set_config('test.video.counts',(select jsonb_build_array((select md5(string_agg(md5(to_jsonb(x)::text),'' order by id)) from tj.pim_video_discovery_jobs x),(select md5(string_agg(md5(to_jsonb(x)::text),'' order by id)) from tj.pim_product_videos x))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org'),'action','status'));
 if r->>'ok'<>'true' or r->>'discovery_enabled'<>'false' or r->>'global_publishing_enabled'<>'false' or r->>'provider_verified'<>'false' then raise exception 'unsafe_status';end if;
 r:=public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org')));
 if r->>'ok'<>'false' or r->>'videos_created'<>'0' then raise exception 'default_enrich_executed';end if;
 foreach a in array array['run'] loop
  r:=public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org'),'action',a));
  if r->>'error'<>'product_video_verification_required' or r->>'executed'<>'false' or r->>'provider_requests'<>'0' or r->>'videos_created'<>'0' or r::text like '%PRIVATE%' then raise exception 'payment_execution_or_leak';end if;
 end loop;
 begin perform public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.other')));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org'),'action','run','data',jsonb_build_object('brand','LG','url','https://PRIVATE.invalid')));raise exception 'client_price_accepted';exception when invalid_parameter_value then null;end;
 foreach a in array array['limit','source_url','job_id','product_id','run_key','video_url','embed_url'] loop
  begin perform public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org'),a,'PRIVATE UNVERIFIED'));raise exception 'legacy_payment_input_accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org'),'action','unknown'));raise exception 'unknown_action_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.video.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.video.org')::uuid and user_id=current_setting('test.video.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_product_video_preflight(jsonb_build_object('organization_id',current_setting('test.video.org')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_product_video_preflight(jsonb)','tj_private.product_video_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select jsonb_build_array((select md5(string_agg(md5(to_jsonb(x)::text),'' order by id)) from tj.pim_video_discovery_jobs x),(select md5(string_agg(md5(to_jsonb(x)::text),'' order by id)) from tj.pim_product_videos x))::text)<>current_setting('test.video.counts') then raise exception 'pim_products_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','product video gate','persisted_rows',0) verification;
