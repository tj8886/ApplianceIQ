begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;account uuid;foreign_account uuid;job uuid;bad_job uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback enrichment','rollback-enrichment-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign enrichment','rollback-enrichment-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 insert into tj.aicrm_accounts(organization_id,company_name) values(org,'PRIVATE ACCOUNT') returning id into account;
 insert into tj.aicrm_accounts(organization_id,company_name) values(other,'PRIVATE FOREIGN ACCOUNT') returning id into foreign_account;
 insert into tj.aicrm_ai_enrichment_jobs(organization_id,account_id,job_type,provider,status,input_payload,error_message) values(org,account,'company_summary','anthropic','failed','{"private":"PRIVATE INPUT"}','PRIVATE ERROR') returning id into job;
 insert into tj.aicrm_ai_enrichment_jobs(organization_id,account_id,job_type,provider,status) values(org,foreign_account,'company_summary','mock','failed') returning id into bad_job;
 perform set_config('request.jwt.claim.sub',native::text,true);
 perform set_config('test.crm.native',native::text,true);perform set_config('test.crm.actor',actor::text,true);perform set_config('test.crm.org',org::text,true);perform set_config('test.crm.other',other::text,true);perform set_config('test.crm.account',account::text,true);perform set_config('test.crm.foreign',foreign_account::text,true);perform set_config('test.crm.job',job::text,true);perform set_config('test.crm.bad_job',bad_job::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;t text;begin
 r:=public.tj_crm_enrichment_preflight(jsonb_build_object('mode','status','existing_job_id',current_setting('test.crm.job')));
 if r->>'ok'<>'true' or r->>'enrichment_enabled'<>'false' or r#>>'{job,retry_eligible}'<>'true' or r::text like '%PRIVATE%' then raise exception 'unsafe_job_status';end if;
 foreach t in array array['mock','anthropic'] loop
  r:=public.tj_crm_enrichment_preflight(jsonb_build_object('account_id',current_setting('test.crm.account'),'job_type','company_summary','provider',t));
  if r->>'error'<>'crm_enrichment_verification_required' or r->>'executed'<>'false' or r->>'job_created'<>'false' then raise exception 'provider_executed';end if;
 end loop;
 r:=public.tj_crm_enrichment_preflight(jsonb_build_object('mode','retry','existing_job_id',current_setting('test.crm.job')));if r->>'error'<>'crm_enrichment_verification_required' then raise exception 'retry_executed';end if;
 begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('mode','status','account_id',current_setting('test.crm.foreign')));raise exception 'foreign_account_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('mode','status','existing_job_id',current_setting('test.crm.bad_job')));raise exception 'foreign_job_join_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('mode','status','existing_job_id',current_setting('test.crm.job'),'organization_id',current_setting('test.crm.other')));raise exception 'foreign_org_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('account_id',current_setting('test.crm.account'),'job_type','bogus'));raise exception 'unknown_type_accepted';exception when invalid_parameter_value then null;end;
 begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('account_id',current_setting('test.crm.account'),'job_type','company_summary','provider','bogus'));raise exception 'provider_defaulted';exception when invalid_parameter_value then null;end;
 begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('existing_job_id',current_setting('test.crm.job'),'provider','mock'));raise exception 'job_provider_overridden';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('mode','status','account_id',current_setting('test.crm.account')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.crm.native'),true);
end $$;
reset role;
update tj.aicrm_ai_enrichment_jobs set status='completed' where id=current_setting('test.crm.job')::uuid;
set local role authenticated;
do $$declare r jsonb;begin r:=public.tj_crm_enrichment_preflight(jsonb_build_object('mode','retry','existing_job_id',current_setting('test.crm.job')));if r->>'error'<>'only_failed_jobs_can_retry' then raise exception 'completed_retry_accepted';end if;end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.crm.org')::uuid and user_id=current_setting('test.crm.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_crm_enrichment_preflight(jsonb_build_object('mode','status','account_id',current_setting('test.crm.account')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_crm_enrichment_preflight(jsonb)','tj_private.crm_enrichment_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select count(*) from tj.aicrm_ai_enrichment_jobs where organization_id=current_setting('test.crm.org')::uuid)<>2 or exists(select 1 from tj.aicrm_enrichment_runs where organization_id=current_setting('test.crm.org')::uuid) or exists(select 1 from tj.aicrm_ai_research where organization_id=current_setting('test.crm.org')::uuid) then raise exception 'enrichment_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','scoped CRM enrichment readiness','persisted_rows',0) verification;
