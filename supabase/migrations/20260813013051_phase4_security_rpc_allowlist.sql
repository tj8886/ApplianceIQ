insert into public.platform_security_rpc_allowlist(function_signature,allow_anon,allow_authenticated,rationale,reviewed_at,metadata)
values
 ('phase4_coaching_dashboard(uuid)',false,true,'Phase 4 organization coaching read RPC; returns data only when auth.uid() is an active organization member.',now(),'{"phase":4}'::jsonb),
 ('phase4_generate_coaching(uuid,uuid,date)',false,true,'Phase 4 coaching prescription RPC; requires organization membership and limits cross-user generation to organization admins.',now(),'{"phase":4}'::jsonb),
 ('phase4_complete_step(uuid,integer,uuid,numeric,jsonb)',false,true,'Phase 4 step mutation RPC; caller must be the intervention owner or an organization admin.',now(),'{"phase":4}'::jsonb),
 ('phase4_evaluate_intervention(uuid,boolean)',false,true,'Phase 4 outcome measurement RPC; caller must be intervention owner or organization admin and organization member.',now(),'{"phase":4}'::jsonb),
 ('phase4_generate_org_coaching(uuid,date,integer)',false,true,'Phase 4 bulk coaching generation RPC; organization admin only.',now(),'{"phase":4}'::jsonb),
 ('phase4_evaluate_due_org(uuid,integer)',false,true,'Phase 4 due-evaluation batch RPC; organization admin only.',now(),'{"phase":4}'::jsonb)
on conflict(function_signature) do update set allow_anon=excluded.allow_anon,allow_authenticated=excluded.allow_authenticated,rationale=excluded.rationale,reviewed_at=excluded.reviewed_at,metadata=coalesce(public.platform_security_rpc_allowlist.metadata,'{}'::jsonb)||excluded.metadata;
