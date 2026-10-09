// Install on a US East client after app cutover. Auth/storage remain on that client.
const REVIEWED = new Set(["accept_org_invite", "ai_manager_assign_task", "ai_manager_generate_executive_brief", "ai_manager_get_dashboard", "ai_manager_get_executive_briefs", "ai_manager_get_members", "ai_manager_get_my_work", "ai_manager_get_task_detail", "ai_manager_mark_brief_delivered", "ai_manager_register_attachment", "ai_manager_run_cycle", "ai_manager_update_assignment", "ai_submit_request", "check_app_access", "compute_iq_score", "create_org_invite", "crm_reassign_rep_deals", "decision_generate_operational_forecasts", "decision_get_feed", "decision_get_prediction_dashboard", "decision_record_prediction_outcome", "decision_sync_executive_insights", "decision_update_action", "evaluate_sla_rules", "executive_answer_question", "executive_get_command_centre", "executive_refresh_command_centre", "find_duplicate_contacts", "get_anniversary_outreach", "get_floor_by_store", "get_floor_gaps", "get_floor_holes", "get_floor_vs_sales", "get_invite_preview", "get_my_org_role", "get_org_member_profiles", "manufacturer_invites", "my_entitled_apps", "my_platform_context", "my_platform_locations", "my_platform_organizations", "performance_get_next_scenario", "performance_start_adaptive_roleplay", "phase4_coaching_dashboard", "phase4_complete_step", "phase4_evaluate_due_org", "phase4_evaluate_intervention", "phase4_generate_coaching", "phase4_generate_org_coaching", "phase5_generate_adaptive_coaching", "phase5_generate_org_adaptive_coaching", "phase5_manager_dashboard", "phase5_manager_recommendations", "phase5_refresh_profile", "phase5_rep_plan", "phase5_select_strategy", "platform_global_search", "platform_intelligence_employee_rollup", "platform_intelligence_feed", "platform_intelligence_store_rollup", "platform_intelligence_summary", "platform_mark_notification_read", "platform_resolve_identity", "revoke_org_invite", "score_leads", "set_platform_context", "speciq_add_comparison_winner"]);
export function installUsRuntimeRpc(client) {
  if (client.supabaseUrl?.replace(/\/$/, '') !== 'https://jdxslqmgjsuzoisuhvlc.supabase.co') {
    throw new Error('US runtime routing requires the US East client');
  }
  const originalRpc = client.rpc.bind(client);
  client.rpc = (name, args, options) => {
    if (!REVIEWED.has(name)) return Promise.resolve({ data: null, error: {
      code: 'MIGRATION_RPC_NOT_READY', message: 'This workflow is not yet available on US East.',
    } });
    return originalRpc(`tj_runtime_${name}`, args, options);
  };
  return client;
}
export const reviewedRuntimeFunctions = Object.freeze([...REVIEWED]);
