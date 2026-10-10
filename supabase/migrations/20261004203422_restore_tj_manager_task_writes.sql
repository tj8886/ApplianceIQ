-- Guarded task/brief writes; no direct table write grants or external delivery.
CREATE OR REPLACE FUNCTION tj.decision_calculate_priority(p_financial_impact_cad numeric, p_customer_impact_score numeric, p_urgency_score numeric, p_confidence numeric, p_evidence_quality numeric, p_effort_score numeric)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
  select round(least(100,greatest(0,
    (least(coalesce(p_financial_impact_cad,0),250000)/250000.0*30) +
    (coalesce(p_customer_impact_score,0)*0.20) +
    (coalesce(p_urgency_score,0)*0.20) +
    (coalesce(p_confidence,0.5)*100*0.15) +
    (coalesce(p_evidence_quality,0.5)*100*0.10) +
    ((100-coalesce(p_effort_score,50))*0.05)
  )),2);
$function$
;
CREATE OR REPLACE FUNCTION tj.decision_touch_case()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
begin
  new.priority_score := tj.decision_calculate_priority(new.financial_impact_cad,new.customer_impact_score,new.urgency_score,new.confidence,new.evidence_quality,new.effort_score);
  new.updated_at := now();
  if new.status in ('completed','dismissed','rejected','expired') and new.resolved_at is null then new.resolved_at:=now(); end if;
  return new;
end $function$
;
REVOKE ALL ON FUNCTION tj.decision_calculate_priority(numeric,numeric,numeric,numeric,numeric,numeric),tj.decision_touch_case() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.decision_calculate_priority(numeric,numeric,numeric,numeric,numeric,numeric) TO authenticated;
CREATE TRIGGER decision_cases_touch BEFORE INSERT OR UPDATE ON tj.decision_cases FOR EACH ROW EXECUTE FUNCTION tj.decision_touch_case();
CREATE OR REPLACE FUNCTION tj_private.ai_manager_mark_brief_delivered(p_brief_id uuid, p_channels jsonb DEFAULT '["in_app"]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row tj.ai_manager_briefs;
begin
  select * into v_row from tj.ai_manager_briefs where id=p_brief_id for update;
  if v_row.id is null or not exists(select 1 from tj_private.my_platform_organizations() o where o.organization_id=v_row.organization_id) then raise exception 'brief_access_denied'; end if;
  update tj.ai_manager_briefs set delivery_status='delivered',delivery_channels=coalesce(p_channels,'[]'::jsonb),delivered_at=now() where id=p_brief_id returning * into v_row;
  return to_jsonb(v_row);
end $function$
;
CREATE OR REPLACE FUNCTION tj_private.ai_manager_update_assignment(p_assignment_id uuid, p_status text, p_blocked_reason text DEFAULT NULL::text, p_assigned_to uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v tj.ai_manager_assignments;
begin
 select * into v from tj.ai_manager_assignments where id=p_assignment_id for update;
 if v.id is null or not exists(select 1 from tj_private.my_platform_organizations() o where o.organization_id=v.organization_id) then raise exception 'not_authorized'; end if;
 if p_status is null or p_status not in ('open','accepted','in_progress','blocked','completed','cancelled') then raise exception 'invalid_status'; end if;
 if p_assigned_to is not null and not exists(select 1 from tj.organization_members m where m.organization_id=v.organization_id and m.user_id=p_assigned_to and m.status='active') then raise exception 'assignee_not_in_organization'; end if;
 update tj.ai_manager_assignments set status=p_status,blocked_reason=case when p_status='blocked' then p_blocked_reason else null end,assigned_to=coalesce(p_assigned_to,assigned_to),due_at=coalesce(p_due_at,due_at),accepted_at=case when p_status='accepted' and accepted_at is null then now() else accepted_at end,started_at=case when p_status='in_progress' and started_at is null then now() else started_at end,completed_at=case when p_status='completed' then now() else completed_at end,updated_at=now() where id=p_assignment_id returning * into v;
 if p_status='completed' then
   update tj.decision_cases set status='completed',resolved_at=now(),updated_at=now() where id=v.decision_case_id and organization_id=v.organization_id;
   update tj.ai_manager_escalations set status='resolved',resolved_at=now() where assignment_id=v.id and organization_id=v.organization_id and status='open';
 end if;
 return to_jsonb(v);
end $function$
;
CREATE OR REPLACE FUNCTION tj_private.ai_manager_assign_task(p_assignment_id uuid, p_assigned_to uuid DEFAULT NULL::uuid, p_assigned_role text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a tj.ai_manager_assignments%rowtype; old_owner uuid;
begin
 select * into a from tj.ai_manager_assignments where id=p_assignment_id for update;
 if a.id is null or not exists(select 1 from tj_private.my_platform_organizations() o where o.organization_id=a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 if p_assigned_to is not null and not exists(select 1 from tj.organization_members m where m.organization_id=a.organization_id and m.user_id=p_assigned_to and m.status='active') then return jsonb_build_object('error','assignee_not_in_organization'); end if;
 old_owner:=a.assigned_to;
 update tj.ai_manager_assignments set assigned_to=p_assigned_to,assigned_role=nullif(trim(p_assigned_role),''),assigned_by=(select tj_private.current_source_user_id()),due_at=coalesce(p_due_at,due_at),updated_at=now() where id=a.id;
 insert into tj.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,from_value,to_value,metadata) values(a.organization_id,a.id,(select tj_private.current_source_user_id()),case when old_owner is null then 'assigned' else 'reassigned' end,old_owner::text,p_assigned_to::text,jsonb_build_object('assigned_role',p_assigned_role,'due_at',p_due_at));
 return jsonb_build_object('ok',true);
end$function$
;

CREATE FUNCTION tj.ai_manager_assign_task(p_assignment_id uuid,p_assigned_to uuid DEFAULT NULL,p_assigned_role text DEFAULT NULL,p_due_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.ai_manager_assign_task(p_assignment_id,p_assigned_to,p_assigned_role,p_due_at); $$;
CREATE FUNCTION tj.ai_manager_update_assignment(p_assignment_id uuid,p_status text,p_blocked_reason text DEFAULT NULL,p_assigned_to uuid DEFAULT NULL,p_due_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.ai_manager_update_assignment(p_assignment_id,p_status,p_blocked_reason,p_assigned_to,p_due_at); $$;
CREATE FUNCTION tj.ai_manager_mark_brief_delivered(p_brief_id uuid,p_channels jsonb DEFAULT '["in_app"]')
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.ai_manager_mark_brief_delivered(p_brief_id,p_channels); $$;
DO $$ DECLARE s text; sig text; BEGIN
FOREACH s IN ARRAY ARRAY['tj','tj_private'] LOOP
FOREACH sig IN ARRAY ARRAY['ai_manager_assign_task(uuid,uuid,text,timestamptz)',
'ai_manager_update_assignment(uuid,text,text,uuid,timestamptz)','ai_manager_mark_brief_delivered(uuid,jsonb)'] LOOP
EXECUTE 'REVOKE ALL ON FUNCTION '||s||'.'||sig||' FROM PUBLIC,anon,authenticated';
EXECUTE 'GRANT EXECUTE ON FUNCTION '||s||'.'||sig||' TO authenticated';
END LOOP; END LOOP;
END $$;
NOTIFY pgrst,'reload schema';
