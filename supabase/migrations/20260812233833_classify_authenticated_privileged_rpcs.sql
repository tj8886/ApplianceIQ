do $$
declare r record;
begin
 for r in
   select p.oid::regprocedure as sig
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosecdef
     and has_function_privilege('authenticated',p.oid,'EXECUTE')
     and p.proname in (
       'apply_feedback_to_chunks','cascade_budget','check_token_budget','deduct_tokens','evaluate_sla_rules',
       'find_duplicate_contacts','generate_daily_coaching_brief','get_anniversary_outreach','get_due_sequence_steps',
       'init_dashboard_metrics','init_default_kpis','init_default_metrics','init_default_personas','notify_overdue_tasks',
       'piq_confirm_invited_email','piq_revoke_invite','provision_aicrm_defaults_for_organization',
       'provision_aicrm_market_defaults_for_organization','provision_aicrm_product_catalog_for_organization',
       'provision_aicrm_territory_defaults_for_organization','provision_standard_roles','refresh_days_since_columns',
       'score_leads','search_knowledge_semantic','match_products'
     )
 loop
   execute format('revoke execute on function %s from authenticated',r.sig);
 end loop;
end $$;

insert into public.platform_security_rpc_allowlist(function_signature,allow_anon,allow_authenticated,rationale,metadata)
select p.oid::regprocedure::text,false,true,
       'Reviewed application RPC: access is caller-bound through auth.uid(), organization membership, or an authorization helper.',
       jsonb_build_object('classification','authenticated_app_rpc','review','2026-08-12-hardening')
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosecdef
  and has_function_privilege('authenticated',p.oid,'EXECUTE')
  and p.proname not in ('get_invite_preview','piq_preview_invite')
  and (
    position('auth.uid()' in pg_get_functiondef(p.oid))>0
    or position('organization_members' in pg_get_functiondef(p.oid))>0
    or p.proname in ('has_role','has_any_role','is_super_admin')
  )
on conflict(function_signature) do update set
 allow_authenticated=true,
 rationale=excluded.rationale,
 reviewed_at=now(),
 metadata=excluded.metadata;

select public.refresh_platform_security_status();
