-- Phase 7: Autonomous Action Orchestration
-- Mirrors the production Phase 7 schema/functions. Idempotent for existing environments.

create table if not exists public.phase7_automation_policies (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  action_type text not null, action_module text, mode text not null default 'approval_required' check(mode in ('disabled','approval_required','auto_execute')),
  max_priority_score numeric, max_revenue_impact numeric, max_margin_impact numeric, require_financial_confidence numeric not null default 0,
  created_by uuid, updated_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,action_type,action_module)
);
create table if not exists public.phase7_action_runs (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  phase6_opportunity_id uuid references public.phase6_revenue_opportunities(id) on delete set null, action_type text not null, action_module text,
  subject_type text, subject_id uuid, policy_id uuid references public.phase7_automation_policies(id) on delete set null, policy_mode text not null,
  status text not null default 'pending_approval' check(status in ('pending_approval','approved','rejected','executing','executed','failed','cancelled','reversed')),
  recommended_action text, estimated_revenue_impact numeric, estimated_margin_impact numeric, impact_confidence numeric, priority_score numeric,
  expected_metric_key text, baseline_value numeric, target_value numeric, due_at timestamptz, approved_by uuid, approved_at timestamptz,
  rejected_by uuid, rejected_at timestamptz, rejection_reason text, executed_by uuid, executed_at timestamptz,
  execution_result jsonb not null default '{}'::jsonb, error_message text,
  outcome_status text not null default 'pending' check(outcome_status in ('pending','improved','no_change','regressed','insufficient_evidence')),
  outcome_value numeric, outcome_measured_at timestamptz, idempotency_key text not null unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.phase7_action_audit (
  id bigint generated always as identity primary key, action_run_id uuid not null references public.phase7_action_runs(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade, event_type text not null, actor_id uuid,
  actor_type text not null default 'user', details jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
alter table public.phase7_automation_policies enable row level security;
alter table public.phase7_action_runs enable row level security;
alter table public.phase7_action_audit enable row level security;
revoke all on public.phase7_automation_policies,public.phase7_action_runs,public.phase7_action_audit from public,anon,authenticated;
grant all on public.phase7_automation_policies,public.phase7_action_runs,public.phase7_action_audit to service_role;
create index if not exists phase7_policy_org_idx on public.phase7_automation_policies(organization_id,mode);
create index if not exists phase7_runs_org_status_idx on public.phase7_action_runs(organization_id,status,priority_score desc);
create index if not exists phase7_runs_due_idx on public.phase7_action_runs(due_at) where outcome_status='pending';
create index if not exists phase7_audit_run_idx on public.phase7_action_audit(action_run_id,created_at desc);

create or replace function public.phase7_seed_default_policies(p_organization_id uuid) returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_count integer;
begin
 if v_actor is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 insert into public.phase7_automation_policies(organization_id,action_type,action_module,mode,created_by,updated_by) values
 (p_organization_id,'performance_gap','ai-coach','approval_required',v_actor,v_actor),(p_organization_id,'performance_gap','academy','approval_required',v_actor,v_actor),
 (p_organization_id,'crm_pipeline','crm','approval_required',v_actor,v_actor),(p_organization_id,'manager_task',null,'auto_execute',v_actor,v_actor),
 (p_organization_id,'customer_outreach','crm','disabled',v_actor,v_actor) on conflict(organization_id,action_type,action_module) do nothing;
 get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function public.phase7_set_policy(p_organization_id uuid,p_action_type text,p_action_module text,p_mode text,p_max_priority_score numeric default null,p_max_revenue_impact numeric default null,p_max_margin_impact numeric default null,p_require_financial_confidence numeric default 0) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
 if v_actor is null or not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 if p_mode not in ('disabled','approval_required','auto_execute') then raise exception 'Invalid mode'; end if;
 if p_action_type='customer_outreach' and p_mode='auto_execute' then raise exception 'Customer outreach cannot be auto-executed in Phase 7'; end if;
 insert into public.phase7_automation_policies(organization_id,action_type,action_module,mode,max_priority_score,max_revenue_impact,max_margin_impact,require_financial_confidence,created_by,updated_by,updated_at)
 values(p_organization_id,p_action_type,p_action_module,p_mode,p_max_priority_score,p_max_revenue_impact,p_max_margin_impact,coalesce(p_require_financial_confidence,0),v_actor,v_actor,now())
 on conflict(organization_id,action_type,action_module) do update set mode=excluded.mode,max_priority_score=excluded.max_priority_score,max_revenue_impact=excluded.max_revenue_impact,max_margin_impact=excluded.max_margin_impact,require_financial_confidence=excluded.require_financial_confidence,updated_by=v_actor,updated_at=now() returning id into v_id;
 return jsonb_build_object('status','saved','policy_id',v_id);
end $$;

create or replace function public.phase7_execute_run(p_action_run_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.phase7_action_runs%rowtype; v_actor uuid:=auth.uid(); v_assignment jsonb; v_coach jsonb; v_result jsonb; v_assignment_id uuid;
begin
 select * into r from public.phase7_action_runs where id=p_action_run_id for update; if r.id is null then raise exception 'Action run not found'; end if;
 if v_actor is not null and not public.is_org_admin(r.organization_id) then raise exception 'Organization admin required'; end if;
 if r.status='executed' then return jsonb_build_object('status','already_executed','result',r.execution_result); end if;
 if r.status not in ('approved','executing') and not(r.policy_mode='auto_execute' and r.status='pending_approval') then raise exception 'Action is not executable in status %',r.status; end if;
 update public.phase7_action_runs set status='executing',executed_by=v_actor,updated_at=now() where id=r.id;
 insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'execution_started',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('module',r.action_module));
 begin
  if r.action_module='ai-coach' and r.subject_type='employee' and r.subject_id is not null then select public.phase5_generate_adaptive_coaching(r.organization_id,r.subject_id,current_date) into v_coach; v_result=jsonb_build_object('handler','adaptive_coaching','result',v_coach);
  else
   if r.phase6_opportunity_id is not null then select public.phase6_accept_action(r.phase6_opportunity_id) into v_assignment; v_assignment_id=nullif(v_assignment->>'assignment_id','')::uuid;
   else insert into public.ai_manager_assignments(organization_id,title,instructions,assigned_by,assigned_to,priority,status,due_at,source,metadata,assigned_role) values(r.organization_id,coalesce(r.recommended_action,'IQ recommended action'),coalesce(r.recommended_action,'Complete recommended action'),v_actor,case when r.subject_type='employee' then r.subject_id else null end,case when r.priority_score>=70 then 'critical' when r.priority_score>=45 then 'high' else 'medium' end,'open',coalesce(r.due_at,now()+interval '1 day'),'phase7_orchestration',jsonb_build_object('phase7_action_run_id',r.id,'action_module',r.action_module),'manager') returning id into v_assignment_id; v_assignment=jsonb_build_object('status','accepted','assignment_id',v_assignment_id); end if;
   v_result=jsonb_build_object('handler','manager_assignment','result',v_assignment);
  end if;
  update public.phase7_action_runs set status='executed',executed_at=now(),execution_result=v_result,error_message=null,updated_at=now() where id=r.id;
  insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'executed',v_actor,case when v_actor is null then 'service' else 'user' end,v_result);
  return jsonb_build_object('status','executed','action_run_id',r.id,'result',v_result);
 exception when others then update public.phase7_action_runs set status='failed',error_message=sqlerrm,updated_at=now() where id=r.id; insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'failed',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('error',sqlerrm)); raise; end;
end $$;

create or replace function public.phase7_orchestrate_opportunity(p_opportunity_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o public.phase6_revenue_opportunities%rowtype; p public.phase7_automation_policies%rowtype; v_actor uuid:=auth.uid(); v_run uuid; v_mode text; v_key text; v_exec jsonb;
begin
 select * into o from public.phase6_revenue_opportunities where id=p_opportunity_id; if o.id is null then raise exception 'Opportunity not found'; end if; if v_actor is not null and not public.is_org_admin(o.organization_id) then raise exception 'Organization admin required'; end if;
 perform public.phase7_seed_default_policies(o.organization_id); select * into p from public.phase7_automation_policies where organization_id=o.organization_id and action_type=o.opportunity_type and action_module is not distinct from o.action_module limit 1; if p.id is null then select * into p from public.phase7_automation_policies where organization_id=o.organization_id and action_type='manager_task' and action_module is null limit 1; end if;
 v_mode=coalesce(p.mode,'approval_required'); if v_mode='auto_execute' and ((p.max_priority_score is not null and o.priority_score>p.max_priority_score) or (p.max_revenue_impact is not null and coalesce(o.estimated_revenue_impact,0)>p.max_revenue_impact) or (p.max_margin_impact is not null and coalesce(o.estimated_margin_impact,0)>p.max_margin_impact) or coalesce(o.impact_confidence,0)<coalesce(p.require_financial_confidence,0)) then v_mode='approval_required'; end if;
 v_key='phase7:'||o.id::text; insert into public.phase7_action_runs(organization_id,phase6_opportunity_id,action_type,action_module,subject_type,subject_id,policy_id,policy_mode,status,recommended_action,estimated_revenue_impact,estimated_margin_impact,impact_confidence,priority_score,expected_metric_key,baseline_value,target_value,due_at,idempotency_key) values(o.organization_id,o.id,o.opportunity_type,o.action_module,o.subject_type,o.subject_id,p.id,v_mode,case when v_mode='disabled' then 'cancelled' else 'pending_approval' end,o.recommended_action,o.estimated_revenue_impact,o.estimated_margin_impact,o.impact_confidence,o.priority_score,o.metric_key,o.actual_value,o.target_value,now()+interval '7 days',v_key) on conflict(idempotency_key) do update set updated_at=now() returning id into v_run;
 insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(v_run,o.organization_id,'policy_evaluated',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('mode',v_mode,'policy_id',p.id,'priority',o.priority_score));
 if v_mode='auto_execute' then update public.phase7_action_runs set status='approved',approved_by=v_actor,approved_at=now() where id=v_run and status='pending_approval'; select public.phase7_execute_run(v_run) into v_exec; return jsonb_build_object('status','auto_executed','action_run_id',v_run,'execution',v_exec); elsif v_mode='disabled' then return jsonb_build_object('status','disabled','action_run_id',v_run); else return jsonb_build_object('status','pending_approval','action_run_id',v_run); end if;
end $$;

create or replace function public.phase7_decide_action(p_action_run_id uuid,p_decision text,p_reason text default null) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.phase7_action_runs%rowtype; v_actor uuid:=auth.uid(); v_exec jsonb;
begin select * into r from public.phase7_action_runs where id=p_action_run_id for update; if r.id is null then raise exception 'Action run not found'; end if; if v_actor is null or not public.is_org_admin(r.organization_id) then raise exception 'Organization admin required'; end if; if r.status<>'pending_approval' then raise exception 'Action is not pending approval'; end if;
 if p_decision='approve' then update public.phase7_action_runs set status='approved',approved_by=v_actor,approved_at=now(),updated_at=now() where id=r.id; insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,details) values(r.id,r.organization_id,'approved',v_actor,jsonb_build_object('reason',p_reason)); select public.phase7_execute_run(r.id) into v_exec; return v_exec;
 elsif p_decision='reject' then update public.phase7_action_runs set status='rejected',rejected_by=v_actor,rejected_at=now(),rejection_reason=p_reason,updated_at=now() where id=r.id; insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,details) values(r.id,r.organization_id,'rejected',v_actor,jsonb_build_object('reason',p_reason)); return jsonb_build_object('status','rejected','action_run_id',r.id); else raise exception 'Decision must be approve or reject'; end if;
end $$;

create or replace function public.phase7_command_center(p_organization_id uuid,p_limit integer default 25) returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); begin if v_actor is null or not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 return jsonb_build_object('summary',jsonb_build_object('pending_approval',(select count(*) from public.phase7_action_runs where organization_id=p_organization_id and status='pending_approval'),'executed_7d',(select count(*) from public.phase7_action_runs where organization_id=p_organization_id and status='executed' and executed_at>=now()-interval '7 days'),'failed',(select count(*) from public.phase7_action_runs where organization_id=p_organization_id and status='failed'),'auto_policies',(select count(*) from public.phase7_automation_policies where organization_id=p_organization_id and mode='auto_execute')),
 'policies',coalesce((select jsonb_agg(to_jsonb(x) order by x.action_type,x.action_module) from (select id,action_type,action_module,mode,max_priority_score,max_revenue_impact,max_margin_impact,require_financial_confidence from public.phase7_automation_policies where organization_id=p_organization_id)x),'[]'::jsonb),
 'actions',coalesce((select jsonb_agg(to_jsonb(x) order by x.priority_score desc,x.created_at asc) from (select id,phase6_opportunity_id,action_type,action_module,subject_type,subject_id,policy_mode,status,recommended_action,estimated_revenue_impact,estimated_margin_impact,impact_confidence,priority_score,expected_metric_key,baseline_value,target_value,due_at,created_at,error_message from public.phase7_action_runs where organization_id=p_organization_id and status in ('pending_approval','approved','executing','failed') order by priority_score desc limit greatest(1,least(coalesce(p_limit,25),100)))x),'[]'::jsonb)); end $$;

create or replace function public.phase7_run_cycle(p_organization_id uuid,p_limit integer default 50) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); o record; v_result jsonb; v_created integer:=0; v_auto integer:=0; v_pending integer:=0; v_disabled integer:=0;
begin if v_actor is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if; perform public.phase7_seed_default_policies(p_organization_id); perform public.phase6_refresh_revenue_opportunities(p_organization_id); for o in select id from public.phase6_revenue_opportunities where organization_id=p_organization_id and status='open' order by priority_score desc limit greatest(1,least(coalesce(p_limit,50),200)) loop select public.phase7_orchestrate_opportunity(o.id) into v_result; v_created:=v_created+1; if v_result->>'status'='auto_executed' then v_auto:=v_auto+1; elsif v_result->>'status'='pending_approval' then v_pending:=v_pending+1; elsif v_result->>'status'='disabled' then v_disabled:=v_disabled+1; end if; end loop; return jsonb_build_object('evaluated',v_created,'auto_executed',v_auto,'pending_approval',v_pending,'disabled',v_disabled); end $$;

create or replace function public.phase7_measure_due(p_organization_id uuid default null) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); r record; v_actual numeric; v_before_gap numeric; v_after_gap numeric; v_status text; v_n integer:=0;
begin if p_organization_id is not null and v_actor is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if; for r in select * from public.phase7_action_runs where status='executed' and outcome_status='pending' and due_at<=now() and (p_organization_id is null or organization_id=p_organization_id) loop v_actual:=null; if r.subject_type='employee' and r.subject_id is not null and r.expected_metric_key is not null then select d.actual_value into v_actual from public.performance_metric_diagnostics d where d.organization_id=r.organization_id and d.user_id=r.subject_id and d.metric_key=r.expected_metric_key order by d.computed_at desc limit 1; end if; if v_actual is null or r.baseline_value is null or r.target_value is null then v_status:='insufficient_evidence'; else v_before_gap:=abs(r.target_value-r.baseline_value); v_after_gap:=abs(r.target_value-v_actual); if v_after_gap<v_before_gap*.9 then v_status:='improved'; elsif v_after_gap>v_before_gap*1.1 then v_status:='regressed'; else v_status:='no_change'; end if; end if; update public.phase7_action_runs set outcome_status=v_status,outcome_value=v_actual,outcome_measured_at=now(),updated_at=now() where id=r.id; insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'outcome_measured',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('status',v_status,'baseline',r.baseline_value,'target',r.target_value,'actual',v_actual)); insert into public.intelligence_outcomes(organization_id,entity_id,outcome_type,outcome_value,outcome_label,success,weight,metadata,source_system,source_record_id,occurred_at,recorded_by) values(r.organization_id,null,'phase7_action_effectiveness',v_actual,v_status,(v_status='improved'),coalesce(r.impact_confidence,.5),jsonb_build_object('phase7_action_run_id',r.id,'metric_key',r.expected_metric_key,'baseline',r.baseline_value,'target',r.target_value),'phase7_orchestration',r.id::text,now(),v_actor); v_n:=v_n+1; end loop; return jsonb_build_object('measured',v_n); end $$;

create or replace function public.phase7_reverse_action(p_action_run_id uuid,p_reason text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r public.phase7_action_runs%rowtype; v_actor uuid:=auth.uid(); v_assignment_id uuid; v_reversible boolean:=false;
begin select * into r from public.phase7_action_runs where id=p_action_run_id for update; if r.id is null then raise exception 'Action run not found'; end if; if v_actor is null or not public.is_org_admin(r.organization_id) then raise exception 'Organization admin required'; end if; if r.status<>'executed' then raise exception 'Only executed actions can be reversed'; end if; begin v_assignment_id=nullif(r.execution_result#>>'{result,result,assignment_id}','')::uuid; exception when others then v_assignment_id:=null; end; if v_assignment_id is not null then update public.ai_manager_assignments set status='cancelled',blocked_reason=coalesce(p_reason,'Reversed by manager'),updated_at=now() where id=v_assignment_id and status not in ('completed','cancelled'); v_reversible:=found; end if; update public.phase7_action_runs set status='reversed',updated_at=now() where id=r.id; insert into public.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,details) values(r.id,r.organization_id,'reversed',v_actor,jsonb_build_object('reason',p_reason,'downstream_reversed',v_reversible,'assignment_id',v_assignment_id)); return jsonb_build_object('status','reversed','downstream_reversed',v_reversible,'assignment_id',v_assignment_id); end $$;

create or replace function public.phase7_run_scheduled_cycles() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o record; v_total integer:=0; v_auto integer:=0; v_pending integer:=0; v_r jsonb;
begin if auth.uid() is not null then raise exception 'Service execution only'; end if; for o in select distinct organization_id from public.phase6_revenue_opportunities where status='open' union select distinct organization_id from public.phase7_automation_policies loop begin select public.phase7_run_cycle(o.organization_id,50) into v_r; v_total:=v_total+coalesce((v_r->>'evaluated')::integer,0); v_auto:=v_auto+coalesce((v_r->>'auto_executed')::integer,0); v_pending:=v_pending+coalesce((v_r->>'pending_approval')::integer,0); perform public.phase7_measure_due(o.organization_id); exception when others then continue; end; end loop; return jsonb_build_object('evaluated',v_total,'auto_executed',v_auto,'pending_approval',v_pending); end $$;

revoke all on function public.phase7_seed_default_policies(uuid),public.phase7_set_policy(uuid,text,text,text,numeric,numeric,numeric,numeric),public.phase7_execute_run(uuid),public.phase7_orchestrate_opportunity(uuid),public.phase7_decide_action(uuid,text,text),public.phase7_command_center(uuid,integer),public.phase7_run_cycle(uuid,integer),public.phase7_measure_due(uuid),public.phase7_reverse_action(uuid,text),public.phase7_run_scheduled_cycles() from public,anon,authenticated;
grant execute on function public.phase7_seed_default_policies(uuid),public.phase7_set_policy(uuid,text,text,text,numeric,numeric,numeric,numeric),public.phase7_orchestrate_opportunity(uuid),public.phase7_decide_action(uuid,text,text),public.phase7_command_center(uuid,integer),public.phase7_run_cycle(uuid,integer),public.phase7_measure_due(uuid),public.phase7_reverse_action(uuid,text) to authenticated;
grant execute on function public.phase7_seed_default_policies(uuid),public.phase7_set_policy(uuid,text,text,text,numeric,numeric,numeric,numeric),public.phase7_execute_run(uuid),public.phase7_orchestrate_opportunity(uuid),public.phase7_decide_action(uuid,text,text),public.phase7_command_center(uuid,integer),public.phase7_run_cycle(uuid,integer),public.phase7_measure_due(uuid),public.phase7_reverse_action(uuid,text),public.phase7_run_scheduled_cycles() to service_role;

do $$ begin perform cron.schedule('phase7-autonomous-orchestration','*/15 * * * *','select public.phase7_run_scheduled_cycles();'); exception when others then if position('already exists' in lower(sqlerrm))=0 then raise; end if; end $$;

insert into public.platform_security_rpc_allowlist(function_signature,allow_anon,allow_authenticated,rationale,metadata,reviewed_at) values
('phase7_seed_default_policies(uuid)',false,true,'Phase 7 policy initialization; organization admin or service role.',jsonb_build_object('phase',7),now()),
('phase7_set_policy(uuid,text,text,text,numeric,numeric,numeric,numeric)',false,true,'Phase 7 policy management; organization admin only.',jsonb_build_object('phase',7),now()),
('phase7_orchestrate_opportunity(uuid)',false,true,'Phase 7 idempotent opportunity orchestration.',jsonb_build_object('phase',7),now()),
('phase7_decide_action(uuid,text,text)',false,true,'Phase 7 approval decision; organization admin only.',jsonb_build_object('phase',7),now()),
('phase7_command_center(uuid,integer)',false,true,'Phase 7 Command Center dashboard; organization admin only.',jsonb_build_object('phase',7),now()),
('phase7_run_cycle(uuid,integer)',false,true,'Phase 7 organization orchestration cycle.',jsonb_build_object('phase',7),now()),
('phase7_measure_due(uuid)',false,true,'Phase 7 governed outcome measurement.',jsonb_build_object('phase',7),now()),
('phase7_reverse_action(uuid,text)',false,true,'Phase 7 manager reversal control.',jsonb_build_object('phase',7),now())
on conflict(function_signature) do update set allow_anon=excluded.allow_anon,allow_authenticated=excluded.allow_authenticated,rationale=excluded.rationale,metadata=excluded.metadata,reviewed_at=now();
