insert into public.platform_security_rpc_allowlist(function_signature,allow_anon,allow_authenticated,rationale,metadata)
values
('phase6_refresh_revenue_opportunities(uuid)',false,true,'Phase 6 opportunity refresh; organization admin only and source data remains tenant scoped.',jsonb_build_object('phase',6)),
('phase6_command_center(uuid,integer)',false,true,'Phase 6 revenue intelligence dashboard; organization admin only.',jsonb_build_object('phase',6)),
('phase6_accept_action(uuid)',false,true,'Phase 6 manager action creation; organization admin only and creates an auditable manager assignment.',jsonb_build_object('phase',6))
on conflict(function_signature) do update set allow_anon=excluded.allow_anon,allow_authenticated=excluded.allow_authenticated,rationale=excluded.rationale,metadata=excluded.metadata,reviewed_at=now();
select public.refresh_platform_security_status();
