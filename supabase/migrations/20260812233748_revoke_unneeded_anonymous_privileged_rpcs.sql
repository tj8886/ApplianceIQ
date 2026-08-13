do $$
declare r record;
begin
 for r in
   select p.oid::regprocedure as sig
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosecdef
     and has_function_privilege('anon',p.oid,'EXECUTE')
     and p.proname not in ('get_invite_preview','piq_preview_invite')
 loop
   execute format('revoke execute on function %s from anon', r.sig);
 end loop;
end $$;

insert into public.platform_security_rpc_allowlist(function_signature,allow_anon,allow_authenticated,rationale,metadata)
values
 ('get_invite_preview(text)',true,true,'Signed-out users must be able to preview an invite before authentication.',jsonb_build_object('classification','public_invite_preview')),
 ('piq_preview_invite(text)',true,true,'Signed-out users must be able to preview a Product IQ invite before authentication.',jsonb_build_object('classification','public_invite_preview'))
on conflict(function_signature) do update set
 allow_anon=excluded.allow_anon,
 allow_authenticated=excluded.allow_authenticated,
 rationale=excluded.rationale,
 reviewed_at=now(),
 metadata=excluded.metadata;
