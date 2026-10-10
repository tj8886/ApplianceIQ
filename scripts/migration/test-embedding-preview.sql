begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;source uuid;foreign_source uuid;global_source uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback embedding','rollback-embedding-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign embedding','rollback-embedding-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 insert into tj.ai_knowledge_sources(organization_id,source_key,title,source_type,visibility) values(org,'rollback-'||gen_random_uuid(),'PRIVATE SOURCE','test','organization') returning id into source;
 insert into tj.ai_knowledge_sources(organization_id,source_key,title,source_type,visibility) values(other,'rollback-'||gen_random_uuid(),'PRIVATE FOREIGN','test','organization') returning id into foreign_source;
 insert into tj.ai_knowledge_sources(source_key,title,source_type) values('rollback-global-'||gen_random_uuid(),'PRIVATE GLOBAL','test') returning id into global_source;
 insert into tj.ai_knowledge_chunks(organization_id,source_id,chunk_key,title,content) select org,source,gen_random_uuid()::text,'PRIVATE TITLE','PRIVATE CONTENT' from generate_series(1,26);
 insert into tj.ai_knowledge_chunks(organization_id,source_id,chunk_key,content) values(other,foreign_source,gen_random_uuid()::text,'PRIVATE FOREIGN'),(org,foreign_source,gen_random_uuid()::text,'PRIVATE MISMATCH'),(null,global_source,gen_random_uuid()::text,'PRIVATE GLOBAL');
 insert into tj.ai_knowledge_chunks(organization_id,source_id,chunk_key,content,embedding,embedding_model) values(org,source,gen_random_uuid()::text,'PRIVATE EMBEDDED',('['||repeat('0,',1023)||'1]')::public.vector,'PRIVATE MODEL');
 insert into tj.products(organization_id,brand,model,name,description) select org,'PRIVATE',gen_random_uuid()::text,'PRIVATE PRODUCT','PRIVATE DESCRIPTION' from generate_series(1,26);
 insert into tj.products(organization_id,brand,model,name) values(other,'PRIVATE',gen_random_uuid()::text,'PRIVATE FOREIGN');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.embed.native',native::text,true);perform set_config('test.embed.actor',actor::text,true);perform set_config('test.embed.org',org::text,true);perform set_config('test.embed.other',other::text,true);perform set_config('test.embed.source',source::text,true);perform set_config('test.embed.global',global_source::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;r2 jsonb;f text;t text;mode text;begin
 foreach f in array array['tj_knowledge_embedding_preview','tj_embedding_worker_preview'] loop
  execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode','preview');
  if r->>'page_count'<>'25' or r->>'has_more'<>'true' or r->>'embedding_enabled'<>'false' or r::text like '%PRIVATE%' then raise exception 'knowledge_scope_bound_or_redaction_failed';end if;
  execute format('select public.%I($1)',f) into r2 using jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode','preview','after_id',r->>'next_after_id');
  if r2->>'page_count'<>'1' or r2->>'has_more'<>'false' then raise exception 'knowledge_pagination_failed';end if;
  foreach mode in array array['query','batch','run'] loop
   execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode',mode,'text','PRIVATE QUERY');
   if r->>'error'<>'embedding_destination_verification_required' or r->>'vectors_written'<>'0' or r->>'run_created'<>'false' or r::text like '%PRIVATE%' then raise exception 'provider_or_write_enabled';end if;
  end loop;
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.embed.other'),'mode','preview');raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.embed.org'),'source_table','forged','mode','preview');raise exception 'table_override_accepted';exception when invalid_parameter_value then null;end;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode','preview');raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',current_setting('test.embed.native'),true);
 end loop;
 r:=public.tj_embedding_worker_preview(jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode','preview','source_table','products'));
 if r->>'page_count'<>'25' or r->>'has_more'<>'true' or r::text like '%PRIVATE%' then raise exception 'product_scope_failed';end if;
 r2:=public.tj_embedding_worker_preview(jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode','preview','source_table','products','after_id',r->>'next_after_id'));
 if r2->>'page_count'<>'1' then raise exception 'product_pagination_failed';end if;
end $$;
reset role;
update tj.ai_knowledge_sources set status='inactive' where id=current_setting('test.embed.source')::uuid;
set local role authenticated;
do $$declare r jsonb;begin r:=public.tj_knowledge_embedding_preview(jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode','preview'));if r->>'page_count'<>'0' then raise exception 'inactive_source_included';end if;end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.embed.org')::uuid and user_id=current_setting('test.embed.actor')::uuid;
set local role authenticated;
do $$declare f text;begin foreach f in array array['tj_knowledge_embedding_preview','tj_embedding_worker_preview'] loop begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.embed.org'),'mode','preview');raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end loop;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_knowledge_embedding_preview(jsonb)','public.tj_embedding_worker_preview(jsonb)','tj_private.embedding_preview(text,jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select count(*) from tj.ai_knowledge_chunks where organization_id=current_setting('test.embed.org')::uuid and embedding is not null)<>1 or exists(select 1 from tj.products where organization_id=current_setting('test.embed.org')::uuid and embedding is not null) or exists(select 1 from tj.embedding_worker_runs) then raise exception 'vectors_or_runs_written';end if;
 if not exists(select 1 from tj.ai_knowledge_chunks where organization_id=current_setting('test.embed.org')::uuid and embedding_model='PRIVATE MODEL' and embedding=('['||repeat('0,',1023)||'1]')::public.vector) then raise exception 'existing_vector_overwritten';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','tenant embedding previews','persisted_rows',0) verification;
