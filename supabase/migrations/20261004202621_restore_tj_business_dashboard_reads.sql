-- Reviewed read-only Command Center and platform intelligence runtime.
CREATE FUNCTION tj_private.source_identity_for_session() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT tj_private.current_source_user_id(); $$;
REVOKE ALL ON FUNCTION tj_private.source_identity_for_session() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.source_identity_for_session() TO authenticated;

CREATE FUNCTION tj_private.get_org_member_profiles(p_org_id uuid)
RETURNS TABLE(user_id uuid,display_name text,email text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT m.user_id,coalesce(nullif(p.full_name,''),nullif(p.email,''),split_part(s.email,'@',1)),s.email
FROM tj.organization_members m JOIN tj.source_auth_users s ON s.id=m.user_id AND s.deleted_at IS NULL
LEFT JOIN tj.profiles p ON p.user_id=m.user_id
WHERE m.organization_id=p_org_id AND m.status='active' AND tj_private.is_org_member(p_org_id); $$;
CREATE FUNCTION tj.get_org_member_profiles(p_org_id uuid)
RETURNS TABLE(user_id uuid,display_name text,email text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT * FROM tj_private.get_org_member_profiles(p_org_id); $$;

CREATE FUNCTION tj_private.get_my_org_role(p_org_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT m.role FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id
WHERE m.organization_id=p_org_id AND m.user_id=tj_private.current_source_user_id()
AND m.status='active' AND o.deleted_at IS NULL LIMIT 1; $$;
CREATE FUNCTION tj.get_my_org_role(p_org_id uuid) RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.get_my_org_role(p_org_id); $$;

CREATE FUNCTION tj_private.intelligence_employee_names(p_organization_id uuid)
RETURNS TABLE(canonical_id uuid,display_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT i.canonical_id,max(i.display_name) FROM tj.platform_identity_links i
WHERE i.organization_id=p_organization_id AND i.entity_type='employee'
AND tj_private.is_org_member(p_organization_id) GROUP BY i.canonical_id; $$;
REVOKE ALL ON FUNCTION tj_private.get_org_member_profiles(uuid),tj_private.get_my_org_role(uuid),
tj_private.intelligence_employee_names(uuid),tj.get_org_member_profiles(uuid),tj.get_my_org_role(uuid)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.get_org_member_profiles(uuid),tj_private.get_my_org_role(uuid),
tj_private.intelligence_employee_names(uuid),tj.get_org_member_profiles(uuid),tj.get_my_org_role(uuid) TO authenticated;

DO $$ DECLARE t text; BEGIN
FOREACH t IN ARRAY ARRAY['ai_manager_briefs','ai_manager_assignments','ai_manager_escalations',
'ai_manager_task_comments','ai_manager_task_attachments','ai_manager_task_history','intelligence_events'] LOOP
EXECUTE format('ALTER TABLE tj.%I ENABLE ROW LEVEL SECURITY',t);
EXECUTE format('CREATE POLICY consolidation_business_read ON tj.%I FOR SELECT TO authenticated USING (organization_id IN (SELECT x.organization_id FROM tj.my_platform_organizations() x))',t);
EXECUTE format('GRANT SELECT ON tj.%I TO authenticated',t);
END LOOP;
END $$;
CREATE POLICY consolidation_intelligence_store_scope ON tj.intelligence_events AS RESTRICTIVE
FOR SELECT TO authenticated USING (tj.aiq_store_allows(organization_id,store_id));

CREATE FUNCTION tj.ai_manager_get_members(p_organization_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT CASE WHEN tj.is_org_member(p_organization_id) THEN
coalesce((SELECT jsonb_agg(jsonb_build_object('user_id',m.user_id,'role',m.role,'manager_id',m.manager_id,
'name',coalesce(p.display_name,p.email,m.user_id::text),'email',p.email) ORDER BY coalesce(p.display_name,p.email,m.user_id::text))
FROM tj.organization_members m LEFT JOIN tj.get_org_member_profiles(p_organization_id) p ON p.user_id=m.user_id
WHERE m.organization_id=p_organization_id AND m.status='active'),'[]'::jsonb)
ELSE jsonb_build_object('error','access_denied') END; $$;
REVOKE ALL ON FUNCTION tj.ai_manager_get_members(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.ai_manager_get_members(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.ai_manager_get_executive_briefs(p_organization_id uuid, p_limit integer DEFAULT 20, p_focus_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
  select case when tj.is_org_member(p_organization_id) then jsonb_build_object(
    'summary',jsonb_build_object(
      'latest_generated_at',(select max(generated_at) from tj.ai_manager_briefs where organization_id=p_organization_id),
      'draft_count',(select count(*) from tj.ai_manager_briefs where organization_id=p_organization_id and delivery_status='draft'),
      'delivered_count',(select count(*) from tj.ai_manager_briefs where organization_id=p_organization_id and delivery_status='delivered')
    ),
    'briefs',coalesce((select jsonb_agg(to_jsonb(b) order by b.generated_at desc)
      from (select * from tj.ai_manager_briefs where organization_id=p_organization_id and (p_focus_id is null or id=p_focus_id) order by generated_at desc limit greatest(1,least(p_limit,50))) b),'[]'::jsonb)
  ) else jsonb_build_object('error','organization_access_denied') end
$function$
;
REVOKE ALL ON FUNCTION tj.ai_manager_get_executive_briefs(uuid,integer,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.ai_manager_get_executive_briefs(uuid,integer,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION tj.ai_manager_get_my_work(p_organization_id uuid, p_scope text DEFAULT 'mine'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare uid uuid:=(select tj_private.source_identity_for_session());
begin
 if not tj.is_org_member(p_organization_id) then return jsonb_build_object('error','access_denied'); end if;
 return jsonb_build_object(
 'members',(select tj.ai_manager_get_members(p_organization_id)),
 'assignments',coalesce((select jsonb_agg(x order by (x->>'due_at') nulls last) from (select jsonb_build_object('id',a.id,'title',a.title,'instructions',a.instructions,'priority',a.priority,'status',a.status,'due_at',a.due_at,'assigned_to',a.assigned_to,'assigned_role',a.assigned_role,'assignee_name',coalesce(p.display_name,p.email,a.assigned_to::text),'approval_status',a.approval_status,'proof_required',a.proof_required,'completion_summary',a.completion_summary,'rejection_reason',a.rejection_reason,'escalation_level',a.escalation_level,'comments',(select count(*) from tj.ai_manager_task_comments c where c.assignment_id=a.id),'attachments',(select count(*) from tj.ai_manager_task_attachments f where f.assignment_id=a.id),'proofs',(select count(*) from tj.ai_manager_task_attachments f where f.assignment_id=a.id and f.attachment_type='proof')) x from tj.ai_manager_assignments a left join tj.get_org_member_profiles(p_organization_id) p on p.user_id=a.assigned_to where a.organization_id=p_organization_id and (p_scope='team' or a.assigned_to=uid or (a.assigned_to is null and a.assigned_role in (select m.role from tj.organization_members m where m.organization_id=p_organization_id and m.user_id=uid and m.status='active')))) s),'[]'::jsonb),
 'pending_approvals',(select count(*) from tj.ai_manager_assignments a where a.organization_id=p_organization_id and a.approval_status='pending'),
 'overdue',(select count(*) from tj.ai_manager_assignments a where a.organization_id=p_organization_id and a.status not in ('completed','cancelled') and a.due_at<now() and (p_scope='team' or a.assigned_to=uid))
 );
end$function$
;
REVOKE ALL ON FUNCTION tj.ai_manager_get_my_work(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.ai_manager_get_my_work(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION tj.ai_manager_get_task_detail(p_assignment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare a tj.ai_manager_assignments%rowtype;
begin
 select * into a from tj.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not tj.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 return jsonb_build_object('assignment',to_jsonb(a),'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'type',c.comment_type,'created_at',c.created_at,'author_name',coalesce(p.display_name,p.email,c.author_id::text)) order by c.created_at) from tj.ai_manager_task_comments c left join tj.get_org_member_profiles(a.organization_id) p on p.user_id=c.author_id where c.assignment_id=a.id),'[]'::jsonb),'attachments',coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at) from tj.ai_manager_task_attachments f where f.assignment_id=a.id),'[]'::jsonb),'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from tj.ai_manager_task_history h where h.assignment_id=a.id),'[]'::jsonb),'escalations',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from tj.ai_manager_escalations e where e.assignment_id=a.id),'[]'::jsonb));
end$function$
;
REVOKE ALL ON FUNCTION tj.ai_manager_get_task_detail(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.ai_manager_get_task_detail(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION tj.platform_intelligence_employee_rollup(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS TABLE(employee_id uuid, display_name text, interactions bigint, no_sales bigint, sales bigint, revenue numeric, conversion_pct numeric, avg_ticket numeric, learning_events bigint, coaching_reviews bigint)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
 with e as (
  select coalesce(canonical_event_type,event_type) et,entity_id,actor_id,payload from tj.intelligence_events
  where organization_id=p_organization_id and occurred_at>=coalesce(p_since,now()-interval '30 days') and actor_id is not null
 ), a as (
  select actor_id,
   count(distinct entity_id) filter(where et in ('interaction.started','interaction.completed','interaction.no_sale','interaction.updated')) interactions,
   count(distinct entity_id) filter(where et='interaction.no_sale') no_sales,
   count(distinct entity_id) filter(where et='transaction.completed') sales,
   coalesce(sum((payload->>'amount')::numeric) filter(where et='transaction.completed'),0) revenue,
   count(*) filter(where et like 'learning.%' or et='field.training_completed') learning_events,
   count(*) filter(where et='coaching.review_completed') coaching_reviews
  from e group by actor_id
 ), n as (
  select canonical_id,display_name from tj_private.intelligence_employee_names(p_organization_id)
 )
 select a.actor_id,coalesce(n.display_name,a.actor_id::text),a.interactions,a.no_sales,a.sales,a.revenue,
  case when a.interactions>0 then round((a.sales::numeric/a.interactions)*100,2) end,
  case when a.sales>0 then round(a.revenue/a.sales,2) end,a.learning_events,a.coaching_reviews
 from a left join n on n.canonical_id=a.actor_id
 where exists(select 1 from tj.organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.source_identity_for_session() and m.status='active')
 order by a.revenue desc nulls last;
$function$
;
REVOKE ALL ON FUNCTION tj.platform_intelligence_employee_rollup(uuid,timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.platform_intelligence_employee_rollup(uuid,timestamp with time zone) TO authenticated;

CREATE OR REPLACE FUNCTION tj.platform_intelligence_feed(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval), p_limit integer DEFAULT 200, p_event_types text[] DEFAULT NULL::text[])
 RETURNS TABLE(id uuid, event_type text, subject_entity_type text, entity_id uuid, store_id uuid, actor_id uuid, source_system text, source_record_id text, payload jsonb, occurred_at timestamp with time zone, correlation_id uuid, identity_confidence numeric, metadata jsonb)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
 select e.id,coalesce(e.canonical_event_type,e.event_type),e.subject_entity_type,e.entity_id,e.store_id,e.actor_id,e.source_system,e.source_record_id,e.payload,e.occurred_at,e.correlation_id,e.identity_confidence,e.metadata from tj.intelligence_events e
 where e.organization_id=p_organization_id and e.occurred_at>=coalesce(p_since,now()-interval '30 days') and (p_event_types is null or coalesce(e.canonical_event_type,e.event_type)=any(p_event_types)) and exists(select 1 from tj.organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.source_identity_for_session() and m.status='active') order by e.occurred_at desc limit least(greatest(coalesce(p_limit,200),1),1000);
$function$
;
REVOKE ALL ON FUNCTION tj.platform_intelligence_feed(uuid,timestamp with time zone,integer,text[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.platform_intelligence_feed(uuid,timestamp with time zone,integer,text[]) TO authenticated;

CREATE OR REPLACE FUNCTION tj.platform_intelligence_store_rollup(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS TABLE(store_id uuid, store_name text, traffic_groups numeric, interactions bigint, no_sales bigint, sales bigint, revenue numeric, refunds bigint, refund_amount numeric, conversion_pct numeric, avg_ticket numeric, field_score numeric)
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
 with e as (
  select coalesce(canonical_event_type,event_type) et,entity_id,store_id,payload from tj.intelligence_events
  where organization_id=p_organization_id and occurred_at>=coalesce(p_since,now()-interval '30 days')
 ), a as (
  select store_id,
   coalesce(sum((payload->>'customer_groups')::numeric) filter(where et='traffic.observed'),0) traffic_groups,
   count(distinct entity_id) filter(where et in ('interaction.started','interaction.completed','interaction.no_sale','interaction.updated')) interactions,
   count(distinct entity_id) filter(where et='interaction.no_sale') no_sales,
   count(distinct entity_id) filter(where et='transaction.completed') sales,
   coalesce(sum((payload->>'amount')::numeric) filter(where et='transaction.completed'),0) revenue,
   count(distinct entity_id) filter(where et='transaction.refunded') refunds,
   coalesce(sum(abs((payload->>'amount')::numeric)) filter(where et='transaction.refunded'),0) refund_amount,
   round(avg((payload->>'overall_score')::numeric) filter(where et='field.score_recorded'),2) field_score
  from e where store_id is not null group by store_id
 )
 select a.store_id,l.name,a.traffic_groups,a.interactions,a.no_sales,a.sales,a.revenue,a.refunds,a.refund_amount,
  case when a.traffic_groups>0 then round((a.sales::numeric/a.traffic_groups)*100,2) end,
  case when a.sales>0 then round(a.revenue/a.sales,2) end,a.field_score
 from a left join tj.org_locations l on l.id=a.store_id
 where exists(select 1 from tj.organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.source_identity_for_session() and m.status='active')
 order by a.revenue desc nulls last;
$function$
;
REVOKE ALL ON FUNCTION tj.platform_intelligence_store_rollup(uuid,timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.platform_intelligence_store_rollup(uuid,timestamp with time zone) TO authenticated;

CREATE OR REPLACE FUNCTION tj.platform_intelligence_summary(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval))
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
 with e as (select coalesce(canonical_event_type,event_type) et,payload from tj.intelligence_events where organization_id=p_organization_id and occurred_at>=coalesce(p_since,now()-interval '30 days'))
 select case when exists(select 1 from tj.organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.source_identity_for_session() and m.status='active') then jsonb_build_object('since',p_since,'events',count(*),'sales',count(*) filter(where et='transaction.completed'),'refunds',count(*) filter(where et='transaction.refunded'),'traffic_groups',coalesce(sum((payload->>'customer_groups')::numeric) filter(where et='traffic.observed'),0),'interactions',count(*) filter(where et like 'interaction.%'),'no_sales',count(*) filter(where et='interaction.no_sale'),'learning_events',count(*) filter(where et like 'learning.%' or et='field.training_completed'),'field_scores',count(*) filter(where et='field.score_recorded'),'revenue',coalesce(sum((payload->>'amount')::numeric) filter(where et='transaction.completed'),0),'refund_amount',coalesce(sum(abs((payload->>'amount')::numeric)) filter(where et='transaction.refunded'),0),'recommendations',count(*) filter(where et='recommendation.generated'),'deals_won',count(*) filter(where et='deal.won'),'coaching_reviews',count(*) filter(where et='coaching.review_completed'),'avg_field_score',round(avg((payload->>'overall_score')::numeric) filter(where et='field.score_recorded'),2)) else '{}'::jsonb end from e;
$function$
;
REVOKE ALL ON FUNCTION tj.platform_intelligence_summary(uuid,timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.platform_intelligence_summary(uuid,timestamp with time zone) TO authenticated;

CREATE OR REPLACE FUNCTION tj.ai_manager_get_dashboard(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare v_result jsonb;
begin
 if not tj.is_org_member(p_organization_id) then raise exception 'not_authorized'; end if;
 select jsonb_build_object(
  'brief',(select to_jsonb(b) from tj.ai_manager_briefs b where b.organization_id=p_organization_id order by b.brief_date desc,b.generated_at desc limit 1),
  'summary',jsonb_build_object(
    'open',(select count(*) from tj.ai_manager_assignments where organization_id=p_organization_id and status in ('open','accepted','in_progress')),
    'blocked',(select count(*) from tj.ai_manager_assignments where organization_id=p_organization_id and status='blocked'),
    'overdue',(select count(*) from tj.ai_manager_assignments where organization_id=p_organization_id and status not in ('completed','cancelled') and due_at<now()),
    'completed_7d',(select count(*) from tj.ai_manager_assignments where organization_id=p_organization_id and status='completed' and completed_at>=now()-interval '7 days'),
    'open_escalations',(select count(*) from tj.ai_manager_escalations where organization_id=p_organization_id and status='open')
  ),
  'assignments',(select coalesce(jsonb_agg(to_jsonb(a) order by case a.priority when 'critical' then 4 when 'high' then 3 when 'medium' then 2 else 1 end desc,a.due_at asc),'[]'::jsonb) from tj.ai_manager_assignments a where a.organization_id=p_organization_id and a.status not in ('completed','cancelled')),
  'recent_completed',(select coalesce(jsonb_agg(to_jsonb(a) order by a.completed_at desc),'[]'::jsonb) from (select * from tj.ai_manager_assignments where organization_id=p_organization_id and status='completed' order by completed_at desc limit 10) a),
  'escalations',(select coalesce(jsonb_agg(to_jsonb(e) order by e.level desc,e.created_at desc),'[]'::jsonb) from tj.ai_manager_escalations e where e.organization_id=p_organization_id and e.status='open')
 ) into v_result;
 return v_result;
end $function$
;
REVOKE ALL ON FUNCTION tj.ai_manager_get_dashboard(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.ai_manager_get_dashboard(uuid) TO authenticated;

NOTIFY pgrst,'reload schema';
