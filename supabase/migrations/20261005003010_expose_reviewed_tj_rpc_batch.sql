-- Reviewed runtime aliases. No owner elevation and no raw table exposure.
CREATE FUNCTION public.tj_runtime_ai_manager_assign_task(p_assignment_id uuid, p_assigned_to uuid DEFAULT NULL::uuid, p_assigned_role text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_assign_task("p_assignment_id","p_assigned_to","p_assigned_role","p_due_at"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_assign_task(p_assignment_id uuid, p_assigned_to uuid, p_assigned_role text, p_due_at timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_assign_task(p_assignment_id uuid, p_assigned_to uuid, p_assigned_role text, p_due_at timestamp with time zone) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_get_dashboard(p_organization_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_get_dashboard("p_organization_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_get_dashboard(p_organization_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_get_dashboard(p_organization_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_get_executive_briefs(p_organization_id uuid, p_limit integer DEFAULT 20, p_focus_id uuid DEFAULT NULL::uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_get_executive_briefs("p_organization_id","p_limit","p_focus_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_get_executive_briefs(p_organization_id uuid, p_limit integer, p_focus_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_get_executive_briefs(p_organization_id uuid, p_limit integer, p_focus_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_get_members(p_organization_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_get_members("p_organization_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_get_members(p_organization_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_get_members(p_organization_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_get_my_work(p_organization_id uuid, p_scope text DEFAULT 'mine'::text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_get_my_work("p_organization_id","p_scope"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_get_my_work(p_organization_id uuid, p_scope text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_get_my_work(p_organization_id uuid, p_scope text) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_get_task_detail(p_assignment_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_get_task_detail("p_assignment_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_get_task_detail(p_assignment_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_get_task_detail(p_assignment_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_mark_brief_delivered(p_brief_id uuid, p_channels jsonb DEFAULT '["in_app"]'::jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_mark_brief_delivered("p_brief_id","p_channels"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_mark_brief_delivered(p_brief_id uuid, p_channels jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_mark_brief_delivered(p_brief_id uuid, p_channels jsonb) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_register_attachment(p_assignment_id uuid, p_storage_path text, p_file_name text, p_mime_type text, p_file_size_bytes bigint, p_attachment_type text DEFAULT 'supporting'::text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_register_attachment("p_assignment_id","p_storage_path","p_file_name","p_mime_type","p_file_size_bytes","p_attachment_type"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_register_attachment(p_assignment_id uuid, p_storage_path text, p_file_name text, p_mime_type text, p_file_size_bytes bigint, p_attachment_type text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_register_attachment(p_assignment_id uuid, p_storage_path text, p_file_name text, p_mime_type text, p_file_size_bytes bigint, p_attachment_type text) TO authenticated;

CREATE FUNCTION public.tj_runtime_ai_manager_update_assignment(p_assignment_id uuid, p_status text, p_blocked_reason text DEFAULT NULL::text, p_assigned_to uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.ai_manager_update_assignment("p_assignment_id","p_status","p_blocked_reason","p_assigned_to","p_due_at"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_update_assignment(p_assignment_id uuid, p_status text, p_blocked_reason text, p_assigned_to uuid, p_due_at timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_update_assignment(p_assignment_id uuid, p_status text, p_blocked_reason text, p_assigned_to uuid, p_due_at timestamp with time zone) TO authenticated;

CREATE FUNCTION public.tj_runtime_compute_iq_score(p_org_id uuid, p_period text DEFAULT '2026-06'::text, p_location_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid) RETURNS TABLE(metric_key text, metric_label text, max_points numeric, actual_value numeric, target_value numeric, pct_of_target numeric, earned_points numeric, sort_order integer)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.compute_iq_score("p_org_id","p_period","p_location_id","p_user_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_compute_iq_score(p_org_id uuid, p_period text, p_location_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_compute_iq_score(p_org_id uuid, p_period text, p_location_id uuid, p_user_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_crm_reassign_rep_deals(p_org_id uuid, p_from_user_id uuid, p_to_user_id uuid, p_reason text DEFAULT 'rep_deactivated'::text, p_actor_id uuid DEFAULT NULL::uuid) RETURNS integer
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.crm_reassign_rep_deals("p_org_id","p_from_user_id","p_to_user_id","p_reason","p_actor_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_crm_reassign_rep_deals(p_org_id uuid, p_from_user_id uuid, p_to_user_id uuid, p_reason text, p_actor_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_crm_reassign_rep_deals(p_org_id uuid, p_from_user_id uuid, p_to_user_id uuid, p_reason text, p_actor_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_decision_get_feed(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.decision_get_feed("p_organization_id","p_limit"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_decision_get_feed(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_decision_get_feed(p_organization_id uuid, p_limit integer) TO authenticated;

CREATE FUNCTION public.tj_runtime_decision_get_prediction_dashboard(p_organization_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.decision_get_prediction_dashboard("p_organization_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_decision_get_prediction_dashboard(p_organization_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_decision_get_prediction_dashboard(p_organization_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_decision_record_prediction_outcome(p_prediction_id uuid, p_actual_value numeric, p_actual_financial_impact_cad numeric DEFAULT NULL::numeric) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.decision_record_prediction_outcome("p_prediction_id","p_actual_value","p_actual_financial_impact_cad"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_decision_record_prediction_outcome(p_prediction_id uuid, p_actual_value numeric, p_actual_financial_impact_cad numeric) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_decision_record_prediction_outcome(p_prediction_id uuid, p_actual_value numeric, p_actual_financial_impact_cad numeric) TO authenticated;

CREATE FUNCTION public.tj_runtime_decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome_success boolean DEFAULT NULL::boolean, p_outcome_value numeric DEFAULT NULL::numeric, p_outcome_unit text DEFAULT NULL::text, p_outcome_notes text DEFAULT NULL::text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.decision_update_action("p_action_id","p_status","p_owner_id","p_due_at","p_outcome_success","p_outcome_value","p_outcome_unit","p_outcome_notes"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid, p_due_at timestamp with time zone, p_outcome_success boolean, p_outcome_value numeric, p_outcome_unit text, p_outcome_notes text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid, p_due_at timestamp with time zone, p_outcome_success boolean, p_outcome_value numeric, p_outcome_unit text, p_outcome_notes text) TO authenticated;

CREATE FUNCTION public.tj_runtime_executive_get_command_centre(p_organization_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.executive_get_command_centre("p_organization_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_executive_get_command_centre(p_organization_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_executive_get_command_centre(p_organization_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_find_duplicate_contacts(p_org_id uuid) RETURNS TABLE(contact_id_1 uuid, contact_id_2 uuid, match_type text, match_value text)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.find_duplicate_contacts("p_org_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_find_duplicate_contacts(p_org_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_find_duplicate_contacts(p_org_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_get_anniversary_outreach(p_org_id uuid, p_days_ahead integer DEFAULT 14) RETURNS TABLE(deal_id uuid, contact_id uuid, contact_name text, contact_email text, deal_title text, purchase_date date, anniversary_number integer, days_until integer)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.get_anniversary_outreach("p_org_id","p_days_ahead"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_get_anniversary_outreach(p_org_id uuid, p_days_ahead integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_anniversary_outreach(p_org_id uuid, p_days_ahead integer) TO authenticated;

CREATE FUNCTION public.tj_runtime_get_floor_by_store(p_org_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.get_floor_by_store("p_org_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_get_floor_by_store(p_org_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_floor_by_store(p_org_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_get_floor_gaps(p_org_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.get_floor_gaps("p_org_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_get_floor_gaps(p_org_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_floor_gaps(p_org_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_get_floor_holes(p_org_id uuid, p_store_id uuid DEFAULT NULL::uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.get_floor_holes("p_org_id","p_store_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_get_floor_holes(p_org_id uuid, p_store_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_floor_holes(p_org_id uuid, p_store_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_get_floor_vs_sales(p_org_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.get_floor_vs_sales("p_org_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_get_floor_vs_sales(p_org_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_floor_vs_sales(p_org_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_get_my_org_role(p_org_id uuid) RETURNS text
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.get_my_org_role("p_org_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_get_my_org_role(p_org_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_my_org_role(p_org_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_get_org_member_profiles(p_org_id uuid) RETURNS TABLE(user_id uuid, display_name text, email text)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.get_org_member_profiles("p_org_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_get_org_member_profiles(p_org_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_get_org_member_profiles(p_org_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_my_entitled_apps() RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.my_entitled_apps(); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_my_entitled_apps() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_my_entitled_apps() TO authenticated;

CREATE FUNCTION public.tj_runtime_my_platform_context() RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.my_platform_context(); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_my_platform_context() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_my_platform_context() TO authenticated;

CREATE FUNCTION public.tj_runtime_my_platform_locations(p_organization_id uuid) RETURNS TABLE(location_id uuid, location_name text, location_code text, location_type text)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.my_platform_locations("p_organization_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_my_platform_locations(p_organization_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_my_platform_locations(p_organization_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_my_platform_organizations() RETURNS TABLE(organization_id uuid, organization_name text, role text)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.my_platform_organizations(); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_my_platform_organizations() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_my_platform_organizations() TO authenticated;

CREATE FUNCTION public.tj_runtime_performance_get_next_scenario(p_organization_id uuid, p_user_id uuid DEFAULT NULL::uuid) RETURNS TABLE(scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, target_competency_name text, target_score numeric, reason text, persona text, context text, objectives jsonb, competency_weights jsonb, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.performance_get_next_scenario("p_organization_id","p_user_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_performance_get_next_scenario(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_performance_get_next_scenario(p_organization_id uuid, p_user_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text DEFAULT 'you_sell'::text) RETURNS TABLE(roleplay_session_id uuid, scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, reason text, persona text, context text, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.performance_start_adaptive_roleplay("p_organization_id","p_mode"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase4_coaching_dashboard(p_organization_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase4_coaching_dashboard("p_organization_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase4_coaching_dashboard(p_organization_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase4_coaching_dashboard(p_organization_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid DEFAULT NULL::uuid, p_score numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase4_complete_step("p_intervention_id","p_step_order","p_completion_ref","p_score","p_metadata"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid, p_score numeric, p_metadata jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid, p_score numeric, p_metadata jsonb) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase4_evaluate_due_org(p_organization_id uuid, p_limit integer DEFAULT 100) RETURNS TABLE(intervention_id uuid, result jsonb)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.phase4_evaluate_due_org("p_organization_id","p_limit"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean DEFAULT false) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase4_evaluate_intervention("p_intervention_id","p_force"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase4_generate_coaching("p_organization_id","p_user_id","p_focus_date"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25) RETURNS TABLE(user_id uuid, intervention_id uuid)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.phase4_generate_org_coaching("p_organization_id","p_focus_date","p_limit"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase5_generate_adaptive_coaching("p_organization_id","p_user_id","p_focus_date"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25) RETURNS TABLE(user_id uuid, intervention_id uuid, adaptation jsonb)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.phase5_generate_org_adaptive_coaching("p_organization_id","p_focus_date","p_limit"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase5_manager_dashboard(p_organization_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase5_manager_dashboard("p_organization_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase5_manager_dashboard(p_organization_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase5_manager_dashboard(p_organization_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase5_manager_recommendations(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase5_manager_recommendations("p_organization_id","p_limit"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase5_manager_recommendations(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase5_manager_recommendations(p_organization_id uuid, p_limit integer) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase5_refresh_profile(p_organization_id uuid, p_user_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase5_refresh_profile("p_organization_id","p_user_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase5_refresh_profile(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase5_refresh_profile(p_organization_id uuid, p_user_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase5_rep_plan(p_organization_id uuid, p_user_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase5_rep_plan("p_organization_id","p_user_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase5_rep_plan(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase5_rep_plan(p_organization_id uuid, p_user_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid DEFAULT NULL::uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.phase5_select_strategy("p_organization_id","p_user_id","p_metric_key","p_skill_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_platform_global_search(p_query text, p_limit integer DEFAULT 30) RETURNS TABLE(entity_type text, entity_id text, entity_label text, subtitle text, module_key text, organization_id uuid, location_id uuid, rank integer)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.platform_global_search("p_query","p_limit"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_platform_global_search(p_query text, p_limit integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_platform_global_search(p_query text, p_limit integer) TO authenticated;

CREATE FUNCTION public.tj_runtime_platform_intelligence_employee_rollup(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval)) RETURNS TABLE(employee_id uuid, display_name text, interactions bigint, no_sales bigint, sales bigint, revenue numeric, conversion_pct numeric, avg_ticket numeric, learning_events bigint, coaching_reviews bigint)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.platform_intelligence_employee_rollup("p_organization_id","p_since"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_platform_intelligence_employee_rollup(p_organization_id uuid, p_since timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_platform_intelligence_employee_rollup(p_organization_id uuid, p_since timestamp with time zone) TO authenticated;

CREATE FUNCTION public.tj_runtime_platform_intelligence_feed(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval), p_limit integer DEFAULT 200, p_event_types text[] DEFAULT NULL::text[]) RETURNS TABLE(id uuid, event_type text, subject_entity_type text, entity_id uuid, store_id uuid, actor_id uuid, source_system text, source_record_id text, payload jsonb, occurred_at timestamp with time zone, correlation_id uuid, identity_confidence numeric, metadata jsonb)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.platform_intelligence_feed("p_organization_id","p_since","p_limit","p_event_types"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_platform_intelligence_feed(p_organization_id uuid, p_since timestamp with time zone, p_limit integer, p_event_types text[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_platform_intelligence_feed(p_organization_id uuid, p_since timestamp with time zone, p_limit integer, p_event_types text[]) TO authenticated;

CREATE FUNCTION public.tj_runtime_platform_intelligence_store_rollup(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval)) RETURNS TABLE(store_id uuid, store_name text, traffic_groups numeric, interactions bigint, no_sales bigint, sales bigint, revenue numeric, refunds bigint, refund_amount numeric, conversion_pct numeric, avg_ticket numeric, field_score numeric)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.platform_intelligence_store_rollup("p_organization_id","p_since"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_platform_intelligence_store_rollup(p_organization_id uuid, p_since timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_platform_intelligence_store_rollup(p_organization_id uuid, p_since timestamp with time zone) TO authenticated;

CREATE FUNCTION public.tj_runtime_platform_intelligence_summary(p_organization_id uuid, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval)) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.platform_intelligence_summary("p_organization_id","p_since"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_platform_intelligence_summary(p_organization_id uuid, p_since timestamp with time zone) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_platform_intelligence_summary(p_organization_id uuid, p_since timestamp with time zone) TO authenticated;

CREATE FUNCTION public.tj_runtime_platform_mark_notification_read(p_notification_id uuid) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.platform_mark_notification_read("p_notification_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_platform_mark_notification_read(p_notification_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_platform_mark_notification_read(p_notification_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text DEFAULT NULL::text, p_external_id text DEFAULT NULL::text, p_source_record_id text DEFAULT NULL::text) RETURNS TABLE(canonical_id uuid, canonical_table text, display_name text, confidence numeric, match_method text, source_system text, source_table text, source_record_id text, external_id text)
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj.platform_resolve_identity("p_organization_id","p_entity_type","p_source_system","p_external_id","p_source_record_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) TO authenticated;

CREATE FUNCTION public.tj_runtime_score_leads(p_org_id uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.score_leads("p_org_id"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_score_leads(p_org_id uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_score_leads(p_org_id uuid) TO authenticated;

CREATE FUNCTION public.tj_runtime_set_platform_context(p_organization_id uuid DEFAULT NULL::uuid, p_location_id uuid DEFAULT NULL::uuid, p_entity_type text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_entity_label text DEFAULT NULL::text, p_source_module_key text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj.set_platform_context("p_organization_id","p_location_id","p_entity_type","p_entity_id","p_entity_label","p_source_module_key","p_context"); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_set_platform_context(p_organization_id uuid, p_location_id uuid, p_entity_type text, p_entity_id text, p_entity_label text, p_source_module_key text, p_context jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.tj_runtime_set_platform_context(p_organization_id uuid, p_location_id uuid, p_entity_type text, p_entity_id text, p_entity_label text, p_source_module_key text, p_context jsonb) TO authenticated;

NOTIFY pgrst,'reload schema';
