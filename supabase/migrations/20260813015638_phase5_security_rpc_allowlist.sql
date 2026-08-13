insert into public.platform_security_rpc_allowlist(function_signature,allow_anon,allow_authenticated,rationale,reviewed_at,metadata)
values
 ('phase5_refresh_profile(uuid,uuid)',false,true,'Phase 5 adaptive profile read/refresh; requires organization membership and limits cross-user access to organization admins.',now(),'{"phase":5}'::jsonb),
 ('phase5_select_strategy(uuid,uuid,text,uuid)',false,true,'Phase 5 strategy selector; same organization membership and owner/admin boundary as the adaptive profile.',now(),'{"phase":5}'::jsonb),
 ('phase5_apply_adaptation(uuid)',false,true,'Phase 5 intervention personalization; caller must own the intervention or be an organization admin.',now(),'{"phase":5}'::jsonb),
 ('phase5_generate_adaptive_coaching(uuid,uuid,date)',false,true,'Phase 5 adaptive coaching generation; requires membership and limits cross-user generation to organization admins.',now(),'{"phase":5}'::jsonb),
 ('phase5_generate_org_adaptive_coaching(uuid,date,integer)',false,true,'Phase 5 organization adaptive coaching generation; organization admin only.',now(),'{"phase":5}'::jsonb),
 ('phase5_rep_plan(uuid,uuid)',false,true,'Phase 5 rep plan read; owner or organization admin only.',now(),'{"phase":5}'::jsonb),
 ('phase5_manager_dashboard(uuid)',false,true,'Phase 5 adaptive intelligence dashboard; organization admin only.',now(),'{"phase":5}'::jsonb),
 ('phase5_manager_recommendations(uuid,integer)',false,true,'Phase 5 manager recommendations; organization admin only.',now(),'{"phase":5}'::jsonb)
on conflict(function_signature) do update set allow_anon=excluded.allow_anon,allow_authenticated=excluded.allow_authenticated,rationale=excluded.rationale,reviewed_at=excluded.reviewed_at,metadata=coalesce(public.platform_security_rpc_allowlist.metadata,'{}'::jsonb)||excluded.metadata;
