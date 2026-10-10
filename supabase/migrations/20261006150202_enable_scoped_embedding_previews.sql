-- Missing-vector metadata previews only. Never read source text or overwrite migrated vectors.
create function tj_private.embedding_preview(p_kind text,p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;after_id uuid;mode text;source_table text;items jsonb;more boolean;
begin
 if actor is null then raise exception using errcode='42501',message='embedding_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','mode','source_table','after_id','text'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;after_id:=(p_body->>'after_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='embedding_access_denied';end if;
 if p_kind is null or p_kind not in ('knowledge','worker') then raise exception using errcode='22023',message='invalid_kind';end if;
 source_table:=coalesce(p_body->>'source_table','ai_knowledge_chunks');
 if source_table not in ('ai_knowledge_chunks','products') or (p_kind='knowledge' and source_table<>'ai_knowledge_chunks') then raise exception using errcode='22023',message='invalid_source_table';end if;
 mode:=coalesce(p_body->>'mode',case when p_kind='knowledge' then 'batch' else 'run' end);
 if mode not in ('preview','query','batch','run') then raise exception using errcode='22023',message='invalid_mode';end if;
 if mode<>'preview' then return jsonb_build_object('ok',false,'error','embedding_destination_verification_required','executed',false,'embedding_enabled',false,'vectors_written',0,'run_created',false,'provider_requests',0);end if;
 if source_table='ai_knowledge_chunks' then
  with candidates as materialized (
   select c.id,c.updated_at from tj.ai_knowledge_chunks c join tj.ai_knowledge_sources s on s.id=c.source_id and s.organization_id=c.organization_id
   where c.organization_id=org and c.status='active' and s.status='active' and c.embedding is null and (after_id is null or c.id>after_id) order by c.id limit 26)
  select (select count(*)>25 from candidates),coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (select * from candidates order by id limit 25)x),'[]') into more,items;
 else
  with candidates as materialized (
   select p.id,p.updated_at from tj.products p where p.organization_id=org and p.embedding is null and (after_id is null or p.id>after_id) order by p.id limit 26)
  select (select count(*)>25 from candidates),coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (select * from candidates order by id limit 25)x),'[]') into more,items;
 end if;
 return jsonb_build_object('ok',true,'organization_id',org,'source_table',source_table,'preview_only',true,'executed',false,'embedding_enabled',false,'scheduler_enabled',false,'vectors_written',0,'run_created',false,
  'basis','missing_vectors_only','items',items,'page_count',jsonb_array_length(items),'has_more',more,'next_after_id',case when more then items->24->>'id' else null end,
  'blockers',jsonb_build_array('reviewed_provider_and_model_routing_required','query_document_embedding_space_compatibility_required','source_hash_and_atomic_stale_write_guard_required','validated_finite_vector_dimension_and_response_order_required','scoped_least_privilege_worker_and_global_corpus_authority_required','bounded_inputs_rate_limits_and_cost_governance_required'));
end $$;
revoke all on function tj_private.embedding_preview(text,jsonb) from public,anon,service_role;
grant execute on function tj_private.embedding_preview(text,jsonb) to authenticated;
create function public.tj_knowledge_embedding_preview(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.embedding_preview('knowledge',p_body);$$;
create function public.tj_embedding_worker_preview(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.embedding_preview('worker',p_body);$$;
revoke all on function public.tj_knowledge_embedding_preview(jsonb),public.tj_embedding_worker_preview(jsonb) from public,anon,service_role;
grant execute on function public.tj_knowledge_embedding_preview(jsonb),public.tj_embedding_worker_preview(jsonb) to authenticated;
notify pgrst,'reload schema';
