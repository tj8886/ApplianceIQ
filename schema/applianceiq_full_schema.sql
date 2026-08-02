-- ============================================================
-- ApplianceIQ Intelligence Group — Full Schema Backup
-- Generated: 2026-08-02T15:39:53.723Z
-- Supabase Project: fumwwhyozeouoqscolke (ca-central-1)
-- Tables: 340 | RLS Policies: 638 | Functions: 148 | Triggers: 156 | Indexes: 584
-- Purpose: Complete reproducible schema for disaster recovery
-- ============================================================

-- =========================
-- SEQUENCES
-- =========================


CREATE SEQUENCE IF NOT EXISTS public.academy_chapters_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.academy_volumes_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.foundation_audit_log_id_seq AS bigint INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.iq_badges_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.iq_cards_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.iq_courses_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.iq_decks_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.iq_gates_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.iq_lanes_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.iq_zones_id_seq AS integer INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.privacy_purge_log_id_seq AS bigint INCREMENT BY 1 MINVALUE 1 START WITH 1;

CREATE SEQUENCE IF NOT EXISTS public.speciq_quote_seq AS bigint INCREMENT BY 1 MINVALUE 1 START WITH 1000;

-- =========================
-- TABLES: academy_*
-- =========================

CREATE TABLE IF NOT EXISTS public.academy_api_keys (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  label text NOT NULL,
  key_hash text NOT NULL,
  firm_id uuid,
  scopes _text[] NOT NULL DEFAULT ARRAY['metrics:write'::text],
  active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  last_used_at timestamp with time zone,
  CONSTRAINT academy_api_keys_firm_id_fkey FOREIGN KEY (firm_id) REFERENCES academy_firms(id) ON DELETE CASCADE,
  CONSTRAINT academy_api_keys_pkey PRIMARY KEY (id),
  CONSTRAINT academy_api_keys_key_hash_key UNIQUE (key_hash)
);

CREATE TABLE IF NOT EXISTS public.academy_brand_certifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  brand_id uuid NOT NULL,
  tier text NOT NULL,
  awarded_at timestamp with time zone DEFAULT now(),
  expires_at timestamp with time zone,
  cert_number text DEFAULT ('BRD-'::text || upper(substr((gen_random_uuid())::text, 1, 8))),
  CONSTRAINT academy_brand_certifications_tier_check CHECK ((tier = ANY (ARRAY['bronze'::text, 'silver'::text, 'gold'::text, 'expert'::text, 'master'::text, 'elite'::text]))),
  CONSTRAINT academy_brand_certifications_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT academy_brand_certifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_brand_certifications_pkey PRIMARY KEY (id),
  CONSTRAINT academy_brand_certifications_cert_number_key UNIQUE (cert_number),
  CONSTRAINT academy_brand_certifications_user_id_brand_id_tier_key UNIQUE (user_id, brand_id, tier)
);

CREATE TABLE IF NOT EXISTS public.academy_brand_progress (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  brand_id uuid NOT NULL,
  level smallint NOT NULL,
  module_key text NOT NULL,
  completed_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_brand_progress_level_check CHECK (((level >= 1) AND (level <= 5))),
  CONSTRAINT academy_brand_progress_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT academy_brand_progress_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_brand_progress_pkey PRIMARY KEY (id),
  CONSTRAINT academy_brand_progress_user_id_brand_id_level_module_key_key UNIQUE (user_id, brand_id, level, module_key)
);

CREATE TABLE IF NOT EXISTS public.academy_brand_quiz_scores (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  brand_id uuid NOT NULL,
  level smallint NOT NULL DEFAULT 1,
  score integer NOT NULL,
  total integer NOT NULL,
  passed boolean DEFAULT false,
  completed_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_brand_quiz_scores_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT academy_brand_quiz_scores_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_brand_quiz_scores_pkey PRIMARY KEY (id),
  CONSTRAINT academy_brand_quiz_scores_user_id_brand_id_level_key UNIQUE (user_id, brand_id, level)
);

CREATE TABLE IF NOT EXISTS public.academy_brand_quizzes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  brand_id uuid NOT NULL,
  level smallint NOT NULL DEFAULT 1,
  questions jsonb NOT NULL DEFAULT '[]'::jsonb,
  version integer DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_brand_quizzes_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT academy_brand_quizzes_pkey PRIMARY KEY (id),
  CONSTRAINT academy_brand_quizzes_brand_id_level_key UNIQUE (brand_id, level)
);

CREATE TABLE IF NOT EXISTS public.academy_cert_gates (
  id text NOT NULL,
  definition jsonb NOT NULL,
  version integer NOT NULL DEFAULT 1,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT academy_cert_gates_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.academy_certifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  track_key text NOT NULL,
  awarded_at timestamp with time zone DEFAULT now(),
  cert_number text DEFAULT ('AIQ-'::text || upper(substr((gen_random_uuid())::text, 1, 8))),
  CONSTRAINT academy_certifications_track_key_fkey FOREIGN KEY (track_key) REFERENCES academy_tracks(track_key),
  CONSTRAINT academy_certifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_certifications_pkey PRIMARY KEY (id),
  CONSTRAINT academy_certifications_cert_number_key UNIQUE (cert_number),
  CONSTRAINT academy_certifications_user_id_track_key_key UNIQUE (user_id, track_key)
);

CREATE TABLE IF NOT EXISTS public.academy_chapters (
  id integer NOT NULL DEFAULT nextval('academy_chapters_id_seq'::regclass),
  volume_id integer,
  chapter_number integer NOT NULL,
  title text NOT NULL,
  slug text NOT NULL,
  intro text,
  sort_order integer DEFAULT 0,
  CONSTRAINT academy_chapters_volume_id_fkey FOREIGN KEY (volume_id) REFERENCES academy_volumes(id) ON DELETE CASCADE,
  CONSTRAINT academy_chapters_pkey PRIMARY KEY (id),
  CONSTRAINT academy_chapters_chapter_number_key UNIQUE (chapter_number),
  CONSTRAINT academy_chapters_slug_key UNIQUE (slug)
);

CREATE TABLE IF NOT EXISTS public.academy_cohort_members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  cohort_id uuid NOT NULL,
  user_id uuid NOT NULL,
  CONSTRAINT academy_cohort_members_cohort_id_fkey FOREIGN KEY (cohort_id) REFERENCES academy_cohorts(id) ON DELETE CASCADE,
  CONSTRAINT academy_cohort_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_cohort_members_pkey PRIMARY KEY (id),
  CONSTRAINT academy_cohort_members_cohort_id_user_id_key UNIQUE (cohort_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.academy_cohorts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  program text NOT NULL,
  firm_id uuid,
  facilitator_id uuid,
  max_participants integer DEFAULT 10,
  status text DEFAULT 'scheduled'::text,
  start_date date,
  end_date date,
  CONSTRAINT academy_cohorts_facilitator_id_fkey FOREIGN KEY (facilitator_id) REFERENCES auth.users(id),
  CONSTRAINT academy_cohorts_firm_id_fkey FOREIGN KEY (firm_id) REFERENCES academy_firms(id),
  CONSTRAINT academy_cohorts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.academy_daily_metrics (
  user_id uuid NOT NULL,
  metric_date date NOT NULL DEFAULT CURRENT_DATE,
  opportunities integer NOT NULL DEFAULT 0,
  captures integer NOT NULL DEFAULT 0,
  asks integer NOT NULL DEFAULT 0,
  touches integer NOT NULL DEFAULT 0,
  attach_presentations integer NOT NULL DEFAULT 0,
  sales integer NOT NULL DEFAULT 0,
  ticket_total numeric(12,2),
  debrief text,
  hot_flags text,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT academy_daily_metrics_asks_check CHECK ((asks >= 0)),
  CONSTRAINT academy_daily_metrics_attach_presentations_check CHECK ((attach_presentations >= 0)),
  CONSTRAINT academy_daily_metrics_captures_check CHECK ((captures >= 0)),
  CONSTRAINT academy_daily_metrics_opportunities_check CHECK ((opportunities >= 0)),
  CONSTRAINT academy_daily_metrics_sales_check CHECK ((sales >= 0)),
  CONSTRAINT academy_daily_metrics_ticket_total_check CHECK (((ticket_total IS NULL) OR (ticket_total >= (0)::numeric))),
  CONSTRAINT academy_daily_metrics_touches_check CHECK ((touches >= 0)),
  CONSTRAINT academy_daily_metrics_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_daily_metrics_pkey PRIMARY KEY (user_id, metric_date)
);

CREATE TABLE IF NOT EXISTS public.academy_firms (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text,
  plan_key text,
  seats_total integer DEFAULT 1,
  seats_used integer DEFAULT 0,
  owner_id uuid,
  billing_email text,
  is_white_label boolean DEFAULT false,
  white_label_name text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_firms_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id),
  CONSTRAINT academy_firms_plan_key_fkey FOREIGN KEY (plan_key) REFERENCES academy_plans(plan_key),
  CONSTRAINT academy_firms_pkey PRIMARY KEY (id),
  CONSTRAINT academy_firms_slug_key UNIQUE (slug)
);

CREATE TABLE IF NOT EXISTS public.academy_leads (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  lead_type text NOT NULL,
  name text,
  email text,
  firm text,
  track text,
  plan text,
  seats text,
  interest text,
  program text,
  cohort_size text,
  timing text,
  volume text,
  status text DEFAULT 'new'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_leads_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.academy_metric_imports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  key_id uuid,
  admin_user uuid,
  source text NOT NULL,
  rows_received integer NOT NULL,
  rows_applied integer NOT NULL,
  rows_failed integer NOT NULL,
  errors jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT academy_metric_imports_key_id_fkey FOREIGN KEY (key_id) REFERENCES academy_api_keys(id),
  CONSTRAINT academy_metric_imports_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.academy_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  organization_id uuid,
  type text NOT NULL,
  title text NOT NULL,
  body text,
  link text,
  brand_id uuid,
  read boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_notifications_type_check CHECK ((type = ANY (ARRAY['new_training'::text, 'required_training'::text, 'launch_training'::text, 'cert_expiring'::text, 'manager_assigned'::text, 'recommended'::text, 'updated_lesson'::text, 'brand_update'::text, 'quiz_available'::text]))),
  CONSTRAINT academy_notifications_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT academy_notifications_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT academy_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_notifications_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.academy_plans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  plan_key text NOT NULL,
  name text NOT NULL,
  description text,
  price_monthly numeric(10,2),
  price_annual numeric(10,2),
  min_seats integer DEFAULT 1,
  max_seats integer,
  features jsonb,
  is_active boolean DEFAULT true,
  CONSTRAINT academy_plans_pkey PRIMARY KEY (id),
  CONSTRAINT academy_plans_plan_key_key UNIQUE (plan_key)
);

CREATE TABLE IF NOT EXISTS public.academy_profiles (
  id uuid NOT NULL,
  full_name text,
  store_name text,
  role_title text,
  active_track text,
  firm_id uuid,
  onboarded boolean DEFAULT false,
  CONSTRAINT academy_profiles_active_track_fkey FOREIGN KEY (active_track) REFERENCES academy_tracks(track_key),
  CONSTRAINT academy_profiles_firm_id_fkey FOREIGN KEY (firm_id) REFERENCES academy_firms(id),
  CONSTRAINT academy_profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_profiles_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.academy_progress (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  chapter_id integer NOT NULL,
  completed_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_progress_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES academy_chapters(id) ON DELETE CASCADE,
  CONSTRAINT academy_progress_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_progress_pkey PRIMARY KEY (id),
  CONSTRAINT academy_progress_user_id_chapter_id_key UNIQUE (user_id, chapter_id)
);

CREATE TABLE IF NOT EXISTS public.academy_quiz_scores (
  user_id uuid NOT NULL,
  vol text NOT NULL,
  score integer NOT NULL,
  total integer NOT NULL,
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_quiz_scores_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_quiz_scores_pkey PRIMARY KEY (user_id, vol)
);

CREATE TABLE IF NOT EXISTS public.academy_quizzes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  volume_id integer NOT NULL,
  questions jsonb NOT NULL,
  version integer NOT NULL DEFAULT 1,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT academy_quizzes_volume_id_fkey FOREIGN KEY (volume_id) REFERENCES academy_volumes(id) ON DELETE CASCADE,
  CONSTRAINT academy_quizzes_pkey PRIMARY KEY (id),
  CONSTRAINT academy_quizzes_volume_id_version_key UNIQUE (volume_id, version)
);

CREATE TABLE IF NOT EXISTS public.academy_seats (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  firm_id uuid NOT NULL,
  user_id uuid,
  invited_email text,
  role text DEFAULT 'member'::text,
  status text DEFAULT 'pending'::text,
  assigned_at timestamp with time zone DEFAULT now(),
  CONSTRAINT academy_seats_firm_id_fkey FOREIGN KEY (firm_id) REFERENCES academy_firms(id) ON DELETE CASCADE,
  CONSTRAINT academy_seats_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT academy_seats_pkey PRIMARY KEY (id),
  CONSTRAINT academy_seats_firm_id_user_id_key UNIQUE (firm_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.academy_track_progress (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  track_key text NOT NULL,
  started_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  CONSTRAINT academy_track_progress_track_key_fkey FOREIGN KEY (track_key) REFERENCES academy_tracks(track_key) ON DELETE CASCADE,
  CONSTRAINT academy_track_progress_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT academy_track_progress_pkey PRIMARY KEY (id),
  CONSTRAINT academy_track_progress_user_id_track_key_key UNIQUE (user_id, track_key)
);

CREATE TABLE IF NOT EXISTS public.academy_tracks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  track_key text NOT NULL,
  badge text NOT NULL,
  name text NOT NULL,
  timeline text,
  cert_name text,
  description text,
  ch_range_min integer,
  ch_range_max integer,
  ch_nums _int4[],
  sort_order integer DEFAULT 0,
  CONSTRAINT academy_tracks_pkey PRIMARY KEY (id),
  CONSTRAINT academy_tracks_track_key_key UNIQUE (track_key)
);

CREATE TABLE IF NOT EXISTS public.academy_volumes (
  id integer NOT NULL DEFAULT nextval('academy_volumes_id_seq'::regclass),
  vol_number integer NOT NULL,
  title text NOT NULL,
  description text,
  sort_order integer DEFAULT 0,
  CONSTRAINT academy_volumes_pkey PRIMARY KEY (id),
  CONSTRAINT academy_volumes_vol_number_key UNIQUE (vol_number)
);

CREATE TABLE IF NOT EXISTS public.academy_worksheets (
  id text NOT NULL,
  title text NOT NULL,
  track text NOT NULL DEFAULT 'all'::text,
  definition jsonb NOT NULL,
  version integer NOT NULL DEFAULT 1,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT academy_worksheets_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.activities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  actor_user_id uuid,
  entity_type text NOT NULL,
  entity_id uuid,
  activity_type text NOT NULL,
  summary text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  user_id uuid,
  title text,
  source text NOT NULL DEFAULT 'manual'::text,
  related_file_path text,
  related_recording_id uuid,
  related_email_id uuid,
  related_presentation_id uuid,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT activities_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'ai_generated'::text, 'email_integration'::text, 'call_integration'::text, 'upload'::text]))),
  CONSTRAINT activities_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT activities_email_fk FOREIGN KEY (related_email_id) REFERENCES crm_emails(id) ON DELETE SET NULL,
  CONSTRAINT activities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT activities_presentation_fk FOREIGN KEY (related_presentation_id) REFERENCES crm_presentations(id) ON DELETE SET NULL,
  CONSTRAINT activities_recording_fk FOREIGN KEY (related_recording_id) REFERENCES sales_recordings(id) ON DELETE SET NULL,
  CONSTRAINT activities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT activities_pkey PRIMARY KEY (id)
);

-- =========================
-- TABLES: ai_* through aicrm_f*
-- =========================

CREATE TABLE IF NOT EXISTS public.ai_assistants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  assistant_key text NOT NULL,
  label text NOT NULL,
  category text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'active'::text,
  approval_policy text NOT NULL DEFAULT 'approval_required'::text,
  approval_required boolean NOT NULL DEFAULT true,
  organization_id uuid,
  retrieval_scopes _text[] NOT NULL DEFAULT ARRAY['crm'::text, 'knowledge'::text],
  safety_controls jsonb NOT NULL DEFAULT '{}'::jsonb,
  response_contract jsonb NOT NULL DEFAULT '{}'::jsonb,
  required_feature_key text,
  required_entitlement_key text,
  required_permission_name text,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_assistants_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text]))),
  CONSTRAINT ai_assistants_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_assistants_pkey PRIMARY KEY (id),
  CONSTRAINT ai_assistants_assistant_key_key UNIQUE (assistant_key)
);

CREATE TABLE IF NOT EXISTS public.ai_audit_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  request_id uuid,
  assistant_key text,
  event_type text NOT NULL,
  event_status text NOT NULL DEFAULT 'recorded'::text,
  event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_audit_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_audit_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_budget_predictions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  budget_plan_id uuid,
  location_id uuid,
  user_id uuid,
  prediction_type text NOT NULL,
  metric_key text,
  period_key text,
  predicted_value numeric,
  confidence numeric,
  insight_text text NOT NULL,
  recommended_action text,
  is_acknowledged boolean DEFAULT false,
  acknowledged_by uuid,
  model text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_budget_predictions_prediction_type_check CHECK ((prediction_type = ANY (ARRAY['trend_alert'::text, 'budget_forecast'::text, 'coaching_recommendation'::text, 'staffing_suggestion'::text]))),
  CONSTRAINT ai_budget_predictions_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES auth.users(id),
  CONSTRAINT ai_budget_predictions_budget_plan_id_fkey FOREIGN KEY (budget_plan_id) REFERENCES budget_plans(id),
  CONSTRAINT ai_budget_predictions_location_id_fkey FOREIGN KEY (location_id) REFERENCES org_locations(id),
  CONSTRAINT ai_budget_predictions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_budget_predictions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT ai_budget_predictions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_coaching_reviews (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  activity_id uuid,
  recording_id uuid,
  review_kind text NOT NULL DEFAULT 'coaching'::text,
  analysis jsonb NOT NULL DEFAULT '{}'::jsonb,
  kpi_scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  overall_score numeric(4,1),
  model text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_coaching_reviews_review_kind_check CHECK ((review_kind = ANY (ARRAY['coaching'::text, 'summary'::text]))),
  CONSTRAINT ai_coaching_reviews_activity_id_fkey FOREIGN KEY (activity_id) REFERENCES activities(id) ON DELETE CASCADE,
  CONSTRAINT ai_coaching_reviews_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_coaching_reviews_recording_id_fkey FOREIGN KEY (recording_id) REFERENCES sales_recordings(id) ON DELETE SET NULL,
  CONSTRAINT ai_coaching_reviews_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_conversation_memory (
  conversation_id uuid NOT NULL,
  user_id uuid NOT NULL,
  profile jsonb NOT NULL DEFAULT '{}'::jsonb,
  contradictions jsonb NOT NULL DEFAULT '[]'::jsonb,
  discussed_models jsonb NOT NULL DEFAULT '[]'::jsonb,
  recommendations jsonb NOT NULL DEFAULT '[]'::jsonb,
  outstanding_questions jsonb NOT NULL DEFAULT '[]'::jsonb,
  completeness_score numeric(5,2) NOT NULL DEFAULT 0,
  memory_version integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_conversation_memory_completeness_score_check CHECK (((completeness_score >= (0)::numeric) AND (completeness_score <= (100)::numeric))),
  CONSTRAINT ai_conversation_memory_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE,
  CONSTRAINT ai_conversation_memory_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_conversation_memory_pkey PRIMARY KEY (conversation_id)
);

CREATE TABLE IF NOT EXISTS public.ai_conversation_turns (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text NOT NULL,
  content text NOT NULL,
  extracted_facts jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_conversation_turns_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text, 'system'::text, 'tool'::text]))),
  CONSTRAINT ai_conversation_turns_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE,
  CONSTRAINT ai_conversation_turns_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_conversation_turns_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_conversations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  organization_id uuid,
  crm_record_type text,
  crm_record_id uuid,
  title text,
  stage text NOT NULL DEFAULT 'discovery'::text,
  status text NOT NULL DEFAULT 'active'::text,
  last_message_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_conversations_stage_check CHECK ((stage = ANY (ARRAY['discovery'::text, 'qualification'::text, 'product_selection'::text, 'comparison'::text, 'installation_review'::text, 'quote_preparation'::text, 'objection_handling'::text, 'close'::text, 'follow_up'::text, 'post_sale'::text]))),
  CONSTRAINT ai_conversations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'archived'::text]))),
  CONSTRAINT ai_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_conversations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_knowledge_chunks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  source_id uuid NOT NULL,
  organization_id uuid,
  chunk_key text NOT NULL,
  title text,
  content text NOT NULL,
  citation jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'active'::text,
  visibility text NOT NULL DEFAULT 'global'::text,
  embedding vector,
  embedding_model text,
  source_hash text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_knowledge_chunks_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text]))),
  CONSTRAINT ai_knowledge_chunks_visibility_check CHECK ((visibility = ANY (ARRAY['global'::text, 'organization'::text]))),
  CONSTRAINT ai_knowledge_chunks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_knowledge_chunks_source_id_fkey FOREIGN KEY (source_id) REFERENCES ai_knowledge_sources(id) ON DELETE CASCADE,
  CONSTRAINT ai_knowledge_chunks_pkey PRIMARY KEY (id),
  CONSTRAINT ai_knowledge_chunks_chunk_key_key UNIQUE (chunk_key)
);

CREATE TABLE IF NOT EXISTS public.ai_knowledge_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  source_key text NOT NULL,
  title text NOT NULL,
  source_type text NOT NULL,
  authority_level text NOT NULL DEFAULT 'reference'::text,
  visibility text NOT NULL DEFAULT 'global'::text,
  status text NOT NULL DEFAULT 'active'::text,
  version integer NOT NULL DEFAULT 1,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_knowledge_sources_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text]))),
  CONSTRAINT ai_knowledge_sources_visibility_check CHECK ((visibility = ANY (ARRAY['global'::text, 'organization'::text]))),
  CONSTRAINT ai_knowledge_sources_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_knowledge_sources_pkey PRIMARY KEY (id),
  CONSTRAINT ai_knowledge_sources_source_key_key UNIQUE (source_key)
);

CREATE TABLE IF NOT EXISTS public.ai_manager_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  decision_case_id uuid,
  title text NOT NULL,
  instructions text,
  assigned_to uuid,
  assigned_by uuid,
  priority text NOT NULL DEFAULT 'medium'::text,
  status text NOT NULL DEFAULT 'open'::text,
  due_at timestamp with time zone,
  accepted_at timestamp with time zone,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  blocked_reason text,
  escalation_level integer NOT NULL DEFAULT 0,
  source text NOT NULL DEFAULT 'ai_manager'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  assigned_role text,
  submitted_at timestamp with time zone,
  submitted_by uuid,
  completion_summary text,
  proof_required boolean NOT NULL DEFAULT true,
  approval_status text NOT NULL DEFAULT 'not_submitted'::text,
  approved_at timestamp with time zone,
  approved_by uuid,
  rejection_reason text,
  CONSTRAINT ai_manager_assignments_approval_status_check CHECK ((approval_status = ANY (ARRAY['not_submitted'::text, 'pending'::text, 'approved'::text, 'rejected'::text]))),
  CONSTRAINT ai_manager_assignments_escalation_level_check CHECK (((escalation_level >= 0) AND (escalation_level <= 5))),
  CONSTRAINT ai_manager_assignments_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text]))),
  CONSTRAINT ai_manager_assignments_status_check CHECK ((status = ANY (ARRAY['open'::text, 'accepted'::text, 'in_progress'::text, 'blocked'::text, 'completed'::text, 'cancelled'::text]))),
  CONSTRAINT ai_manager_assignments_decision_case_id_fkey FOREIGN KEY (decision_case_id) REFERENCES decision_cases(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_assignments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_assignments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_manager_briefs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  brief_date date NOT NULL DEFAULT CURRENT_DATE,
  brief_type text NOT NULL DEFAULT 'daily'::text,
  headline text NOT NULL,
  executive_summary text NOT NULL,
  priorities jsonb NOT NULL DEFAULT '[]'::jsonb,
  risks jsonb NOT NULL DEFAULT '[]'::jsonb,
  wins jsonb NOT NULL DEFAULT '[]'::jsonb,
  workload jsonb NOT NULL DEFAULT '{}'::jsonb,
  financial_exposure_cad numeric NOT NULL DEFAULT 0,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  generated_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  period_start date,
  period_end date,
  delivery_status text NOT NULL DEFAULT 'draft'::text,
  delivered_at timestamp with time zone,
  delivery_channels jsonb NOT NULL DEFAULT '[]'::jsonb,
  narrative jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT ai_manager_briefs_brief_type_check CHECK ((brief_type = ANY (ARRAY['daily'::text, 'weekly'::text, 'exception'::text]))),
  CONSTRAINT ai_manager_briefs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_briefs_pkey PRIMARY KEY (id),
  CONSTRAINT ai_manager_briefs_organization_id_brief_date_brief_type_key UNIQUE (organization_id, brief_date, brief_type)
);

CREATE TABLE IF NOT EXISTS public.ai_manager_escalations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  level integer NOT NULL,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open'::text,
  escalated_to uuid,
  acknowledged_at timestamp with time zone,
  resolved_at timestamp with time zone,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_manager_escalations_level_check CHECK (((level >= 1) AND (level <= 5))),
  CONSTRAINT ai_manager_escalations_status_check CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text, 'dismissed'::text]))),
  CONSTRAINT ai_manager_escalations_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES ai_manager_assignments(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_escalations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_escalations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_manager_task_attachments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  uploaded_by uuid NOT NULL,
  storage_bucket text NOT NULL DEFAULT 'manager-task-files'::text,
  storage_path text NOT NULL,
  file_name text NOT NULL,
  mime_type text,
  file_size_bytes bigint,
  attachment_type text NOT NULL DEFAULT 'supporting'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_manager_task_attachments_attachment_type_check CHECK ((attachment_type = ANY (ARRAY['supporting'::text, 'proof'::text, 'approval'::text]))),
  CONSTRAINT ai_manager_task_attachments_file_size_bytes_check CHECK (((file_size_bytes IS NULL) OR (file_size_bytes >= 0))),
  CONSTRAINT ai_manager_task_attachments_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES ai_manager_assignments(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_task_attachments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_task_attachments_pkey PRIMARY KEY (id),
  CONSTRAINT ai_manager_task_attachments_storage_bucket_storage_path_key UNIQUE (storage_bucket, storage_path)
);

CREATE TABLE IF NOT EXISTS public.ai_manager_task_comments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  author_id uuid NOT NULL,
  body text NOT NULL,
  comment_type text NOT NULL DEFAULT 'comment'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_manager_task_comments_body_check CHECK (((length(TRIM(BOTH FROM body)) >= 1) AND (length(TRIM(BOTH FROM body)) <= 5000))),
  CONSTRAINT ai_manager_task_comments_comment_type_check CHECK ((comment_type = ANY (ARRAY['comment'::text, 'status_note'::text, 'manager_note'::text, 'rejection_note'::text]))),
  CONSTRAINT ai_manager_task_comments_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES ai_manager_assignments(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_task_comments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_task_comments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_manager_task_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  actor_id uuid,
  event_type text NOT NULL,
  from_value text,
  to_value text,
  note text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_manager_task_history_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES ai_manager_assignments(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_task_history_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_manager_task_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_personas (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  persona_name text NOT NULL,
  persona_role text NOT NULL,
  avatar_emoji text,
  tone text,
  specialization text,
  personality_traits text,
  prompt_prefix text,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT ai_personas_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_personas_pkey PRIMARY KEY (id),
  CONSTRAINT ai_personas_organization_id_persona_name_key UNIQUE (organization_id, persona_name)
);

CREATE TABLE IF NOT EXISTS public.ai_product_comparisons (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  user_id uuid NOT NULL,
  conversation_id uuid,
  crm_record_type text,
  crm_record_id uuid,
  title text,
  status text NOT NULL DEFAULT 'active'::text,
  comparison_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  selected_product_ids _uuid[] NOT NULL DEFAULT '{}'::uuid[],
  winner_product_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_product_comparisons_status_check CHECK ((status = ANY (ARRAY['active'::text, 'shared'::text, 'archived'::text]))),
  CONSTRAINT ai_product_comparisons_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE SET NULL,
  CONSTRAINT ai_product_comparisons_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_product_comparisons_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_product_comparisons_winner_product_id_fkey FOREIGN KEY (winner_product_id) REFERENCES aiq_products(id) ON DELETE SET NULL,
  CONSTRAINT ai_product_comparisons_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_prompt_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  template_key text NOT NULL,
  tool_type text NOT NULL,
  label text NOT NULL,
  organization_id uuid,
  status text NOT NULL DEFAULT 'active'::text,
  system_prompt text NOT NULL,
  user_prompt_template text NOT NULL,
  tone_guidance text,
  output_schema jsonb,
  version integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_prompt_templates_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text]))),
  CONSTRAINT ai_prompt_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_prompt_templates_pkey PRIMARY KEY (id),
  CONSTRAINT ai_prompt_templates_template_key_key UNIQUE (template_key)
);

CREATE TABLE IF NOT EXISTS public.ai_proposed_actions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  request_id uuid,
  assistant_key text NOT NULL,
  action_type text NOT NULL,
  action_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending'::text,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_proposed_actions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'executed'::text, 'expired'::text]))),
  CONSTRAINT ai_proposed_actions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_proposed_actions_request_id_fkey FOREIGN KEY (request_id) REFERENCES ai_requests(id) ON DELETE CASCADE,
  CONSTRAINT ai_proposed_actions_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id),
  CONSTRAINT ai_proposed_actions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  session_id uuid,
  user_id uuid NOT NULL,
  assistant_key text NOT NULL,
  request_status text NOT NULL DEFAULT 'received'::text,
  prompt text NOT NULL,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  grounded_context jsonb,
  output jsonb,
  explanation text,
  model_provider text,
  model_name text,
  token_estimate integer,
  error_message text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  CONSTRAINT ai_requests_assistant_key_fkey FOREIGN KEY (assistant_key) REFERENCES ai_assistants(assistant_key),
  CONSTRAINT ai_requests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_requests_session_id_fkey FOREIGN KEY (session_id) REFERENCES ai_sessions(id) ON DELETE SET NULL,
  CONSTRAINT ai_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_requests_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_roleplay_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  scenario_type text NOT NULL,
  status text NOT NULL DEFAULT 'active'::text,
  total_turns integer DEFAULT 0,
  session_score numeric,
  kpi_scores jsonb,
  transcript jsonb,
  feedback text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  CONSTRAINT ai_roleplay_sessions_scenario_type_check CHECK ((scenario_type = ANY (ARRAY['cold_call'::text, 'follow_up'::text, 'objection_handling'::text, 'product_demo'::text]))),
  CONSTRAINT ai_roleplay_sessions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'abandoned'::text]))),
  CONSTRAINT ai_roleplay_sessions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_roleplay_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_roleplay_sessions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  assistant_key text NOT NULL,
  status text NOT NULL DEFAULT 'active'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  last_activity_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_sessions_assistant_key_fkey FOREIGN KEY (assistant_key) REFERENCES ai_assistants(assistant_key),
  CONSTRAINT ai_sessions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_sessions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_token_limits (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  tier text NOT NULL,
  monthly_limit bigint NOT NULL,
  tokens_used_this_month bigint NOT NULL DEFAULT 0,
  reset_date date NOT NULL DEFAULT (CURRENT_DATE + '1 mon'::interval),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_token_limits_tier_check CHECK ((tier = ANY (ARRAY['starter'::text, 'pro'::text, 'enterprise'::text, 'demo'::text]))),
  CONSTRAINT ai_token_limits_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_token_limits_pkey PRIMARY KEY (id),
  CONSTRAINT ai_token_limits_organization_id_key UNIQUE (organization_id)
);

CREATE TABLE IF NOT EXISTS public.ai_trainer_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id uuid,
  user_id uuid,
  msg_role text NOT NULL,
  content text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT ai_trainer_messages_msg_role_check CHECK ((msg_role = ANY (ARRAY['user'::text, 'assistant'::text]))),
  CONSTRAINT ai_trainer_messages_session_id_fkey FOREIGN KEY (session_id) REFERENCES ai_trainer_sessions(id) ON DELETE CASCADE,
  CONSTRAINT ai_trainer_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_trainer_messages_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.ai_trainer_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid,
  chapter_slug text NOT NULL,
  course text,
  module text,
  lesson text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT ai_trainer_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT ai_trainer_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT ai_trainer_sessions_user_id_chapter_slug_key UNIQUE (user_id, chapter_slug)
);

CREATE TABLE IF NOT EXISTS public.ai_usage_meter (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  assistant_key text,
  request_id uuid,
  usage_kind text NOT NULL,
  quantity numeric NOT NULL,
  limit_key text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT ai_usage_meter_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT ai_usage_meter_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_account_custom_field_values (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  custom_field_id uuid NOT NULL,
  value jsonb,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_account_custom_field_values_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_custom_field_values_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_account_custom_field_values_custom_field_id_fkey FOREIGN KEY (custom_field_id) REFERENCES aicrm_account_custom_fields(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_custom_field_values_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_custom_field_values_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_account_custom_field_values_pkey PRIMARY KEY (id),
  CONSTRAINT aicrm_account_custom_field_values_unique UNIQUE (account_id, custom_field_id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_account_custom_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  field_key citext NOT NULL,
  field_name text NOT NULL,
  field_type aicrm_custom_field_type NOT NULL DEFAULT 'text'::aicrm_custom_field_type,
  is_required boolean NOT NULL DEFAULT false,
  options jsonb NOT NULL DEFAULT '[]'::jsonb,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_account_custom_fields_sort_order_check CHECK ((sort_order >= 0)),
  CONSTRAINT aicrm_account_custom_fields_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_account_custom_fields_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_custom_fields_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_account_custom_fields_pkey PRIMARY KEY (id),
  CONSTRAINT aicrm_account_custom_fields_org_key UNIQUE (organization_id, field_key)
);

CREATE TABLE IF NOT EXISTS public.aicrm_account_execution_briefs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  account_name text NOT NULL,
  executive_summary text,
  relationship_summary text,
  product_fit text,
  recommended_playbook text,
  recommended_campaign text,
  recommended_sales_motion text,
  recommended_meeting_agenda text,
  next_three_actions jsonb NOT NULL DEFAULT '[]'::jsonb,
  confidence numeric NOT NULL DEFAULT 0,
  source text NOT NULL DEFAULT 'system'::text,
  last_calculated_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_account_execution_briefs_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_account_execution_briefs_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_execution_briefs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_execution_briefs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_account_product_fit (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  product_id uuid NOT NULL,
  fit_score numeric NOT NULL DEFAULT 0,
  fit_tier text NOT NULL DEFAULT 'unknown'::text,
  fit_reason text,
  recommended_sales_motion text,
  recommended_campaign text,
  confidence numeric NOT NULL DEFAULT 0,
  source text NOT NULL DEFAULT 'system'::text,
  reviewed_status text NOT NULL DEFAULT 'pending'::text,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  last_calculated_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_account_product_fit_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_account_product_fit_fit_score_check CHECK (((fit_score >= (0)::numeric) AND (fit_score <= (100)::numeric))),
  CONSTRAINT aicrm_account_product_fit_fit_tier_check CHECK ((fit_tier = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text, 'not_fit'::text, 'unknown'::text]))),
  CONSTRAINT aicrm_account_product_fit_reviewed_status_check CHECK ((reviewed_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_review'::text]))),
  CONSTRAINT aicrm_account_product_fit_source_check CHECK ((source = ANY (ARRAY['ai'::text, 'manual'::text, 'import'::text, 'system'::text]))),
  CONSTRAINT aicrm_account_product_fit_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_product_fit_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_product_fit_product_id_fkey FOREIGN KEY (product_id) REFERENCES aicrm_products(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_product_fit_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_account_product_fit_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_account_tags (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  tag_id uuid NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_account_tags_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_tags_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_account_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES aicrm_tags(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_account_tags_pkey PRIMARY KEY (id),
  CONSTRAINT aicrm_account_tags_account_id_tag_id_key UNIQUE (account_id, tag_id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_accounts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  owner_id uuid,
  company_name text NOT NULL,
  legal_name text,
  category text,
  subcategory text,
  segment text,
  account_type text,
  website text,
  province text,
  city text,
  market text,
  address text,
  postal_code text,
  country text,
  latitude numeric,
  longitude numeric,
  google_place_id text,
  estimated_revenue numeric,
  revenue_low_cad numeric,
  revenue_high_cad numeric,
  revenue_tier text,
  revenue_basis text,
  revenue_confidence numeric,
  employee_count integer,
  location_count integer,
  parent_company text,
  description text,
  channel_product_fit text,
  spec_channel_influence text,
  priority_score numeric,
  priority_score_basis text,
  verification_status text,
  pipeline_stage text,
  last_touch timestamp with time zone,
  next_action text,
  status text,
  do_not_contact boolean NOT NULL DEFAULT false,
  source text,
  source_confidence numeric,
  linkedin_company_url text,
  google_business_url text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  scoring_review_required boolean NOT NULL DEFAULT false,
  scoring_review_reason text,
  last_scored_at timestamp with time zone,
  CONSTRAINT aicrm_accounts_company_name_nonempty CHECK ((length(TRIM(BOTH FROM company_name)) > 0)),
  CONSTRAINT aicrm_accounts_employee_count_check CHECK (((employee_count IS NULL) OR (employee_count >= 0))),
  CONSTRAINT aicrm_accounts_location_count_check CHECK (((location_count IS NULL) OR (location_count >= 0))),
  CONSTRAINT aicrm_accounts_priority_score_check CHECK (((priority_score IS NULL) OR ((priority_score >= (0)::numeric) AND (priority_score <= (100)::numeric)))),
  CONSTRAINT aicrm_accounts_revenue_confidence_check CHECK (((revenue_confidence IS NULL) OR ((revenue_confidence >= (0)::numeric) AND (revenue_confidence <= (100)::numeric)))),
  CONSTRAINT aicrm_accounts_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_accounts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_accounts_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_accounts_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_accounts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_activities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid,
  contact_id uuid,
  opportunity_id uuid,
  activity_type text NOT NULL,
  direction text,
  activity_date timestamp with time zone NOT NULL DEFAULT now(),
  outcome text,
  notes text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_activities_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_activities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_activities_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_activities_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_activities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_activities_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_ai_enrichment_jobs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  requested_by uuid,
  job_type text NOT NULL,
  status text NOT NULL DEFAULT 'queued'::text,
  provider text NOT NULL DEFAULT 'mock'::text,
  input_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_payload jsonb,
  error_message text,
  tokens_used integer,
  cost_estimate numeric,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  mock_mode boolean NOT NULL DEFAULT false,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  model text,
  prompt_version text,
  source_fingerprint text,
  CONSTRAINT aicrm_ai_enrichment_jobs_job_type_check CHECK ((job_type = ANY (ARRAY['company_summary'::text, 'revenue_estimate'::text, 'employee_estimate'::text, 'category_classification'::text, 'buying_group_detection'::text, 'contact_role_recommendation'::text, 'website_discovery'::text, 'linkedin_discovery'::text, 'duplicate_detection'::text, 'score_explanation'::text, 'next_action_recommendation'::text, 'campaign_recommendation'::text, 'full_account_enrichment'::text]))),
  CONSTRAINT aicrm_ai_enrichment_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text, 'mock_completed'::text]))),
  CONSTRAINT aicrm_ai_enrichment_jobs_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_ai_enrichment_jobs_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_enrichment_jobs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_ai_enrichment_jobs_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_enrichment_jobs_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_enrichment_jobs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_ai_profiles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  brand_id uuid,
  name text NOT NULL,
  industry text,
  preferred_channels jsonb NOT NULL DEFAULT '[]'::jsonb,
  preferred_products jsonb NOT NULL DEFAULT '[]'::jsonb,
  preferred_brands jsonb NOT NULL DEFAULT '[]'::jsonb,
  buyer_types jsonb NOT NULL DEFAULT '[]'::jsonb,
  sales_language text,
  outreach_style text,
  prompt_profile jsonb NOT NULL DEFAULT '{}'::jsonb,
  active boolean NOT NULL DEFAULT true,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_ai_profiles_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES aicrm_brands(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_profiles_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_profiles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_ai_profiles_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_ai_research (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  research_summary text,
  revenue_score numeric,
  influence_score numeric,
  growth_score numeric,
  strategic_score numeric,
  priority_score numeric,
  score_explanation text,
  confidence numeric,
  provider text,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  mock_generated boolean NOT NULL DEFAULT false,
  output_payload jsonb,
  last_updated timestamp with time zone,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  recommended_products jsonb NOT NULL DEFAULT '[]'::jsonb,
  recommended_campaign text,
  recommended_campaign_reasoning text,
  recommended_next_action text,
  recommended_next_action_reasoning text,
  recommended_next_action_confidence numeric,
  product_fit_scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  model text,
  prompt_version text,
  review_status text NOT NULL DEFAULT 'pending'::text,
  executive_summary text,
  company_summary text,
  business_model text,
  likely_customer_type text,
  estimated_size text,
  growth_indicators text,
  buying_influence jsonb NOT NULL DEFAULT '{}'::jsonb,
  sales_intelligence text,
  recommended_contacts jsonb NOT NULL DEFAULT '[]'::jsonb,
  source_fingerprint text,
  CONSTRAINT aicrm_ai_research_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (100)::numeric)))),
  CONSTRAINT aicrm_ai_research_growth_score_check CHECK (((growth_score IS NULL) OR ((growth_score >= (0)::numeric) AND (growth_score <= (100)::numeric)))),
  CONSTRAINT aicrm_ai_research_influence_score_check CHECK (((influence_score IS NULL) OR ((influence_score >= (0)::numeric) AND (influence_score <= (100)::numeric)))),
  CONSTRAINT aicrm_ai_research_priority_score_check CHECK (((priority_score IS NULL) OR ((priority_score >= (0)::numeric) AND (priority_score <= (100)::numeric)))),
  CONSTRAINT aicrm_ai_research_revenue_score_check CHECK (((revenue_score IS NULL) OR ((revenue_score >= (0)::numeric) AND (revenue_score <= (100)::numeric)))),
  CONSTRAINT aicrm_ai_research_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'reviewed'::text, 'approved'::text, 'rejected'::text]))),
  CONSTRAINT aicrm_ai_research_strategic_score_check CHECK (((strategic_score IS NULL) OR ((strategic_score >= (0)::numeric) AND (strategic_score <= (100)::numeric)))),
  CONSTRAINT aicrm_ai_research_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_ai_research_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_research_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_ai_research_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_research_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_ai_research_pkey PRIMARY KEY (id),
  CONSTRAINT aicrm_ai_research_org_account_unique UNIQUE (organization_id, account_id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  account_id uuid,
  job_id uuid,
  event_type text NOT NULL,
  job_type text,
  provider text,
  before_state jsonb,
  after_state jsonb,
  mock_mode boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  request_payload jsonb,
  response_payload jsonb,
  CONSTRAINT aicrm_audit_log_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_audit_log_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_audit_log_job_id_fkey FOREIGN KEY (job_id) REFERENCES aicrm_ai_enrichment_jobs(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_audit_log_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_audit_log_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_brands (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_brands_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_brands_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_brands_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_brands_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_business_units (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_business_units_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_business_units_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_business_units_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_buying_committee (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  person_id uuid NOT NULL,
  committee_role text NOT NULL,
  influence_level numeric NOT NULL DEFAULT 50,
  trust_level text NOT NULL DEFAULT 'medium'::text,
  notes text,
  source text NOT NULL DEFAULT 'manual'::text,
  current boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_buying_committee_committee_role_check CHECK ((committee_role = ANY (ARRAY['Decision Maker'::text, 'Economic Buyer'::text, 'Technical Buyer'::text, 'Design Influence'::text, 'Operations'::text, 'Executive Sponsor'::text, 'Champion'::text]))),
  CONSTRAINT aicrm_buying_committee_influence_level_check CHECK (((influence_level >= (0)::numeric) AND (influence_level <= (100)::numeric))),
  CONSTRAINT aicrm_buying_committee_trust_level_check CHECK ((trust_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'very_high'::text]))),
  CONSTRAINT aicrm_buying_committee_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_buying_committee_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_buying_committee_person_id_fkey FOREIGN KEY (person_id) REFERENCES aicrm_people(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_buying_committee_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_campaign_categories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_campaign_categories_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_campaign_categories_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_campaign_categories_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_campaign_categories_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_campaign_sequences (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  campaign_type_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  is_default boolean NOT NULL DEFAULT true,
  steps jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_campaign_sequences_campaign_type_id_fkey FOREIGN KEY (campaign_type_id) REFERENCES aicrm_campaign_types(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_campaign_sequences_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_campaign_sequences_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_campaign_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  campaign_category_id uuid,
  channel_id uuid,
  sales_motion_id uuid,
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  default_sequence jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_campaign_types_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_campaign_types_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_campaign_types_campaign_category_id_fkey FOREIGN KEY (campaign_category_id) REFERENCES aicrm_campaign_categories(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_campaign_types_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES aicrm_channels(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_campaign_types_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_campaign_types_sales_motion_id_fkey FOREIGN KEY (sales_motion_id) REFERENCES aicrm_sales_motions(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_campaign_types_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_channels (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_channels_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_channels_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_channels_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_channels_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_collaboration_audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  partner_organization_id uuid,
  entity_type text NOT NULL,
  entity_id uuid,
  action text NOT NULL,
  permission_level text,
  result text NOT NULL DEFAULT 'success'::text,
  revocation_reason text,
  actor_user_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_collaboration_audit_log_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_collaboration_audit_log_partner_organization_id_fkey FOREIGN KEY (partner_organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_collaboration_audit_log_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_consent_records (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  email text NOT NULL,
  channel text NOT NULL DEFAULT 'email'::text,
  consent_status text NOT NULL DEFAULT 'unknown'::text,
  source text,
  notes text,
  source_record_id text,
  obtained_at timestamp with time zone,
  expires_at timestamp with time zone,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_consent_records_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'phone'::text, 'mail'::text, 'linkedin'::text, 'task'::text]))),
  CONSTRAINT aicrm_consent_records_status_check CHECK ((consent_status = ANY (ARRAY['unknown'::text, 'pending'::text, 'granted'::text, 'revoked'::text, 'unreachable'::text, 'bounced'::text]))),
  CONSTRAINT aicrm_consent_records_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_consent_records_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_consent_records_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_consent_records_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_consent_records_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_consent_records_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid,
  first_name text,
  last_name text,
  full_name text,
  title text,
  department text,
  role_type text,
  email citext,
  email_status text,
  phone text,
  direct_phone text,
  linkedin_url text,
  priority text,
  influence_score numeric,
  decision_maker boolean NOT NULL DEFAULT false,
  source text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_contacts_full_name_or_names CHECK (((full_name IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM first_name), ''::text) IS NOT NULL) OR (NULLIF(TRIM(BOTH FROM last_name), ''::text) IS NOT NULL))),
  CONSTRAINT aicrm_contacts_influence_score_check CHECK (((influence_score IS NULL) OR ((influence_score >= (0)::numeric) AND (influence_score <= (100)::numeric)))),
  CONSTRAINT aicrm_contacts_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_contacts_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_contacts_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_contacts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_daily_execution_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  queue_date date NOT NULL DEFAULT CURRENT_DATE,
  account_id uuid NOT NULL,
  account_name text NOT NULL,
  contact_id uuid,
  contact_name text,
  opportunity_id uuid,
  opportunity_title text,
  product_id uuid,
  product_name text,
  playbook_id uuid,
  playbook_name text,
  source_bucket text NOT NULL DEFAULT 'top_target'::text,
  priority numeric NOT NULL DEFAULT 0,
  reason text NOT NULL,
  confidence numeric NOT NULL DEFAULT 0,
  estimated_revenue_impact numeric NOT NULL DEFAULT 0,
  recommended_action text NOT NULL,
  meeting_objective text,
  potential_objection text,
  bring_items text,
  coach_note text,
  status text NOT NULL DEFAULT 'queued'::text,
  completed_at timestamp with time zone,
  ignored_at timestamp with time zone,
  last_scored_at timestamp with time zone,
  source text NOT NULL DEFAULT 'system'::text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_daily_execution_queue_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_daily_execution_queue_estimated_revenue_impact_check CHECK ((estimated_revenue_impact >= (0)::numeric)),
  CONSTRAINT aicrm_daily_execution_queue_priority_check CHECK (((priority >= (0)::numeric) AND (priority <= (100)::numeric))),
  CONSTRAINT aicrm_daily_execution_queue_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'completed'::text, 'ignored'::text, 'deferred'::text]))),
  CONSTRAINT aicrm_daily_execution_queue_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_daily_execution_queue_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_daily_execution_queue_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_daily_execution_queue_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_daily_execution_queue_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_daily_execution_queue_playbook_id_fkey FOREIGN KEY (playbook_id) REFERENCES aicrm_sales_playbooks(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_daily_execution_queue_product_id_fkey FOREIGN KEY (product_id) REFERENCES aicrm_products(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_daily_execution_queue_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_employment_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  person_id uuid NOT NULL,
  company_id uuid NOT NULL,
  title text,
  department text,
  start_date date,
  end_date date,
  current boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_employment_history_company_id_fkey FOREIGN KEY (company_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_employment_history_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_employment_history_person_id_fkey FOREIGN KEY (person_id) REFERENCES aicrm_people(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_employment_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_enrichment_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  enrichment_job_id uuid,
  job_type text NOT NULL,
  provider text NOT NULL DEFAULT 'mock'::text,
  status text NOT NULL,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  input_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_payload jsonb,
  before_state jsonb,
  after_state jsonb,
  error_message text,
  tokens_used integer,
  cost_estimate numeric,
  mock_mode boolean NOT NULL DEFAULT false,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  model text,
  prompt_version text,
  source_fingerprint text,
  CONSTRAINT aicrm_enrichment_runs_job_type_check CHECK ((job_type = ANY (ARRAY['company_summary'::text, 'revenue_estimate'::text, 'employee_estimate'::text, 'category_classification'::text, 'buying_group_detection'::text, 'contact_role_recommendation'::text, 'website_discovery'::text, 'linkedin_discovery'::text, 'duplicate_detection'::text, 'score_explanation'::text, 'next_action_recommendation'::text, 'campaign_recommendation'::text, 'full_account_enrichment'::text]))),
  CONSTRAINT aicrm_enrichment_runs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text, 'mock_completed'::text]))),
  CONSTRAINT aicrm_enrichment_runs_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_enrichment_runs_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_enrichment_runs_enrichment_job_id_fkey FOREIGN KEY (enrichment_job_id) REFERENCES aicrm_ai_enrichment_jobs(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_enrichment_runs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_enrichment_runs_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_enrichment_runs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_execution_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  queue_item_id uuid,
  account_id uuid,
  account_name text,
  contact_id uuid,
  contact_name text,
  opportunity_id uuid,
  opportunity_title text,
  action_type text NOT NULL,
  recommendation text,
  result text,
  notes text,
  confidence numeric NOT NULL DEFAULT 0,
  estimated_revenue_impact numeric NOT NULL DEFAULT 0,
  completed boolean NOT NULL DEFAULT false,
  ignored boolean NOT NULL DEFAULT false,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_execution_history_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_execution_history_estimated_revenue_impact_check CHECK ((estimated_revenue_impact >= (0)::numeric)),
  CONSTRAINT aicrm_execution_history_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_execution_history_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_execution_history_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_execution_history_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_execution_history_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_execution_history_queue_item_id_fkey FOREIGN KEY (queue_item_id) REFERENCES aicrm_daily_execution_queue(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_execution_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_forecasts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  business_unit_name text,
  brand_id uuid,
  brand_name text,
  product_id uuid,
  product_name text,
  province text,
  territory text,
  channel text,
  account_id uuid,
  account_name text,
  salesperson_id uuid,
  salesperson_name text,
  campaign_id uuid,
  campaign_name text,
  period_type text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  projected_revenue numeric NOT NULL DEFAULT 0,
  weighted_revenue numeric NOT NULL DEFAULT 0,
  best_case numeric NOT NULL DEFAULT 0,
  expected_case numeric NOT NULL DEFAULT 0,
  worst_case numeric NOT NULL DEFAULT 0,
  confidence numeric NOT NULL DEFAULT 0,
  forecast_status text NOT NULL DEFAULT 'on_track'::text,
  reasoning text NOT NULL DEFAULT ''::text,
  supporting_metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_forecasts_best_case_check CHECK ((best_case >= (0)::numeric)),
  CONSTRAINT aicrm_forecasts_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_forecasts_expected_case_check CHECK ((expected_case >= (0)::numeric)),
  CONSTRAINT aicrm_forecasts_forecast_status_check CHECK ((forecast_status = ANY (ARRAY['on_track'::text, 'at_risk'::text, 'upside'::text, 'watch'::text]))),
  CONSTRAINT aicrm_forecasts_period_type_check CHECK ((period_type = ANY (ARRAY['weekly'::text, 'monthly'::text, 'quarterly'::text, 'yearly'::text]))),
  CONSTRAINT aicrm_forecasts_projected_revenue_check CHECK ((projected_revenue >= (0)::numeric)),
  CONSTRAINT aicrm_forecasts_weighted_revenue_check CHECK ((weighted_revenue >= (0)::numeric)),
  CONSTRAINT aicrm_forecasts_worst_case_check CHECK ((worst_case >= (0)::numeric)),
  CONSTRAINT aicrm_forecasts_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_forecasts_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES aicrm_brands(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_forecasts_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_forecasts_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES aicrm_outreach_campaigns(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_forecasts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_forecasts_product_id_fkey FOREIGN KEY (product_id) REFERENCES aicrm_products(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_forecasts_salesperson_id_fkey FOREIGN KEY (salesperson_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_forecasts_pkey PRIMARY KEY (id)
);

-- =========================
-- TABLES: aicrm_g* through aicrm_z*
-- =========================

CREATE TABLE IF NOT EXISTS public.aicrm_graph_edges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  from_node_id uuid NOT NULL,
  to_node_id uuid NOT NULL,
  relationship_type text NOT NULL,
  strength numeric(5,2) NOT NULL DEFAULT 0,
  confidence numeric(5,2) NOT NULL DEFAULT 0,
  source text NOT NULL DEFAULT 'system'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_graph_edges_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_graph_edges_relationship_type_check CHECK ((relationship_type = ANY (ARRAY['OWNS'::text, 'SELLS'::text, 'REPRESENTS'::text, 'WORKS_FOR'::text, 'WORKED_FOR'::text, 'SPECIFIES'::text, 'PURCHASES'::text, 'BELONGS_TO'::text, 'COMPETES_WITH'::text, 'REFERRED'::text, 'ATTENDED'::text, 'INFLUENCES'::text, 'CONNECTED_TO'::text]))),
  CONSTRAINT aicrm_graph_edges_strength_check CHECK (((strength >= (0)::numeric) AND (strength <= (100)::numeric))),
  CONSTRAINT aicrm_graph_edges_from_node_id_fkey FOREIGN KEY (from_node_id) REFERENCES aicrm_graph_nodes(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_graph_edges_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_graph_edges_to_node_id_fkey FOREIGN KEY (to_node_id) REFERENCES aicrm_graph_nodes(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_graph_edges_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_graph_nodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  node_type text NOT NULL,
  entity_id uuid,
  entity_type text,
  label text NOT NULL,
  description text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_graph_nodes_node_type_check CHECK ((node_type = ANY (ARRAY['Organization'::text, 'Business Unit'::text, 'Brand'::text, 'Product'::text, 'Company'::text, 'Person'::text, 'Channel'::text, 'Buying Group'::text, 'Project'::text, 'Territory'::text, 'Campaign'::text, 'Opportunity'::text, 'Meeting'::text, 'Document'::text, 'Relationship'::text]))),
  CONSTRAINT aicrm_graph_nodes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_graph_nodes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_import_mappings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  import_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  source_column text NOT NULL,
  target_entity text NOT NULL,
  target_field text NOT NULL,
  field_type aicrm_custom_field_type,
  is_required boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_import_mappings_target_entity_check CHECK ((target_entity = ANY (ARRAY['account'::text, 'contact'::text, 'custom_account'::text]))),
  CONSTRAINT aicrm_import_mappings_import_id_fkey FOREIGN KEY (import_id) REFERENCES aicrm_imports(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_import_mappings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_import_mappings_pkey PRIMARY KEY (id),
  CONSTRAINT aicrm_import_mappings_import_id_source_column_key UNIQUE (import_id, source_column)
);

CREATE TABLE IF NOT EXISTS public.aicrm_import_rows (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  import_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  row_number integer NOT NULL,
  source_data jsonb NOT NULL,
  mapped_data jsonb,
  target_account_id uuid,
  target_contact_id uuid,
  status aicrm_import_row_status NOT NULL DEFAULT 'pending'::aicrm_import_row_status,
  validation_errors _text[] NOT NULL DEFAULT '{}'::text[],
  duplicate_flags _text[] NOT NULL DEFAULT '{}'::text[],
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_import_rows_row_number_check CHECK ((row_number > 0)),
  CONSTRAINT aicrm_import_rows_import_id_fkey FOREIGN KEY (import_id) REFERENCES aicrm_imports(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_import_rows_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_import_rows_target_account_id_fkey FOREIGN KEY (target_account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_import_rows_target_contact_id_fkey FOREIGN KEY (target_contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_import_rows_pkey PRIMARY KEY (id),
  CONSTRAINT aicrm_import_rows_import_id_row_number_key UNIQUE (import_id, row_number)
);

CREATE TABLE IF NOT EXISTS public.aicrm_imports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  source_type aicrm_import_source NOT NULL,
  source_sheet text,
  file_name text NOT NULL,
  file_hash text,
  import_status aicrm_import_status NOT NULL DEFAULT 'queued'::aicrm_import_status,
  total_rows integer NOT NULL DEFAULT 0,
  accepted_rows integer NOT NULL DEFAULT 0,
  rejected_rows integer NOT NULL DEFAULT 0,
  processed_rows integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_message text,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_imports_accepted_rows_check CHECK ((accepted_rows >= 0)),
  CONSTRAINT aicrm_imports_processed_rows_check CHECK ((processed_rows >= 0)),
  CONSTRAINT aicrm_imports_rejected_rows_check CHECK ((rejected_rows >= 0)),
  CONSTRAINT aicrm_imports_total_rows_check CHECK ((total_rows >= 0)),
  CONSTRAINT aicrm_imports_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_imports_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_imports_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_kpis (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  name text NOT NULL,
  kpi_key text NOT NULL,
  kpi_category text NOT NULL DEFAULT 'operational'::text,
  kpi_type text NOT NULL DEFAULT 'numeric'::text,
  description text,
  target_value numeric,
  formula jsonb NOT NULL DEFAULT '{}'::jsonb,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_kpis_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_kpis_kpi_type_check CHECK ((kpi_type = ANY (ARRAY['numeric'::text, 'percentage'::text, 'currency'::text, 'yes_no'::text, 'calculated'::text, 'ai_generated'::text]))),
  CONSTRAINT aicrm_kpis_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_kpis_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_kpis_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_market_connectors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  provider text NOT NULL,
  display_name text NOT NULL,
  active boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'disabled'::text,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_run_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_market_connectors_status_check CHECK ((status = ANY (ARRAY['disabled'::text, 'configured'::text, 'ready'::text, 'running'::text, 'error'::text]))),
  CONSTRAINT aicrm_market_connectors_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_connectors_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_market_coverage (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  territory_id uuid,
  territory_name text NOT NULL,
  territory_type text NOT NULL,
  coverage_dimension text NOT NULL DEFAULT 'territory'::text,
  country text,
  province text,
  region text,
  city text,
  postal_area text,
  product_id uuid,
  product_name text,
  channel text,
  total_accounts integer NOT NULL DEFAULT 0,
  researched_accounts integer NOT NULL DEFAULT 0,
  contacted_accounts integer NOT NULL DEFAULT 0,
  qualified_accounts integer NOT NULL DEFAULT 0,
  active_opportunities integer NOT NULL DEFAULT 0,
  won_accounts integer NOT NULL DEFAULT 0,
  lost_accounts integer NOT NULL DEFAULT 0,
  coverage_percentage numeric(5,2) NOT NULL DEFAULT 0,
  potential_revenue numeric NOT NULL DEFAULT 0,
  actual_revenue numeric NOT NULL DEFAULT 0,
  remaining_opportunity numeric NOT NULL DEFAULT 0,
  white_space_score numeric(5,2) NOT NULL DEFAULT 0,
  territory_health_score numeric(5,2) NOT NULL DEFAULT 0,
  market_share_estimate numeric(5,2) NOT NULL DEFAULT 0,
  growth_potential numeric(5,2) NOT NULL DEFAULT 0,
  confidence numeric(5,2) NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_calculated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_market_coverage_active_opportunities_check CHECK ((active_opportunities >= 0)),
  CONSTRAINT aicrm_market_coverage_actual_revenue_check CHECK ((actual_revenue >= (0)::numeric)),
  CONSTRAINT aicrm_market_coverage_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_market_coverage_contacted_accounts_check CHECK ((contacted_accounts >= 0)),
  CONSTRAINT aicrm_market_coverage_coverage_dimension_check CHECK ((coverage_dimension = ANY (ARRAY['territory'::text, 'product'::text, 'channel'::text]))),
  CONSTRAINT aicrm_market_coverage_coverage_percentage_check CHECK (((coverage_percentage >= (0)::numeric) AND (coverage_percentage <= (100)::numeric))),
  CONSTRAINT aicrm_market_coverage_growth_potential_check CHECK (((growth_potential >= (0)::numeric) AND (growth_potential <= (100)::numeric))),
  CONSTRAINT aicrm_market_coverage_lost_accounts_check CHECK ((lost_accounts >= 0)),
  CONSTRAINT aicrm_market_coverage_market_share_estimate_check CHECK (((market_share_estimate >= (0)::numeric) AND (market_share_estimate <= (100)::numeric))),
  CONSTRAINT aicrm_market_coverage_potential_revenue_check CHECK ((potential_revenue >= (0)::numeric)),
  CONSTRAINT aicrm_market_coverage_qualified_accounts_check CHECK ((qualified_accounts >= 0)),
  CONSTRAINT aicrm_market_coverage_remaining_opportunity_check CHECK ((remaining_opportunity >= (0)::numeric)),
  CONSTRAINT aicrm_market_coverage_researched_accounts_check CHECK ((researched_accounts >= 0)),
  CONSTRAINT aicrm_market_coverage_territory_health_score_check CHECK (((territory_health_score >= (0)::numeric) AND (territory_health_score <= (100)::numeric))),
  CONSTRAINT aicrm_market_coverage_total_accounts_check CHECK ((total_accounts >= 0)),
  CONSTRAINT aicrm_market_coverage_white_space_score_check CHECK (((white_space_score >= (0)::numeric) AND (white_space_score <= (100)::numeric))),
  CONSTRAINT aicrm_market_coverage_won_accounts_check CHECK ((won_accounts >= 0)),
  CONSTRAINT aicrm_market_coverage_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_coverage_product_id_fkey FOREIGN KEY (product_id) REFERENCES aicrm_products(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_market_coverage_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES aicrm_territories(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_market_coverage_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_market_discovery_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  watchlist_id uuid,
  source text NOT NULL,
  source_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  company_name text NOT NULL,
  legal_name text,
  website text,
  province text,
  country text,
  industry text,
  suggested_category text,
  suggested_channel text,
  suggested_products jsonb NOT NULL DEFAULT '[]'::jsonb,
  estimated_revenue numeric,
  duplicate_likelihood numeric NOT NULL DEFAULT 0,
  confidence numeric NOT NULL DEFAULT 0,
  review_status text NOT NULL DEFAULT 'pending'::text,
  account_id uuid,
  review_note text,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_market_discovery_queue_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_market_discovery_queue_duplicate_likelihood_check CHECK (((duplicate_likelihood >= (0)::numeric) AND (duplicate_likelihood <= (100)::numeric))),
  CONSTRAINT aicrm_market_discovery_queue_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'merged'::text, 'review_later'::text]))),
  CONSTRAINT aicrm_market_discovery_queue_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_market_discovery_queue_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_discovery_queue_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_market_discovery_queue_watchlist_id_fkey FOREIGN KEY (watchlist_id) REFERENCES aicrm_market_watchlists(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_market_discovery_queue_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_market_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  event_type text NOT NULL,
  event_title text NOT NULL,
  event_summary text,
  event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  source text,
  confidence numeric NOT NULL DEFAULT 0,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_market_events_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_market_events_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_market_refresh_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  reason text NOT NULL,
  priority integer NOT NULL DEFAULT 50,
  status text NOT NULL DEFAULT 'pending'::text,
  stale_ai boolean NOT NULL DEFAULT false,
  stale_score boolean NOT NULL DEFAULT false,
  company_changed boolean NOT NULL DEFAULT false,
  contact_changed boolean NOT NULL DEFAULT false,
  ownership_changed boolean NOT NULL DEFAULT false,
  suggested_at timestamp with time zone NOT NULL DEFAULT now(),
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_market_refresh_queue_priority_check CHECK (((priority >= 0) AND (priority <= 100))),
  CONSTRAINT aicrm_market_refresh_queue_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'completed'::text, 'skipped'::text]))),
  CONSTRAINT aicrm_market_refresh_queue_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_refresh_queue_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_refresh_queue_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_market_refresh_queue_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_market_watchlists (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  province text,
  country text,
  industry text,
  channel text,
  keywords jsonb NOT NULL DEFAULT '[]'::jsonb,
  products_followed jsonb NOT NULL DEFAULT '[]'::jsonb,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_market_watchlists_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_market_watchlists_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_notes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid,
  contact_id uuid,
  opportunity_id uuid,
  body text NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_notes_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_notes_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_notes_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_notes_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_notes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_notes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_opportunities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  product_line_id uuid,
  title text NOT NULL,
  opportunity_value numeric,
  stage text NOT NULL,
  probability numeric,
  expected_close_date timestamp with time zone,
  owner_id uuid,
  notes text,
  status text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_opportunities_opportunity_value_check CHECK (((opportunity_value IS NULL) OR (opportunity_value >= (0)::numeric))),
  CONSTRAINT aicrm_opportunities_probability_check CHECK (((probability IS NULL) OR ((probability >= (0)::numeric) AND (probability <= (100)::numeric)))),
  CONSTRAINT aicrm_opportunities_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_opportunities_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_opportunities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_opportunities_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_opportunities_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_opportunity_health (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  account_name text NOT NULL,
  opportunity_id uuid NOT NULL,
  opportunity_title text NOT NULL,
  health_score numeric NOT NULL DEFAULT 0,
  health_status text NOT NULL DEFAULT 'Needs Attention'::text,
  reasoning text,
  ai_comment text,
  last_calculated_at timestamp with time zone,
  source text NOT NULL DEFAULT 'system'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_opportunity_health_health_score_check CHECK (((health_score >= (0)::numeric) AND (health_score <= (100)::numeric))),
  CONSTRAINT aicrm_opportunity_health_health_status_check CHECK ((health_status = ANY (ARRAY['Healthy'::text, 'Needs Attention'::text, 'High Risk'::text, 'Critical'::text]))),
  CONSTRAINT aicrm_opportunity_health_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_opportunity_health_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_opportunity_health_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_opportunity_health_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_opportunity_timelines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid,
  opportunity_id uuid NOT NULL,
  event_type text NOT NULL,
  event_label text NOT NULL,
  event_summary text,
  ai_comment text,
  source text NOT NULL DEFAULT 'system'::text,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_opportunity_timelines_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_opportunity_timelines_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_opportunity_timelines_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_opportunity_timelines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_opportunity_timelines_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_organization_settings (
  organization_id uuid NOT NULL,
  organization_profile jsonb NOT NULL DEFAULT '{}'::jsonb,
  industry text,
  country text NOT NULL DEFAULT 'CA'::text,
  currency text NOT NULL DEFAULT 'CAD'::text,
  timezone text NOT NULL DEFAULT 'America/Toronto'::text,
  language text NOT NULL DEFAULT 'en'::text,
  ai_enabled boolean NOT NULL DEFAULT true,
  default_territory text,
  branding jsonb NOT NULL DEFAULT '{}'::jsonb,
  default_business_unit_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  execution_score_weights jsonb NOT NULL DEFAULT '{}'::jsonb,
  forecasting_weights jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT aicrm_organization_settings_default_business_unit_fk FOREIGN KEY (default_business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_organization_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_organization_settings_pkey PRIMARY KEY (organization_id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_outcomes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid,
  contact_id uuid,
  opportunity_id uuid,
  opportunity_title text,
  product_id uuid,
  product_name text,
  campaign_id uuid,
  campaign_name text,
  relationship_id uuid,
  recommendation_type text NOT NULL DEFAULT 'general'::text,
  recommendation text NOT NULL,
  action_taken text,
  completed boolean NOT NULL DEFAULT false,
  ignored boolean NOT NULL DEFAULT false,
  delayed boolean NOT NULL DEFAULT false,
  successful boolean NOT NULL DEFAULT false,
  unsuccessful boolean NOT NULL DEFAULT false,
  revenue numeric NOT NULL DEFAULT 0,
  territory text,
  province text,
  channel text,
  confidence numeric NOT NULL DEFAULT 0,
  outcome text NOT NULL DEFAULT 'unknown'::text,
  reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid DEFAULT auth.uid(),
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_outcomes_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_outcomes_revenue_check CHECK ((revenue >= (0)::numeric)),
  CONSTRAINT aicrm_outcomes_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outcomes_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES aicrm_outreach_campaigns(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outcomes_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outcomes_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outcomes_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outcomes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_outcomes_product_id_fkey FOREIGN KEY (product_id) REFERENCES aicrm_products(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outcomes_relationship_id_fkey FOREIGN KEY (relationship_id) REFERENCES aicrm_relationships(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outcomes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_outreach_campaigns (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  campaign_type text NOT NULL,
  product_line_id uuid,
  status text NOT NULL DEFAULT 'draft'::text,
  description text,
  target_category text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_outreach_campaigns_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'archived'::text]))),
  CONSTRAINT aicrm_outreach_campaigns_type_check CHECK ((campaign_type = ANY (ARRAY['Appliance Dealer'::text, 'Kitchen & Bath'::text, 'Cabinet Dealer'::text, 'Builder - Single Family'::text, 'Builder - Multi Family'::text, 'Architect'::text, 'Interior Designer'::text, 'Developer'::text, 'Distributor'::text, 'National Retailer'::text, 'Buying Group'::text]))),
  CONSTRAINT aicrm_outreach_campaigns_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outreach_campaigns_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_outreach_campaigns_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outreach_campaigns_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_outreach_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  enrollment_id uuid NOT NULL,
  account_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  campaign_id uuid NOT NULL,
  sequence_step_id uuid,
  subject text,
  body_snapshot text,
  status text NOT NULL DEFAULT 'draft'::text,
  approval_status text NOT NULL DEFAULT 'pending'::text,
  provider_message_id text,
  sent_at timestamp with time zone,
  eligibility_status text,
  eligibility_reason text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_outreach_messages_approval_status_check CHECK ((approval_status = ANY (ARRAY['not_required'::text, 'pending'::text, 'approved'::text, 'rejected'::text]))),
  CONSTRAINT aicrm_outreach_messages_eligibility_status_check CHECK (((eligibility_status IS NULL) OR (eligibility_status = ANY (ARRAY['eligible'::text, 'review_required'::text, 'blocked'::text])))),
  CONSTRAINT aicrm_outreach_messages_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending_approval'::text, 'approved'::text, 'queued'::text, 'sent'::text, 'failed'::text, 'cancelled'::text]))),
  CONSTRAINT aicrm_outreach_messages_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_outreach_messages_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES aicrm_outreach_campaigns(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_outreach_messages_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_outreach_messages_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outreach_messages_enrollment_id_fkey FOREIGN KEY (enrollment_id) REFERENCES aicrm_sequence_enrollments(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_outreach_messages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_outreach_messages_sequence_step_id_fkey FOREIGN KEY (sequence_step_id) REFERENCES aicrm_sequence_steps(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outreach_messages_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_outreach_messages_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_partner_organizations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  organization_name text NOT NULL,
  business_units _text[] NOT NULL DEFAULT '{}'::text[],
  industries _text[] NOT NULL DEFAULT '{}'::text[],
  regions _text[] NOT NULL DEFAULT '{}'::text[],
  capabilities _text[] NOT NULL DEFAULT '{}'::text[],
  products_represented _text[] NOT NULL DEFAULT '{}'::text[],
  services _text[] NOT NULL DEFAULT '{}'::text[],
  public_summary text,
  website text,
  status text NOT NULL DEFAULT 'active'::text,
  public_visible boolean NOT NULL DEFAULT false,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_partner_organizations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'pending'::text, 'suspended'::text, 'archived'::text]))),
  CONSTRAINT aicrm_partner_organizations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_partner_organizations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_partnerships (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  partner_organization_id uuid NOT NULL,
  partnership_type text NOT NULL DEFAULT 'collaboration'::text,
  status text NOT NULL DEFAULT 'pending'::text,
  permission_level text NOT NULL DEFAULT 'view'::text,
  shared_permissions _text[] NOT NULL DEFAULT '{}'::text[],
  notes text,
  started_at timestamp with time zone,
  expires_at timestamp with time zone,
  revoked_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_partnerships_permission_level_check CHECK ((permission_level = ANY (ARRAY['view'::text, 'comment'::text, 'collaborate'::text, 'contribute'::text, 'admin'::text]))),
  CONSTRAINT aicrm_partnerships_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'expired'::text, 'declined'::text]))),
  CONSTRAINT aicrm_partnerships_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_partnerships_partner_organization_id_fkey FOREIGN KEY (partner_organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_partnerships_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_people (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  first_name text NOT NULL,
  last_name text NOT NULL,
  preferred_name text,
  email text,
  phone text,
  linkedin_url text,
  notes text,
  relationship_strength numeric NOT NULL DEFAULT 50,
  influence_score numeric NOT NULL DEFAULT 50,
  buying_authority boolean NOT NULL DEFAULT false,
  current_company_id uuid,
  current_title text,
  current_department text,
  relationship_score numeric NOT NULL DEFAULT 0,
  relationship_score_basis text,
  insight_summary text,
  insight_reasoning text,
  insight_confidence numeric NOT NULL DEFAULT 0,
  best_introduction_path text,
  source text NOT NULL DEFAULT 'manual'::text,
  last_company_change_at timestamp with time zone,
  last_scored_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_people_influence_score_check CHECK (((influence_score >= (0)::numeric) AND (influence_score <= (100)::numeric))),
  CONSTRAINT aicrm_people_insight_confidence_check CHECK (((insight_confidence >= (0)::numeric) AND (insight_confidence <= (100)::numeric))),
  CONSTRAINT aicrm_people_relationship_score_check CHECK (((relationship_score >= (0)::numeric) AND (relationship_score <= (100)::numeric))),
  CONSTRAINT aicrm_people_relationship_strength_check CHECK (((relationship_strength >= (0)::numeric) AND (relationship_strength <= (100)::numeric))),
  CONSTRAINT aicrm_people_current_company_id_fkey FOREIGN KEY (current_company_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_people_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_people_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_pipeline_stages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  color text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_pipeline_stages_sort_order_check CHECK ((sort_order >= 0)),
  CONSTRAINT aicrm_pipeline_stages_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_pipeline_stages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_pipeline_stages_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_pipeline_stages_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  brand text NOT NULL,
  category text,
  description text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  business_unit_id uuid,
  brand_id uuid,
  archived_at timestamp with time zone,
  CONSTRAINT aicrm_products_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES aicrm_brands(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_products_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_products_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_products_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_referrals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  partnership_id uuid,
  referral_type text NOT NULL,
  origin_organization_id uuid NOT NULL,
  destination_organization_id uuid NOT NULL,
  origin_account_id uuid,
  destination_account_id uuid,
  origin_contact_id uuid,
  destination_contact_id uuid,
  opportunity_id uuid,
  status text NOT NULL DEFAULT 'pending'::text,
  revenue numeric(14,2) NOT NULL DEFAULT 0,
  commission numeric(14,2) NOT NULL DEFAULT 0,
  outcome text,
  notes text,
  audit_trail jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_referrals_referral_type_check CHECK ((referral_type = ANY (ARRAY['lead_referral'::text, 'opportunity_referral'::text, 'partner_referral'::text, 'project_referral'::text, 'builder_referral'::text, 'designer_referral'::text, 'dealer_referral'::text]))),
  CONSTRAINT aicrm_referrals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'rejected'::text, 'converted'::text, 'closed'::text, 'revoked'::text]))),
  CONSTRAINT aicrm_referrals_destination_organization_id_fkey FOREIGN KEY (destination_organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_referrals_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_referrals_origin_organization_id_fkey FOREIGN KEY (origin_organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_referrals_partnership_id_fkey FOREIGN KEY (partnership_id) REFERENCES aicrm_partnerships(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_referrals_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_relationships (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  person_id uuid NOT NULL,
  related_person_id uuid NOT NULL,
  account_id uuid,
  relationship_type text NOT NULL,
  relationship_strength numeric NOT NULL DEFAULT 50,
  first_met date,
  last_interaction date,
  trust_level text NOT NULL DEFAULT 'medium'::text,
  source text NOT NULL DEFAULT 'manual'::text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_relationships_relationship_strength_check CHECK (((relationship_strength >= (0)::numeric) AND (relationship_strength <= (100)::numeric))),
  CONSTRAINT aicrm_relationships_relationship_type_check CHECK ((relationship_type = ANY (ARRAY['colleague'::text, 'former colleague'::text, 'customer'::text, 'supplier'::text, 'referral'::text, 'partner'::text, 'consultant'::text, 'influencer'::text]))),
  CONSTRAINT aicrm_relationships_trust_level_check CHECK ((trust_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'very_high'::text]))),
  CONSTRAINT aicrm_relationships_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_relationships_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_relationships_person_id_fkey FOREIGN KEY (person_id) REFERENCES aicrm_people(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_relationships_related_person_id_fkey FOREIGN KEY (related_person_id) REFERENCES aicrm_people(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_relationships_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_route_plans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  title text NOT NULL,
  origin_city text,
  origin_province text,
  destination_city text,
  destination_province text,
  distance_km numeric(10,2),
  appointment_count integer NOT NULL DEFAULT 0,
  dealer_visits integer NOT NULL DEFAULT 0,
  builder_visits integer NOT NULL DEFAULT 0,
  travel_date date,
  notes text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'draft'::text,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_route_plans_appointment_count_check CHECK ((appointment_count >= 0)),
  CONSTRAINT aicrm_route_plans_builder_visits_check CHECK ((builder_visits >= 0)),
  CONSTRAINT aicrm_route_plans_dealer_visits_check CHECK ((dealer_visits >= 0)),
  CONSTRAINT aicrm_route_plans_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'planned'::text, 'completed'::text, 'cancelled'::text]))),
  CONSTRAINT aicrm_route_plans_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_route_plans_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_route_plans_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_sales_motions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  name text NOT NULL,
  description text,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_sales_motions_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_sales_motions_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sales_motions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sales_motions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_sales_playbooks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  business_unit_id uuid,
  channel_id uuid,
  product_id uuid,
  name text NOT NULL,
  target_channel text NOT NULL,
  target_product text NOT NULL,
  buyer_persona text NOT NULL,
  meeting_objective text NOT NULL,
  qualification_questions jsonb NOT NULL DEFAULT '[]'::jsonb,
  objections jsonb NOT NULL DEFAULT '[]'::jsonb,
  responses jsonb NOT NULL DEFAULT '[]'::jsonb,
  recommended_collateral jsonb NOT NULL DEFAULT '[]'::jsonb,
  follow_up_cadence text,
  default_agenda jsonb NOT NULL DEFAULT '[]'::jsonb,
  active boolean NOT NULL DEFAULT true,
  is_default boolean NOT NULL DEFAULT false,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_sales_playbooks_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_sales_playbooks_business_unit_id_fkey FOREIGN KEY (business_unit_id) REFERENCES aicrm_business_units(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sales_playbooks_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES aicrm_channels(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sales_playbooks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sales_playbooks_product_id_fkey FOREIGN KEY (product_id) REFERENCES aicrm_products(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sales_playbooks_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_saved_views (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  created_by uuid DEFAULT auth.uid(),
  view_name text NOT NULL,
  view_entity text NOT NULL DEFAULT 'accounts'::text,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_saved_views_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_saved_views_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_saved_views_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_sequence_enrollments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  campaign_id uuid NOT NULL,
  current_step integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'active'::text,
  enrolled_at timestamp with time zone NOT NULL DEFAULT now(),
  last_contacted_at timestamp with time zone,
  next_action_at timestamp with time zone,
  eligibility_status text,
  eligibility_reason text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  deal_id uuid,
  sequence_id uuid,
  paused_at timestamp with time zone,
  completed_at timestamp with time zone,
  unenrolled_at timestamp with time zone,
  unenroll_reason text,
  CONSTRAINT aicrm_sequence_enrollments_eligibility_status_check CHECK (((eligibility_status IS NULL) OR (eligibility_status = ANY (ARRAY['eligible'::text, 'review_required'::text, 'blocked'::text])))),
  CONSTRAINT aicrm_sequence_enrollments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'completed'::text, 'replied'::text, 'bounced'::text, 'unsubscribed'::text, 'cancelled'::text]))),
  CONSTRAINT aicrm_sequence_enrollments_step_positive CHECK ((current_step >= 1)),
  CONSTRAINT aicrm_sequence_enrollments_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sequence_enrollments_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES aicrm_outreach_campaigns(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sequence_enrollments_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sequence_enrollments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sequence_enrollments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sequence_enrollments_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sequence_enrollments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_sequence_steps (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  campaign_id uuid NOT NULL,
  step_number integer NOT NULL,
  delay_days integer NOT NULL DEFAULT 0,
  channel text NOT NULL,
  subject_template text,
  body_template text,
  purpose text,
  requires_manual_approval boolean NOT NULL DEFAULT true,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  action_type text DEFAULT 'send'::text,
  template_id uuid,
  CONSTRAINT aicrm_sequence_steps_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'call'::text, 'linkedin'::text, 'task'::text]))),
  CONSTRAINT aicrm_sequence_steps_delay_check CHECK ((delay_days >= 0)),
  CONSTRAINT aicrm_sequence_steps_purpose_check CHECK (((purpose IS NULL) OR (purpose = ANY (ARRAY['intro'::text, 'value'::text, 'proof'::text, 'follow_up'::text, 'break_up'::text, 'nurture'::text, 'value_add'::text, 'close_or_archive'::text, 'post_sale'::text, 'delivery'::text, 're_engagement'::text])))),
  CONSTRAINT aicrm_sequence_steps_step_number_positive CHECK ((step_number >= 1)),
  CONSTRAINT aicrm_sequence_steps_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES aicrm_outreach_campaigns(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sequence_steps_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sequence_steps_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_sequence_steps_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_sequence_steps_pkey PRIMARY KEY (id),
  CONSTRAINT aicrm_sequence_steps_campaign_id_step_number_key UNIQUE (campaign_id, step_number)
);

CREATE TABLE IF NOT EXISTS public.aicrm_shared_market_intelligence (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  partner_organization_id uuid,
  intelligence_type text NOT NULL,
  region text,
  category text,
  channel text,
  summary text NOT NULL,
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  anonymous boolean NOT NULL DEFAULT true,
  visibility_level text NOT NULL DEFAULT 'partner'::text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_shared_market_intelligence_visibility_level_check CHECK ((visibility_level = ANY (ARRAY['partner'::text, 'network'::text, 'public'::text]))),
  CONSTRAINT aicrm_shared_market_intelligence_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_shared_market_intelligence_partner_organization_id_fkey FOREIGN KEY (partner_organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_shared_market_intelligence_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_shared_projects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  partner_organization_id uuid NOT NULL,
  title text NOT NULL,
  project_type text NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  permission_level text NOT NULL DEFAULT 'view'::text,
  shared_permissions _text[] NOT NULL DEFAULT '{}'::text[],
  products _text[] NOT NULL DEFAULT '{}'::text[],
  description text,
  notes text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_shared_projects_permission_level_check CHECK ((permission_level = ANY (ARRAY['view'::text, 'comment'::text, 'collaborate'::text, 'contribute'::text, 'admin'::text]))),
  CONSTRAINT aicrm_shared_projects_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'completed'::text, 'archived'::text]))),
  CONSTRAINT aicrm_shared_projects_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_shared_projects_partner_organization_id_fkey FOREIGN KEY (partner_organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_shared_projects_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_suppression_list (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid,
  contact_id uuid,
  email text,
  reason text,
  source text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_suppression_list_email_or_ref CHECK (((account_id IS NOT NULL) OR (contact_id IS NOT NULL) OR ((email IS NOT NULL) AND (TRIM(BOTH FROM email) <> ''::text)))),
  CONSTRAINT aicrm_suppression_list_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_suppression_list_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_suppression_list_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_suppression_list_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_suppression_list_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_suppression_list_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_tags (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  color text,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_tags_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_tags_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_tags_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_tags_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  account_id uuid NOT NULL,
  contact_id uuid,
  opportunity_id uuid,
  title text NOT NULL,
  description text,
  due_date timestamp with time zone,
  priority text,
  status text NOT NULL DEFAULT 'open'::text,
  owner_id uuid,
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_tasks_status_constraint CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text]))),
  CONSTRAINT aicrm_tasks_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_tasks_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_tasks_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_tasks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_tasks_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aicrm_tasks_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_territories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  parent_id uuid,
  territory_type text NOT NULL,
  name text NOT NULL,
  code text,
  country text NOT NULL DEFAULT 'CA'::text,
  province text,
  region text,
  city text,
  postal_area text,
  active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_territories_display_order_check CHECK ((display_order >= 0)),
  CONSTRAINT aicrm_territories_territory_type_check CHECK ((territory_type = ANY (ARRAY['country'::text, 'province'::text, 'region'::text, 'city'::text, 'postal_area'::text, 'sales_territory'::text]))),
  CONSTRAINT aicrm_territories_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_territories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES aicrm_territories(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_territories_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_territory_heatmaps (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  geography_type text NOT NULL,
  geography_key text NOT NULL,
  country text,
  province text,
  region text,
  city text,
  postal_area text,
  total_accounts integer NOT NULL DEFAULT 0,
  total_opportunities integer NOT NULL DEFAULT 0,
  total_revenue numeric NOT NULL DEFAULT 0,
  product_fit_score numeric(5,2) NOT NULL DEFAULT 0,
  coverage_percentage numeric(5,2) NOT NULL DEFAULT 0,
  forecast_value numeric NOT NULL DEFAULT 0,
  white_space_score numeric(5,2) NOT NULL DEFAULT 0,
  territory_health_score numeric(5,2) NOT NULL DEFAULT 0,
  confidence numeric(5,2) NOT NULL DEFAULT 0,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_calculated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_territory_heatmaps_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (100)::numeric))),
  CONSTRAINT aicrm_territory_heatmaps_coverage_percentage_check CHECK (((coverage_percentage >= (0)::numeric) AND (coverage_percentage <= (100)::numeric))),
  CONSTRAINT aicrm_territory_heatmaps_forecast_value_check CHECK ((forecast_value >= (0)::numeric)),
  CONSTRAINT aicrm_territory_heatmaps_geography_type_check CHECK ((geography_type = ANY (ARRAY['country'::text, 'province'::text, 'region'::text, 'city'::text, 'postal_area'::text]))),
  CONSTRAINT aicrm_territory_heatmaps_product_fit_score_check CHECK (((product_fit_score >= (0)::numeric) AND (product_fit_score <= (100)::numeric))),
  CONSTRAINT aicrm_territory_heatmaps_territory_health_score_check CHECK (((territory_health_score >= (0)::numeric) AND (territory_health_score <= (100)::numeric))),
  CONSTRAINT aicrm_territory_heatmaps_total_accounts_check CHECK ((total_accounts >= 0)),
  CONSTRAINT aicrm_territory_heatmaps_total_opportunities_check CHECK ((total_opportunities >= 0)),
  CONSTRAINT aicrm_territory_heatmaps_total_revenue_check CHECK ((total_revenue >= (0)::numeric)),
  CONSTRAINT aicrm_territory_heatmaps_white_space_score_check CHECK (((white_space_score >= (0)::numeric) AND (white_space_score <= (100)::numeric))),
  CONSTRAINT aicrm_territory_heatmaps_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_territory_heatmaps_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aicrm_training_exchanges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  partner_organization_id uuid NOT NULL,
  training_type text NOT NULL,
  title text NOT NULL,
  learner_name text,
  product_name text,
  certification_name text,
  status text NOT NULL DEFAULT 'pending'::text,
  completion_status text NOT NULL DEFAULT 'pending'::text,
  completed_at timestamp with time zone,
  expires_at timestamp with time zone,
  notes text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aicrm_training_exchanges_completion_status_check CHECK ((completion_status = ANY (ARRAY['pending'::text, 'completed'::text, 'expired'::text, 'paused'::text, 'cancelled'::text]))),
  CONSTRAINT aicrm_training_exchanges_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'completed'::text, 'expired'::text, 'paused'::text, 'cancelled'::text]))),
  CONSTRAINT aicrm_training_exchanges_training_type_check CHECK ((training_type = ANY (ARRAY['manufacturer_training'::text, 'distributor_training'::text, 'dealer_training'::text, 'sales_certification'::text, 'product_certification'::text]))),
  CONSTRAINT aicrm_training_exchanges_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_training_exchanges_partner_organization_id_fkey FOREIGN KEY (partner_organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aicrm_training_exchanges_pkey PRIMARY KEY (id)
);

-- =========================
-- TABLES: aiq_* through az*
-- =========================

CREATE TABLE IF NOT EXISTS public.aiq_distributors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  distributor_type text NOT NULL DEFAULT 'importer_distributor'::text,
  country text NOT NULL DEFAULT 'CA'::text,
  headquarters text,
  provinces_states _text[] DEFAULT '{}'::text[],
  brands_carried _text[] DEFAULT '{}'::text[],
  coverage_notes text,
  website text,
  founded text,
  member_outlet_count text,
  annual_sales_notes text,
  status text NOT NULL DEFAULT 'active'::text,
  is_buying_group boolean DEFAULT false,
  notes text,
  intel_company_id uuid,
  logo_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT aiq_distributors_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_product_versions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  product_id uuid NOT NULL,
  version_number integer NOT NULL,
  snapshot jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT aiq_product_versions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aiq_product_versions_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT aiq_product_versions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  manufacturer_name text NOT NULL,
  brand_name text NOT NULL,
  product_line text,
  category text NOT NULL,
  series text,
  model text NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  launch_date date,
  discontinued_date date,
  msrp numeric(12,2),
  country_availability _text[] NOT NULL DEFAULT '{}'::text[],
  product_family text,
  short_description text,
  public_visible boolean NOT NULL DEFAULT false,
  approval_status text NOT NULL DEFAULT 'draft'::text,
  version_number integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  brand_id uuid,
  manufacturer_id uuid,
  source_type text NOT NULL DEFAULT 'internal'::text,
  source_reference text,
  source_confidence numeric(5,2),
  source_extracted_at timestamp with time zone,
  source_review_status text NOT NULL DEFAULT 'not_required'::text,
  source_reviewed_by uuid,
  source_reviewed_at timestamp with time zone,
  published_at timestamp with time zone,
  unpublished_at timestamp with time zone,
  created_by uuid,
  updated_by uuid,
  long_description text,
  features_html text,
  upc text,
  ean text,
  gtin text,
  finish text,
  color text,
  color_family text,
  energy_star boolean DEFAULT false,
  ada_compliant boolean DEFAULT false,
  made_in text,
  weight_lbs numeric,
  width_inches numeric,
  height_inches numeric,
  depth_inches numeric,
  map_price numeric,
  dealer_cost numeric,
  freight_class text,
  ships_ltl boolean DEFAULT false,
  lead_time_days integer,
  min_order_qty integer DEFAULT 1,
  sale_price numeric,
  lowest_price numeric,
  lowest_price_source text,
  price_currency text DEFAULT 'CAD'::text,
  price_checked_at timestamp with time zone,
  condition_flags _text[] DEFAULT '{}'::text[],
  is_discontinued boolean DEFAULT false,
  is_clearance boolean DEFAULT false,
  is_end_of_life boolean DEFAULT false,
  is_open_box boolean DEFAULT false,
  is_refurbished boolean DEFAULT false,
  replacement_model text,
  condition_notes text,
  specs_json jsonb DEFAULT '{}'::jsonb,
  available_colors jsonb DEFAULT '[]'::jsonb,
  capacity_cu_ft numeric,
  voltage text,
  amperage numeric,
  wattage numeric,
  frequency_hz text,
  installation_type text,
  depth_with_handles numeric,
  depth_without_handles numeric,
  market text NOT NULL DEFAULT 'CA'::text,
  CONSTRAINT aiq_products_approval_status_check CHECK ((approval_status = ANY (ARRAY['draft'::text, 'pending_review'::text, 'approved'::text, 'rejected'::text]))),
  CONSTRAINT aiq_products_source_confidence_check CHECK (((source_confidence IS NULL) OR ((source_confidence >= (0)::numeric) AND (source_confidence <= (100)::numeric)))),
  CONSTRAINT aiq_products_source_review_status_check CHECK ((source_review_status = ANY (ARRAY['not_required'::text, 'pending'::text, 'accepted'::text, 'rejected'::text, 'needs_review'::text, 'approved'::text]))),
  CONSTRAINT aiq_products_source_type_check CHECK ((source_type = ANY (ARRAY['raw_import'::text, 'ai_extracted'::text, 'ai_suggested'::text, 'manufacturer_submitted'::text, 'aiq_reviewed'::text, 'internal'::text, 'web_scrape'::text]))),
  CONSTRAINT aiq_products_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'archived'::text, 'discontinued'::text, 'clearance'::text, 'end_of_life'::text, 'open_box'::text, 'refurbished'::text]))),
  CONSTRAINT aiq_products_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE RESTRICT,
  CONSTRAINT aiq_products_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aiq_products_manufacturer_id_fkey FOREIGN KEY (manufacturer_id) REFERENCES mfr_vendors(id) ON DELETE RESTRICT,
  CONSTRAINT aiq_products_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT aiq_products_source_reviewed_by_fkey FOREIGN KEY (source_reviewed_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aiq_products_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT aiq_products_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_rebate_programs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  program_name text NOT NULL,
  level text NOT NULL,
  country text NOT NULL,
  region text NOT NULL,
  administering_body text,
  program_type text,
  appliance_categories _text[] DEFAULT '{}'::text[],
  rebate_amount_min numeric,
  rebate_amount_max numeric,
  currency text DEFAULT 'USD'::text,
  is_income_qualified boolean DEFAULT false,
  income_qualification_notes text,
  eligible_retailers _text[] DEFAULT '{}'::text[],
  status text NOT NULL DEFAULT 'active'::text,
  valid_from date,
  valid_to date,
  application_url text,
  notes text,
  last_verified_date date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT aiq_rebate_programs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_recalls (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  source text NOT NULL,
  source_recall_id text,
  country text NOT NULL DEFAULT 'US'::text,
  brand_name text NOT NULL,
  manufacturer_name text,
  product_name text,
  model_numbers _text[] DEFAULT '{}'::text[],
  category text,
  recall_date date,
  title text,
  description text,
  hazard text,
  remedy text,
  remedy_options _text[] DEFAULT '{}'::text[],
  units_affected text,
  injury_count integer DEFAULT 0,
  injury_notes text,
  url text NOT NULL,
  is_appliance_related boolean DEFAULT true,
  matched_brand_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  raw_data jsonb,
  last_synced_at timestamp with time zone,
  CONSTRAINT aiq_recalls_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_retailers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  country text NOT NULL DEFAULT 'CA'::text,
  website text,
  parent_company text,
  type text DEFAULT 'retailer'::text,
  specialty text,
  store_count integer,
  headquarters text,
  provinces_states _text[],
  brands_carried _text[],
  exclusive_brands _text[],
  price_tier text,
  delivery_options _text[],
  has_showroom boolean DEFAULT true,
  has_ecommerce boolean DEFAULT true,
  has_installation boolean DEFAULT false,
  has_haul_away boolean DEFAULT false,
  commercial_division boolean DEFAULT false,
  membership_required boolean DEFAULT false,
  founded text,
  status text DEFAULT 'active'::text,
  notes text,
  intel_company_id uuid,
  logo_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  retailer_story text,
  phone text,
  email text,
  key_differentiators _text[],
  service_offerings _text[],
  price_match_policy text,
  financing_options text,
  return_policy text,
  target_customer text,
  competitive_advantage text,
  annual_revenue_estimate text,
  employee_count_estimate text,
  social_media jsonb DEFAULT '{}'::jsonb,
  operating_hours text,
  delivery_radius text,
  design_services boolean DEFAULT false,
  trade_program boolean DEFAULT false,
  CONSTRAINT aiq_retailers_intel_company_id_fkey FOREIGN KEY (intel_company_id) REFERENCES intel_companies(id),
  CONSTRAINT aiq_retailers_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_service_providers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_name text NOT NULL,
  service_type text NOT NULL,
  city text,
  province_state text,
  country text NOT NULL DEFAULT 'CA'::text,
  service_area text,
  phone text,
  email text,
  website text,
  brands_authorized _text[] DEFAULT '{}'::text[],
  brand_ids _uuid[] DEFAULT '{}'::uuid[],
  categories_serviced _text[] DEFAULT '{}'::text[],
  offers_installation boolean DEFAULT false,
  offers_warranty_repair boolean DEFAULT true,
  offers_out_of_warranty boolean DEFAULT true,
  offers_commercial boolean DEFAULT false,
  avg_rating numeric(2,1),
  review_count integer,
  years_in_business integer,
  num_technicians integer,
  certifications _text[],
  status text DEFAULT 'active'::text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT aiq_service_providers_service_type_check CHECK ((service_type = ANY (ARRAY['warranty_service'::text, 'independent'::text, 'factory_certified'::text, 'installer'::text, 'parts_depot'::text]))),
  CONSTRAINT aiq_service_providers_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_vendor_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  brand_name text NOT NULL,
  country text NOT NULL DEFAULT 'US+CA'::text,
  customer_service_phone text,
  customer_service_phone_label text,
  customer_service_hours text,
  service_repair_phone text,
  warranty_phone text,
  trade_distributor_phone text,
  parts_phone text,
  parts_url text,
  support_email text,
  live_chat_url text,
  support_website_url text,
  registration_url text,
  source_url text,
  confidence_level text NOT NULL DEFAULT 'official'::text,
  last_verified_date date NOT NULL DEFAULT CURRENT_DATE,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  service_portal_url text,
  owner_account_portal_url text,
  CONSTRAINT aiq_vendor_contacts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.aiq_warranty_policies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  brand_name text NOT NULL,
  category text NOT NULL DEFAULT 'all'::text,
  country text NOT NULL DEFAULT 'US+CA'::text,
  full_coverage_years numeric NOT NULL,
  full_coverage_notes text,
  component_warranties jsonb DEFAULT '[]'::jsonb,
  registration_required boolean DEFAULT false,
  registration_window_days integer,
  registration_url text,
  certified_install_bonus_notes text,
  extended_warranty_available boolean DEFAULT true,
  extended_warranty_notes text,
  commercial_use_notes text,
  key_exclusions text,
  source_url text,
  last_verified_date date NOT NULL DEFAULT CURRENT_DATE,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT aiq_warranty_policies_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.app_bundles (
  key text NOT NULL,
  content_b64 text NOT NULL,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT app_bundles_pkey PRIMARY KEY (key)
);

CREATE TABLE IF NOT EXISTS public.brand_catalog (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  brand_name text NOT NULL,
  brand_tier text NOT NULL,
  is_active boolean DEFAULT true,
  sort_order integer DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  slug text,
  logo_url text,
  website text,
  parent_company text,
  manufacturer_id uuid,
  country text,
  featured boolean DEFAULT false,
  academy_status text DEFAULT 'none'::text,
  latest_update timestamp with time zone,
  launch_count integer DEFAULT 0,
  training_count integer DEFAULT 0,
  product_count integer DEFAULT 0,
  public_visible boolean DEFAULT true,
  updated_at timestamp with time zone DEFAULT now(),
  canada_website text,
  us_website text,
  canada_email text,
  canada_phone text,
  contact_status text,
  founded_year text,
  headquarters text,
  brand_story text,
  brand_tagline text,
  key_innovations _text[],
  product_categories _text[],
  CONSTRAINT brand_catalog_brand_tier_check CHECK ((brand_tier = ANY (ARRAY['entry'::text, 'mid'::text, 'luxury'::text, 'ultra_luxury'::text]))),
  CONSTRAINT brand_catalog_manufacturer_id_fkey FOREIGN KEY (manufacturer_id) REFERENCES mfr_vendors(id),
  CONSTRAINT brand_catalog_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT brand_catalog_pkey PRIMARY KEY (id),
  CONSTRAINT brand_catalog_organization_id_brand_name_key UNIQUE (organization_id, brand_name)
);

CREATE TABLE IF NOT EXISTS public.brand_map_policies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  brand_name text NOT NULL,
  map_enforced boolean DEFAULT true,
  online_price_display text,
  cart_pricing_allowed boolean,
  map_policy_notes text,
  violation_consequences text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT brand_map_policies_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.brand_training_cards (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  brand_id uuid NOT NULL,
  parent_company text,
  country_of_origin text,
  founded_year text,
  heritage text,
  brand_positioning text,
  core_categories jsonb DEFAULT '[]'::jsonb,
  key_product_lines jsonb DEFAULT '[]'::jsonb,
  known_for text,
  customer_profile text,
  price_position text,
  floor_talking_points jsonb DEFAULT '[]'::jsonb,
  common_objections jsonb DEFAULT '[]'::jsonb,
  competes_with jsonb DEFAULT '[]'::jsonb,
  competitive_advantage text,
  competitive_weakness text,
  status text DEFAULT 'draft'::text,
  version integer DEFAULT 1,
  last_reviewed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  reviewed_by uuid,
  next_review_at timestamp with time zone,
  manufacturer_approved boolean DEFAULT false,
  confidence_score smallint DEFAULT 0,
  source_url text,
  editor_id uuid,
  CONSTRAINT brand_training_cards_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'archived'::text]))),
  CONSTRAINT brand_training_cards_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT brand_training_cards_editor_id_fkey FOREIGN KEY (editor_id) REFERENCES auth.users(id),
  CONSTRAINT brand_training_cards_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT brand_training_cards_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id),
  CONSTRAINT brand_training_cards_pkey PRIMARY KEY (id),
  CONSTRAINT brand_training_cards_organization_id_brand_id_key UNIQUE (organization_id, brand_id)
);

CREATE TABLE IF NOT EXISTS public.budget_nodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  budget_plan_id uuid NOT NULL,
  location_id uuid,
  user_id uuid,
  period_type text NOT NULL,
  period_key text NOT NULL,
  metric_type text NOT NULL,
  metric_subtype text,
  target_value numeric NOT NULL DEFAULT 0,
  pct_of_parent numeric,
  is_manual_override boolean DEFAULT false,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT budget_nodes_period_type_check CHECK ((period_type = ANY (ARRAY['annual'::text, 'quarterly'::text, 'monthly'::text]))),
  CONSTRAINT budget_nodes_budget_plan_id_fkey FOREIGN KEY (budget_plan_id) REFERENCES budget_plans(id) ON DELETE CASCADE,
  CONSTRAINT budget_nodes_location_id_fkey FOREIGN KEY (location_id) REFERENCES org_locations(id),
  CONSTRAINT budget_nodes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT budget_nodes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT budget_nodes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.budget_plans (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  fiscal_year integer NOT NULL,
  plan_name text NOT NULL DEFAULT 'Annual Budget'::text,
  status text NOT NULL DEFAULT 'draft'::text,
  total_revenue_target numeric NOT NULL DEFAULT 0,
  growth_pct numeric,
  base_year integer,
  currency text DEFAULT 'CAD'::text,
  notes text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT budget_plans_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'closed'::text]))),
  CONSTRAINT budget_plans_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT budget_plans_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT budget_plans_pkey PRIMARY KEY (id),
  CONSTRAINT budget_plans_organization_id_fiscal_year_key UNIQUE (organization_id, fiscal_year)
);

CREATE TABLE IF NOT EXISTS public.buying_groups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  country text NOT NULL,
  headquarters text,
  website text,
  description text,
  member_count_estimate integer,
  annual_volume_estimate text,
  services _text[],
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT buying_groups_pkey PRIMARY KEY (id),
  CONSTRAINT buying_groups_name_key UNIQUE (name)
);

-- =========================
-- TABLES: b* through c*
-- =========================

CREATE TABLE IF NOT EXISTS public.cad_bim_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  brand_id uuid,
  brand_name text NOT NULL,
  official_cad_url text,
  official_bim_url text,
  bimobject_url text,
  arcat_url text,
  caddetails_url text,
  bimsmith_url text,
  dealer_portal_url text,
  registration_required boolean NOT NULL DEFAULT false,
  availability_status text NOT NULL DEFAULT 'research_pending'::text,
  formats _text[] NOT NULL DEFAULT '{}'::text[],
  notes text,
  last_verified_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT cad_bim_sources_availability_status_check CHECK ((availability_status = ANY (ARRAY['available'::text, 'partial'::text, 'not_found'::text, 'research_pending'::text, 'login_required'::text]))),
  CONSTRAINT cad_bim_sources_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT cad_bim_sources_pkey PRIMARY KEY (id),
  CONSTRAINT cad_bim_sources_brand_name_key UNIQUE (brand_name)
);

CREATE TABLE IF NOT EXISTS public.communication_audit_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  event_type text NOT NULL,
  event_payload jsonb DEFAULT '{}'::jsonb,
  actor_user_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT communication_audit_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT communication_audit_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.communication_email_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  crm_email_id uuid,
  provider_message_id text,
  from_email text,
  to_email text,
  subject text,
  status text DEFAULT 'sent'::text,
  delivered_at timestamp with time zone,
  opened_at timestamp with time zone,
  clicked_at timestamp with time zone,
  bounced_at timestamp with time zone,
  bounce_reason text,
  complained_at timestamp with time zone,
  open_count integer DEFAULT 0,
  click_count integer DEFAULT 0,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT communication_email_messages_crm_email_id_fkey FOREIGN KEY (crm_email_id) REFERENCES crm_emails(id),
  CONSTRAINT communication_email_messages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT communication_email_messages_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.communication_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  channel text NOT NULL DEFAULT 'email'::text,
  subject_template text,
  body_template text NOT NULL,
  category text DEFAULT 'general'::text,
  merge_fields jsonb DEFAULT '[]'::jsonb,
  is_active boolean DEFAULT true,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT communication_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT communication_templates_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.communication_webhook_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  provider_message_id text,
  event_type text NOT NULL,
  raw_payload jsonb DEFAULT '{}'::jsonb,
  processed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT communication_webhook_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT communication_webhook_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.companies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  display_name text,
  legal_name text,
  industry text,
  website text,
  city text,
  region text,
  country_code text DEFAULT 'CA'::text,
  status company_status NOT NULL DEFAULT 'prospect'::company_status,
  lifecycle_stage lifecycle_stage NOT NULL DEFAULT 'lead'::lifecycle_stage,
  source text,
  custom_fields jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  business_type text,
  main_phone text,
  general_email text,
  billing_address jsonb DEFAULT '{}'::jsonb,
  shipping_addresses jsonb DEFAULT '[]'::jsonb,
  number_of_locations integer DEFAULT 1,
  tax_info jsonb DEFAULT '{}'::jsonb,
  credit_status text DEFAULT 'not_assessed'::text,
  account_terms text,
  assigned_account_manager_id uuid,
  store_territory_owner_id uuid,
  account_classification text DEFAULT 'standard'::text,
  annual_revenue_potential numeric,
  notes text,
  CONSTRAINT companies_assigned_account_manager_id_fkey FOREIGN KEY (assigned_account_manager_id) REFERENCES profiles(id),
  CONSTRAINT companies_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT companies_store_territory_owner_id_fkey FOREIGN KEY (store_territory_owner_id) REFERENCES profiles(id),
  CONSTRAINT companies_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.competitive_cross_reference (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  category text NOT NULL,
  tier text NOT NULL,
  price_range text,
  brand1_id uuid,
  brand1_model text,
  brand1_notes text,
  brand2_id uuid,
  brand2_model text,
  brand2_notes text,
  brand3_id uuid,
  brand3_model text,
  brand3_notes text,
  brand4_id uuid,
  brand4_model text,
  brand4_notes text,
  brand5_id uuid,
  brand5_model text,
  brand5_notes text,
  brand6_id uuid,
  brand6_model text,
  brand6_notes text,
  comparison_notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT competitive_cross_reference_brand1_id_fkey FOREIGN KEY (brand1_id) REFERENCES brand_catalog(id),
  CONSTRAINT competitive_cross_reference_brand2_id_fkey FOREIGN KEY (brand2_id) REFERENCES brand_catalog(id),
  CONSTRAINT competitive_cross_reference_brand3_id_fkey FOREIGN KEY (brand3_id) REFERENCES brand_catalog(id),
  CONSTRAINT competitive_cross_reference_brand4_id_fkey FOREIGN KEY (brand4_id) REFERENCES brand_catalog(id),
  CONSTRAINT competitive_cross_reference_brand5_id_fkey FOREIGN KEY (brand5_id) REFERENCES brand_catalog(id),
  CONSTRAINT competitive_cross_reference_brand6_id_fkey FOREIGN KEY (brand6_id) REFERENCES brand_catalog(id),
  CONSTRAINT competitive_cross_reference_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.consent_ledger (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL,
  tenant_id uuid,
  scope text NOT NULL,
  basis text NOT NULL,
  jurisdiction text,
  matrix_version integer,
  method text NOT NULL,
  granted_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone,
  revoked_at timestamp with time zone,
  revoked_method text,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT consent_ledger_basis_check CHECK ((basis = ANY (ARRAY['consent'::text, 'contract'::text, 'legitimate_interest'::text, 'legal_obligation'::text]))),
  CONSTRAINT consent_ledger_jurisdiction_fkey FOREIGN KEY (jurisdiction) REFERENCES privacy_jurisdictions(code),
  CONSTRAINT consent_ledger_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  company_id uuid,
  first_name text NOT NULL,
  last_name text,
  title text,
  email text,
  phone text,
  linkedin_url text,
  country_code text DEFAULT 'CA'::text,
  source text,
  lifecycle_stage lifecycle_stage NOT NULL DEFAULT 'lead'::lifecycle_stage,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  preferred_name text,
  mobile_phone text,
  alternate_phone text,
  preferred_contact_method text DEFAULT 'email'::text,
  preferred_language text DEFAULT 'en'::text,
  contact_consent boolean DEFAULT true,
  communication_restrictions jsonb DEFAULT '[]'::jsonb,
  relationship_to_purchase text,
  decision_making_role text,
  last_communication_at timestamp with time zone,
  assigned_salesperson_id uuid,
  department text,
  seniority_level text,
  direct_phone text,
  purchasing_authority text,
  relationship_status text DEFAULT 'active'::text,
  notes text,
  temperature lead_temperature DEFAULT 'warm'::lead_temperature,
  temperature_changed_at timestamp with time zone,
  temperature_changed_by uuid,
  temperature_reason text,
  temperature_ai_recommendation lead_temperature,
  temperature_ai_confidence numeric(3,2),
  lead_source text,
  is_iq_lead boolean DEFAULT false,
  iq_lead_assigned_at timestamp with time zone,
  iq_lead_assignment_reason text,
  last_contact_method text,
  last_contacted_by uuid,
  customer_last_response timestamp with time zone,
  days_since_contact integer,
  next_followup_date date,
  next_followup_type text,
  followup_status text DEFAULT 'on_track'::text,
  CONSTRAINT contacts_assigned_salesperson_id_fkey FOREIGN KEY (assigned_salesperson_id) REFERENCES profiles(id),
  CONSTRAINT contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE SET NULL,
  CONSTRAINT contacts_last_contacted_by_fkey FOREIGN KEY (last_contacted_by) REFERENCES profiles(user_id),
  CONSTRAINT contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT contacts_temperature_changed_by_fkey FOREIGN KEY (temperature_changed_by) REFERENCES profiles(user_id),
  CONSTRAINT contacts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_buying_group_members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  buying_group_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  buying_role text NOT NULL DEFAULT 'co_buyer'::text,
  is_primary boolean DEFAULT false,
  communication_preference text DEFAULT 'include'::text,
  share_quotes boolean DEFAULT true,
  share_products_filter jsonb,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_buying_group_members_buying_group_id_fkey FOREIGN KEY (buying_group_id) REFERENCES crm_buying_groups(id) ON DELETE CASCADE,
  CONSTRAINT crm_buying_group_members_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT crm_buying_group_members_pkey PRIMARY KEY (id),
  CONSTRAINT crm_buying_group_members_buying_group_id_contact_id_key UNIQUE (buying_group_id, contact_id)
);

CREATE TABLE IF NOT EXISTS public.crm_buying_groups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  group_type text NOT NULL DEFAULT 'household'::text,
  primary_contact_id uuid,
  communication_default text DEFAULT 'primary_only'::text,
  notes text,
  is_archived boolean DEFAULT false,
  archived_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_buying_groups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_buying_groups_primary_contact_id_fkey FOREIGN KEY (primary_contact_id) REFERENCES contacts(id),
  CONSTRAINT crm_buying_groups_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_coaching_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  salesperson_id uuid NOT NULL,
  coaching_type text NOT NULL,
  priority integer DEFAULT 0,
  title text NOT NULL,
  description text,
  evidence jsonb DEFAULT '{}'::jsonb,
  status text DEFAULT 'pending'::text,
  assigned_manager_id uuid,
  completed_at timestamp with time zone,
  outcome_notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_coaching_queue_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'dismissed'::text]))),
  CONSTRAINT crm_coaching_queue_assigned_manager_id_fkey FOREIGN KEY (assigned_manager_id) REFERENCES profiles(user_id),
  CONSTRAINT crm_coaching_queue_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT crm_coaching_queue_salesperson_id_fkey FOREIGN KEY (salesperson_id) REFERENCES profiles(user_id),
  CONSTRAINT crm_coaching_queue_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_daily_five (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  work_date date NOT NULL DEFAULT CURRENT_DATE,
  items jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed_count integer DEFAULT 0,
  total_count integer DEFAULT 5,
  revenue_influenced numeric DEFAULT 0,
  outcomes jsonb DEFAULT '[]'::jsonb,
  generated_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_daily_five_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_daily_five_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id),
  CONSTRAINT crm_daily_five_pkey PRIMARY KEY (id),
  CONSTRAINT crm_daily_five_organization_id_user_id_work_date_key UNIQUE (organization_id, user_id, work_date)
);

CREATE TABLE IF NOT EXISTS public.crm_deal_participants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  deal_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  buying_role text NOT NULL DEFAULT 'co_buyer'::text,
  is_primary boolean DEFAULT false,
  communication_preference text DEFAULT 'include'::text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_deal_participants_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE,
  CONSTRAINT crm_deal_participants_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id) ON DELETE CASCADE,
  CONSTRAINT crm_deal_participants_pkey PRIMARY KEY (id),
  CONSTRAINT crm_deal_participants_deal_id_contact_id_key UNIQUE (deal_id, contact_id)
);

CREATE TABLE IF NOT EXISTS public.crm_deals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  company_id uuid,
  contact_id uuid,
  owner_user_id uuid,
  title text NOT NULL,
  stage text NOT NULL DEFAULT 'Lead'::text,
  value_amount numeric(14,2),
  value_currency text DEFAULT 'CAD'::text,
  expected_close_date date,
  closed_at timestamp with time zone,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  record_type text DEFAULT 'individual'::text,
  buying_group_id uuid,
  margin_amount numeric,
  margin_pct numeric,
  product_categories _text[] DEFAULT '{}'::text[],
  quote_expiry_date date,
  last_contact_at timestamp with time zone,
  next_action text,
  next_action_date date,
  days_inactive integer DEFAULT 0,
  follow_up_status text DEFAULT 'none'::text,
  priority text DEFAULT 'normal'::text,
  automation_status text DEFAULT 'none'::text,
  is_archived boolean DEFAULT false,
  archived_at timestamp with time zone,
  archive_reason text,
  auto_archive_exempt boolean DEFAULT false,
  lost_reason text,
  lost_competitor text,
  lost_objection text,
  future_followup_permitted boolean DEFAULT true,
  order_number text,
  delivery_date date,
  purchase_date date,
  warranty_status text,
  won_products jsonb DEFAULT '[]'::jsonb,
  stage_entered_at timestamp with time zone DEFAULT now(),
  quote_attached boolean DEFAULT false,
  source text,
  traffic_source text,
  temperature lead_temperature DEFAULT 'warm'::lead_temperature,
  temperature_changed_at timestamp with time zone,
  temperature_changed_by uuid,
  temperature_reason text,
  CONSTRAINT crm_deals_buying_group_id_fkey FOREIGN KEY (buying_group_id) REFERENCES crm_buying_groups(id),
  CONSTRAINT crm_deals_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE SET NULL,
  CONSTRAINT crm_deals_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL,
  CONSTRAINT crm_deals_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_deals_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT crm_deals_temperature_changed_by_fkey FOREIGN KEY (temperature_changed_by) REFERENCES profiles(user_id),
  CONSTRAINT crm_deals_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_delivery_workflows (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  deal_id uuid NOT NULL,
  contact_id uuid,
  status text NOT NULL DEFAULT 'pending'::text,
  delivery_date date,
  installation_date date,
  delivery_notes text,
  customer_confirmed_at timestamp with time zone,
  delivered_at timestamp with time zone,
  installed_at timestamp with time zone,
  warranty_registered_at timestamp with time zone,
  satisfaction_score integer,
  satisfaction_notes text,
  assigned_to uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_delivery_workflows_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'inventory_check'::text, 'install_review'::text, 'accessory_check'::text, 'customer_confirmed'::text, 'delivery_scheduled'::text, 'delivered'::text, 'installed'::text, 'warranty_registered'::text, 'satisfaction_reviewed'::text, 'completed'::text]))),
  CONSTRAINT crm_delivery_workflows_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES profiles(user_id),
  CONSTRAINT crm_delivery_workflows_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id),
  CONSTRAINT crm_delivery_workflows_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id),
  CONSTRAINT crm_delivery_workflows_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT crm_delivery_workflows_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_emails (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid,
  to_email text,
  subject text NOT NULL,
  body text,
  sent_at timestamp with time zone NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'sent'::text,
  from_email text,
  provider_message_id text,
  contact_id uuid,
  deal_id uuid,
  template_id uuid,
  sequence_enrollment_id uuid,
  channel text DEFAULT 'email'::text,
  CONSTRAINT crm_emails_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'sent'::text, 'failed'::text]))),
  CONSTRAINT crm_emails_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_emails_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT crm_emails_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_iq_lead_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  contact_id uuid,
  deal_id uuid,
  location_id uuid,
  assigned_to uuid,
  assignment_reason text NOT NULL,
  routing_method text,
  response_time_seconds integer,
  accepted boolean,
  accepted_at timestamp with time zone,
  declined_at timestamp with time zone,
  decline_reason text,
  reassigned_from uuid,
  reassignment_count integer DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_iq_lead_assignments_routing_method_check CHECK ((routing_method = ANY (ARRAY['customer_selected'::text, 'geographic'::text, 'availability'::text, 'rotation'::text, 'capacity'::text]))),
  CONSTRAINT crm_iq_lead_assignments_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES profiles(user_id),
  CONSTRAINT crm_iq_lead_assignments_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id),
  CONSTRAINT crm_iq_lead_assignments_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id),
  CONSTRAINT crm_iq_lead_assignments_location_id_fkey FOREIGN KEY (location_id) REFERENCES org_locations(id),
  CONSTRAINT crm_iq_lead_assignments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT crm_iq_lead_assignments_reassigned_from_fkey FOREIGN KEY (reassigned_from) REFERENCES profiles(user_id),
  CONSTRAINT crm_iq_lead_assignments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_org_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  auto_archive_days integer DEFAULT 180,
  auto_archive_enabled boolean DEFAULT true,
  archive_options jsonb DEFAULT '{"archive_customer": false, "archive_opportunity_only": true}'::jsonb,
  stage_requirements jsonb DEFAULT '{}'::jsonb,
  daily_five_enabled boolean DEFAULT true,
  performance_banner_enabled boolean DEFAULT true,
  performance_banner_metrics jsonb DEFAULT '["revenue_today", "revenue_mtd", "margin_pct", "warranty_rate", "avg_order", "daily_five"]'::jsonb,
  ai_assistant_mode text DEFAULT 'expandable_bar'::text,
  ai_search_enabled boolean DEFAULT true,
  rotation_integration_enabled boolean DEFAULT false,
  duplicate_detection_enabled boolean DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_org_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_org_settings_pkey PRIMARY KEY (id),
  CONSTRAINT crm_org_settings_organization_id_key UNIQUE (organization_id)
);

CREATE TABLE IF NOT EXISTS public.crm_postmortems (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  deal_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  review_type text NOT NULL DEFAULT 'won'::text,
  salesperson_id uuid,
  ai_summary text,
  salesperson_reflection text,
  strengths jsonb DEFAULT '[]'::jsonb,
  improvements jsonb DEFAULT '[]'::jsonb,
  objections jsonb DEFAULT '[]'::jsonb,
  closing_method text,
  coaching_recommendations jsonb DEFAULT '[]'::jsonb,
  followup_training text,
  manager_comments text,
  is_private boolean DEFAULT false,
  controllability text,
  is_recoverable boolean,
  recovery_plan text,
  raw_transcript text,
  recording_id uuid,
  customer_satisfaction text,
  warranty_sold boolean,
  accessories_included boolean,
  competitor_considered text,
  what_went_well text,
  what_to_improve text,
  completed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_postmortems_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id) ON DELETE CASCADE,
  CONSTRAINT crm_postmortems_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_postmortems_recording_id_fkey FOREIGN KEY (recording_id) REFERENCES sales_recordings(id),
  CONSTRAINT crm_postmortems_salesperson_id_fkey FOREIGN KEY (salesperson_id) REFERENCES profiles(id),
  CONSTRAINT crm_postmortems_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_presentations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid,
  title text NOT NULL,
  file_path text,
  sent_at timestamp with time zone,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_presentations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_presentations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT crm_presentations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_sla_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  contact_id uuid,
  deal_id uuid,
  rule_id uuid,
  event_type text NOT NULL,
  days_since_contact integer,
  assigned_to uuid,
  escalated_to uuid,
  resolved_at timestamp with time zone,
  resolution_note text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_sla_events_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES profiles(user_id),
  CONSTRAINT crm_sla_events_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id),
  CONSTRAINT crm_sla_events_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id),
  CONSTRAINT crm_sla_events_escalated_to_fkey FOREIGN KEY (escalated_to) REFERENCES profiles(user_id),
  CONSTRAINT crm_sla_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT crm_sla_events_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES crm_sla_rules(id),
  CONSTRAINT crm_sla_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_sla_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  days_threshold integer NOT NULL,
  action text NOT NULL,
  notify_manager boolean DEFAULT false,
  notify_regional boolean DEFAULT false,
  is_active boolean DEFAULT true,
  sort_order integer DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_sla_rules_action_check CHECK ((action = ANY (ARRAY['reminder'::text, 'overdue'::text, 'escalation'::text, 'critical'::text]))),
  CONSTRAINT crm_sla_rules_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT crm_sla_rules_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_stage_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  deal_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  from_stage text,
  to_stage text NOT NULL,
  changed_by uuid,
  changed_at timestamp with time zone NOT NULL DEFAULT now(),
  duration_seconds integer,
  required_fields_met boolean DEFAULT true,
  notes text,
  CONSTRAINT crm_stage_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES profiles(id),
  CONSTRAINT crm_stage_history_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id) ON DELETE CASCADE,
  CONSTRAINT crm_stage_history_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_stage_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  deal_id uuid,
  company_id uuid,
  contact_id uuid,
  assignee_user_id uuid,
  title text NOT NULL,
  description text,
  due_at timestamp with time zone,
  completed_at timestamp with time zone,
  priority text DEFAULT 'normal'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  escalation_level integer DEFAULT 0,
  escalated_to uuid,
  escalated_at timestamp with time zone,
  escalation_reason text,
  task_type text DEFAULT 'general'::text,
  task_category text,
  ai_recommended boolean DEFAULT false,
  ai_priority_score numeric(5,2),
  source text DEFAULT 'manual'::text,
  resolution_note text,
  sla_due_at timestamp with time zone,
  CONSTRAINT crm_tasks_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
  CONSTRAINT crm_tasks_assignee_user_id_fkey FOREIGN KEY (assignee_user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT crm_tasks_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE SET NULL,
  CONSTRAINT crm_tasks_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE SET NULL,
  CONSTRAINT crm_tasks_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id) ON DELETE CASCADE,
  CONSTRAINT crm_tasks_escalated_to_fkey FOREIGN KEY (escalated_to) REFERENCES profiles(user_id),
  CONSTRAINT crm_tasks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT crm_tasks_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.crm_temperature_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  from_temperature lead_temperature,
  to_temperature lead_temperature NOT NULL,
  changed_by uuid,
  ai_recommended boolean DEFAULT false,
  reason text,
  confidence numeric(3,2),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT crm_temperature_history_entity_type_check CHECK ((entity_type = ANY (ARRAY['contact'::text, 'deal'::text]))),
  CONSTRAINT crm_temperature_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES profiles(user_id),
  CONSTRAINT crm_temperature_history_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT crm_temperature_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.daily_coaching_focus (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  focus_date date NOT NULL DEFAULT CURRENT_DATE,
  primary_kpi_id uuid,
  primary_kpi_name text,
  previous_score numeric,
  target_score numeric,
  insight text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT daily_coaching_focus_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT daily_coaching_focus_primary_kpi_id_fkey FOREIGN KEY (primary_kpi_id) REFERENCES org_kpis(id),
  CONSTRAINT daily_coaching_focus_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT daily_coaching_focus_pkey PRIMARY KEY (id),
  CONSTRAINT daily_coaching_focus_organization_id_user_id_focus_date_key UNIQUE (organization_id, user_id, focus_date)
);

CREATE TABLE IF NOT EXISTS public.dashboard_metric_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  metric_key text NOT NULL,
  metric_name text NOT NULL,
  metric_category text,
  visible boolean DEFAULT true,
  "position" integer,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT dashboard_metric_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT dashboard_metric_settings_pkey PRIMARY KEY (id),
  CONSTRAINT dashboard_metric_settings_organization_id_metric_key_key UNIQUE (organization_id, metric_key)
);

CREATE TABLE IF NOT EXISTS public.dashboard_views (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  view_name text NOT NULL,
  view_type text NOT NULL DEFAULT 'custom'::text,
  owner_user_id uuid,
  is_default boolean DEFAULT false,
  is_shared boolean DEFAULT false,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT dashboard_views_view_type_check CHECK ((view_type = ANY (ARRAY['corporate'::text, 'regional'::text, 'store'::text, 'personal'::text, 'custom'::text]))),
  CONSTRAINT dashboard_views_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT dashboard_views_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id),
  CONSTRAINT dashboard_views_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.decision_actions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  decision_case_id uuid NOT NULL,
  action_type text NOT NULL DEFAULT 'recommended'::text,
  action_text text NOT NULL,
  status text NOT NULL DEFAULT 'recommended'::text,
  owner_id uuid,
  due_at timestamp with time zone,
  accepted_at timestamp with time zone,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  outcome_success boolean,
  outcome_value numeric,
  outcome_unit text,
  outcome_notes text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT decision_actions_status_check CHECK ((status = ANY (ARRAY['recommended'::text, 'accepted'::text, 'rejected'::text, 'assigned'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text, 'measured'::text]))),
  CONSTRAINT decision_actions_decision_case_id_fkey FOREIGN KEY (decision_case_id) REFERENCES decision_cases(id) ON DELETE CASCADE,
  CONSTRAINT decision_actions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT decision_actions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.decision_cases (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  module text NOT NULL,
  entity_type text,
  entity_id uuid,
  title text NOT NULL,
  summary text NOT NULL,
  recommendation text NOT NULL,
  consequence_if_ignored text,
  decision_type text NOT NULL DEFAULT 'operational'::text,
  status text NOT NULL DEFAULT 'open'::text,
  severity text NOT NULL DEFAULT 'medium'::text,
  financial_impact_cad numeric,
  customer_impact_score numeric NOT NULL DEFAULT 0,
  urgency_score numeric NOT NULL DEFAULT 0,
  confidence numeric NOT NULL DEFAULT 0.5,
  evidence_quality numeric NOT NULL DEFAULT 0.5,
  effort_score numeric NOT NULL DEFAULT 50,
  priority_score numeric NOT NULL DEFAULT 0,
  owner_id uuid,
  due_at timestamp with time zone,
  source_system text NOT NULL DEFAULT 'decision_engine'::text,
  source_record_id text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid,
  updated_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  resolved_at timestamp with time zone,
  CONSTRAINT decision_cases_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
  CONSTRAINT decision_cases_customer_impact_score_check CHECK (((customer_impact_score >= (0)::numeric) AND (customer_impact_score <= (100)::numeric))),
  CONSTRAINT decision_cases_decision_type_check CHECK ((decision_type = ANY (ARRAY['operational'::text, 'commercial'::text, 'customer'::text, 'product'::text, 'training'::text, 'field'::text, 'risk'::text, 'strategic'::text, 'opportunity'::text, 'forecast'::text]))),
  CONSTRAINT decision_cases_effort_score_check CHECK (((effort_score >= (0)::numeric) AND (effort_score <= (100)::numeric))),
  CONSTRAINT decision_cases_evidence_quality_check CHECK (((evidence_quality >= (0)::numeric) AND (evidence_quality <= (1)::numeric))),
  CONSTRAINT decision_cases_priority_score_check CHECK (((priority_score >= (0)::numeric) AND (priority_score <= (100)::numeric))),
  CONSTRAINT decision_cases_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'low'::text, 'medium'::text, 'high'::text, 'critical'::text]))),
  CONSTRAINT decision_cases_status_check CHECK ((status = ANY (ARRAY['open'::text, 'accepted'::text, 'rejected'::text, 'in_progress'::text, 'completed'::text, 'dismissed'::text, 'expired'::text]))),
  CONSTRAINT decision_cases_urgency_score_check CHECK (((urgency_score >= (0)::numeric) AND (urgency_score <= (100)::numeric))),
  CONSTRAINT decision_cases_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT decision_cases_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.decision_evidence (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  decision_case_id uuid NOT NULL,
  evidence_type text NOT NULL,
  source_system text NOT NULL,
  source_table text,
  source_record_id text,
  label text NOT NULL,
  description text,
  metric_value numeric,
  metric_unit text,
  weight numeric NOT NULL DEFAULT 1,
  confidence numeric NOT NULL DEFAULT 0.5,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT decision_evidence_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
  CONSTRAINT decision_evidence_weight_check CHECK (((weight >= (0)::numeric) AND (weight <= (10)::numeric))),
  CONSTRAINT decision_evidence_decision_case_id_fkey FOREIGN KEY (decision_case_id) REFERENCES decision_cases(id) ON DELETE CASCADE,
  CONSTRAINT decision_evidence_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT decision_evidence_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.decision_model_performance (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  module text NOT NULL,
  prediction_type text NOT NULL,
  sample_count integer NOT NULL DEFAULT 0,
  mean_absolute_error numeric,
  mean_absolute_percentage_error numeric,
  confidence_adjustment numeric NOT NULL DEFAULT 0,
  last_measured_at timestamp with time zone,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT decision_model_performance_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT decision_model_performance_pkey PRIMARY KEY (id),
  CONSTRAINT decision_model_performance_organization_id_module_predictio_key UNIQUE (organization_id, module, prediction_type)
);

CREATE TABLE IF NOT EXISTS public.decision_predictions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  decision_case_id uuid NOT NULL,
  prediction_type text NOT NULL,
  horizon text NOT NULL DEFAULT '30_days'::text,
  baseline_value numeric,
  predicted_value numeric,
  predicted_delta numeric,
  unit text,
  probability numeric NOT NULL DEFAULT 0.5,
  lower_bound numeric,
  upper_bound numeric,
  assumptions jsonb NOT NULL DEFAULT '[]'::jsonb,
  model_name text,
  model_version text,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone,
  cost_of_inaction_cad numeric,
  financial_impact_cad numeric,
  actual_value numeric,
  actual_financial_impact_cad numeric,
  measured_at timestamp with time zone,
  absolute_error numeric,
  percent_error numeric,
  status text NOT NULL DEFAULT 'active'::text,
  CONSTRAINT decision_predictions_probability_check CHECK (((probability >= (0)::numeric) AND (probability <= (1)::numeric))),
  CONSTRAINT decision_predictions_decision_case_id_fkey FOREIGN KEY (decision_case_id) REFERENCES decision_cases(id) ON DELETE CASCADE,
  CONSTRAINT decision_predictions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT decision_predictions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.dsr_downstream_notices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  dsr_id uuid NOT NULL,
  participant text NOT NULL,
  notified_at timestamp with time zone NOT NULL DEFAULT now(),
  confirmed_at timestamp with time zone,
  CONSTRAINT dsr_downstream_notices_dsr_id_fkey FOREIGN KEY (dsr_id) REFERENCES dsr_requests(id) ON DELETE CASCADE,
  CONSTRAINT dsr_downstream_notices_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.dsr_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL,
  tenant_id uuid,
  request_type text NOT NULL,
  status text NOT NULL DEFAULT 'received'::text,
  jurisdiction text,
  due_at timestamp with time zone NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  received_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  handled_by uuid,
  CONSTRAINT dsr_requests_request_type_check CHECK ((request_type = ANY (ARRAY['access'::text, 'correction'::text, 'deletion'::text, 'portability'::text]))),
  CONSTRAINT dsr_requests_status_check CHECK ((status = ANY (ARRAY['received'::text, 'identity_verification'::text, 'processing'::text, 'downstream_notified'::text, 'completed'::text, 'rejected'::text]))),
  CONSTRAINT dsr_requests_jurisdiction_fkey FOREIGN KEY (jurisdiction) REFERENCES privacy_jurisdictions(code),
  CONSTRAINT dsr_requests_pkey PRIMARY KEY (id)
);

-- =========================
-- TABLES: d* through field_l*
-- =========================

CREATE TABLE IF NOT EXISTS public.embedding_worker_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  batch_requested integer NOT NULL,
  triggered_by text,
  status text NOT NULL DEFAULT 'running'::text,
  rows_embedded integer DEFAULT 0,
  rows_failed integer DEFAULT 0,
  model text,
  error_message text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  finished_at timestamp with time zone,
  CONSTRAINT embedding_worker_runs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.executive_intelligence_insights (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  snapshot_id uuid,
  insight_type text NOT NULL,
  domain text NOT NULL,
  severity text NOT NULL DEFAULT 'info'::text,
  priority_score numeric NOT NULL DEFAULT 0,
  title text NOT NULL,
  summary text NOT NULL,
  recommended_action text,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_systems _text[] NOT NULL DEFAULT '{}'::text[],
  status text NOT NULL DEFAULT 'open'::text,
  owner_user_id uuid,
  due_at timestamp with time zone,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT executive_intelligence_insights_insight_type_check CHECK ((insight_type = ANY (ARRAY['risk'::text, 'opportunity'::text, 'performance'::text, 'anomaly'::text, 'action'::text, 'trend'::text]))),
  CONSTRAINT executive_intelligence_insights_severity_check CHECK ((severity = ANY (ARRAY['critical'::text, 'high'::text, 'medium'::text, 'low'::text, 'info'::text]))),
  CONSTRAINT executive_intelligence_insights_status_check CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'in_progress'::text, 'resolved'::text, 'dismissed'::text]))),
  CONSTRAINT executive_intelligence_insights_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT executive_intelligence_insights_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT executive_intelligence_insights_snapshot_id_fkey FOREIGN KEY (snapshot_id) REFERENCES executive_intelligence_snapshots(id) ON DELETE CASCADE,
  CONSTRAINT executive_intelligence_insights_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.executive_intelligence_queries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  asked_by uuid,
  question text NOT NULL,
  intent text,
  answer jsonb NOT NULL DEFAULT '{}'::jsonb,
  evidence jsonb NOT NULL DEFAULT '[]'::jsonb,
  confidence numeric,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT executive_intelligence_queries_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
  CONSTRAINT executive_intelligence_queries_asked_by_fkey FOREIGN KEY (asked_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT executive_intelligence_queries_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT executive_intelligence_queries_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.executive_intelligence_snapshots (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  snapshot_type text NOT NULL DEFAULT 'current'::text,
  period_start date,
  period_end date,
  overall_health_score numeric NOT NULL DEFAULT 0,
  health_status text NOT NULL DEFAULT 'unknown'::text,
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  evidence_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  generated_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  data_confidence numeric NOT NULL DEFAULT 0,
  coverage_status text NOT NULL DEFAULT 'insufficient'::text,
  CONSTRAINT executive_intelligence_snapshots_coverage_status_check CHECK ((coverage_status = ANY (ARRAY['insufficient'::text, 'partial'::text, 'good'::text, 'strong'::text]))),
  CONSTRAINT executive_intelligence_snapshots_data_confidence_check CHECK (((data_confidence >= (0)::numeric) AND (data_confidence <= (1)::numeric))),
  CONSTRAINT executive_intelligence_snapshots_health_status_check CHECK ((health_status = ANY (ARRAY['critical'::text, 'at_risk'::text, 'watch'::text, 'healthy'::text, 'strong'::text, 'unknown'::text]))),
  CONSTRAINT executive_intelligence_snapshots_overall_health_score_check CHECK (((overall_health_score >= (0)::numeric) AND (overall_health_score <= (100)::numeric))),
  CONSTRAINT executive_intelligence_snapshots_generated_by_fkey FOREIGN KEY (generated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT executive_intelligence_snapshots_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT executive_intelligence_snapshots_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_action_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL,
  assigned_to_user_id uuid,
  assigned_to_name text,
  assigned_to_role text,
  assigned_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  status text DEFAULT 'active'::text,
  CONSTRAINT field_action_assignments_assigned_to_role_check CHECK ((assigned_to_role = ANY (ARRAY['manufacturer_account_manager'::text, 'manufacturer_field_manager'::text, 'service_department'::text, 'third_party_service'::text, 'retailer_manager'::text, 'applianceiq_manager'::text, 'applianceiq_rep'::text, 'distributor'::text, 'merchandising_provider'::text]))),
  CONSTRAINT field_action_assignments_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id) ON DELETE CASCADE,
  CONSTRAINT field_action_assignments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_action_comments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_id uuid,
  visit_id uuid,
  finding_id uuid,
  author_user_id uuid,
  author_name text,
  comment_text text,
  comment_type text DEFAULT 'text'::text,
  visibility text DEFAULT 'internal'::text,
  media_url text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_action_comments_comment_type_check CHECK ((comment_type = ANY (ARRAY['text'::text, 'voice_note'::text, 'photo'::text, 'document'::text, 'service_record'::text]))),
  CONSTRAINT field_action_comments_visibility_check CHECK ((visibility = ANY (ARRAY['internal'::text, 'manufacturer'::text, 'retailer'::text, 'service_provider'::text, 'all'::text]))),
  CONSTRAINT field_action_comments_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id) ON DELETE CASCADE,
  CONSTRAINT field_action_comments_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES field_findings(id),
  CONSTRAINT field_action_comments_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id),
  CONSTRAINT field_action_comments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_action_evidence (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL,
  evidence_type text,
  storage_path text,
  caption text,
  uploaded_by_user_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_action_evidence_evidence_type_check CHECK ((evidence_type = ANY (ARRAY['before_photo'::text, 'after_photo'::text, 'service_record'::text, 'receipt'::text, 'document'::text, 'video'::text]))),
  CONSTRAINT field_action_evidence_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id) ON DELETE CASCADE,
  CONSTRAINT field_action_evidence_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_action_status_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL,
  old_status text,
  new_status text NOT NULL,
  changed_by_user_id uuid,
  changed_by_name text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_action_status_history_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id) ON DELETE CASCADE,
  CONSTRAINT field_action_status_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_actions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  finding_id uuid NOT NULL,
  visit_id uuid NOT NULL,
  client_id uuid NOT NULL,
  store_id uuid NOT NULL,
  title text NOT NULL,
  description text,
  action_type text,
  status text DEFAULT 'new'::text,
  priority text DEFAULT 'normal'::text,
  assigned_to_user_id uuid,
  assigned_to_team text,
  assigned_to_role text,
  due_date date,
  escalation_level integer DEFAULT 0,
  resolved_at timestamp with time zone,
  closed_at timestamp with time zone,
  resolution_notes text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  verified_at timestamp with time zone,
  verified_by_user_id uuid,
  verification_notes text,
  CONSTRAINT field_actions_priority_check CHECK ((priority = ANY (ARRAY['critical'::text, 'high'::text, 'normal'::text, 'low'::text]))),
  CONSTRAINT field_actions_status_check CHECK ((status = ANY (ARRAY['new'::text, 'reviewed'::text, 'action_required'::text, 'assigned'::text, 'service_requested'::text, 'service_deployed'::text, 'waiting_retailer'::text, 'waiting_manufacturer'::text, 'waiting_parts'::text, 'replacement_approved'::text, 'replacement_deployed'::text, 'follow_up_required'::text, 'resolved'::text, 'closed'::text, 'rejected'::text]))),
  CONSTRAINT field_actions_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_actions_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES field_findings(id),
  CONSTRAINT field_actions_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_actions_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id),
  CONSTRAINT field_actions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_ai_detections (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  media_id uuid NOT NULL,
  visit_id uuid NOT NULL,
  detection_type text NOT NULL,
  description text,
  confidence numeric(5,2),
  bounding_box jsonb,
  suggested_category text,
  suggested_severity text,
  accepted boolean,
  accepted_at timestamp with time zone,
  rejected_reason text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_ai_detections_media_id_fkey FOREIGN KEY (media_id) REFERENCES field_media(id) ON DELETE CASCADE,
  CONSTRAINT field_ai_detections_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id) ON DELETE CASCADE,
  CONSTRAINT field_ai_detections_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_assets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL,
  client_id uuid NOT NULL,
  product_id uuid,
  brand_name text,
  model_number text,
  serial_number text,
  display_location text,
  install_date date,
  last_inspected_at timestamp with time zone,
  condition text,
  status text DEFAULT 'active'::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_assets_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_assets_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id),
  CONSTRAINT field_assets_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_assets_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_assignments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL,
  program_id uuid,
  store_id uuid NOT NULL,
  rep_user_id uuid NOT NULL,
  frequency text DEFAULT 'monthly'::text,
  next_visit_due date,
  priority text DEFAULT 'normal'::text,
  status text DEFAULT 'active'::text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_assignments_frequency_check CHECK ((frequency = ANY (ARRAY['weekly'::text, 'biweekly'::text, 'monthly'::text, 'quarterly'::text, 'one_time'::text, 'as_needed'::text]))),
  CONSTRAINT field_assignments_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_assignments_program_id_fkey FOREIGN KEY (program_id) REFERENCES field_programs(id),
  CONSTRAINT field_assignments_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_assignments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_checklist_categories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  icon text DEFAULT '📋'::text,
  applies_to text NOT NULL DEFAULT 'both'::text,
  sort_order integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_checklist_categories_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_checklist_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL,
  question text NOT NULL,
  description text,
  response_type text DEFAULT 'yes_no'::text,
  applies_to text NOT NULL DEFAULT 'both'::text,
  severity_if_fail text DEFAULT 'medium'::text,
  auto_action_type text,
  sort_order integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_checklist_items_category_id_fkey FOREIGN KEY (category_id) REFERENCES field_checklist_categories(id),
  CONSTRAINT field_checklist_items_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_checklist_responses (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL,
  checklist_item_id uuid NOT NULL,
  category_id uuid NOT NULL,
  response text NOT NULL,
  notes text,
  photo_path text,
  flagged boolean DEFAULT false,
  finding_id uuid,
  action_id uuid,
  responded_by_user_id uuid,
  responded_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_checklist_responses_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id),
  CONSTRAINT field_checklist_responses_category_id_fkey FOREIGN KEY (category_id) REFERENCES field_checklist_categories(id),
  CONSTRAINT field_checklist_responses_checklist_item_id_fkey FOREIGN KEY (checklist_item_id) REFERENCES field_checklist_items(id),
  CONSTRAINT field_checklist_responses_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES field_findings(id),
  CONSTRAINT field_checklist_responses_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id),
  CONSTRAINT field_checklist_responses_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_clients (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  client_name text NOT NULL,
  country text DEFAULT 'CA'::text,
  status text DEFAULT 'active'::text,
  contract_start date,
  contract_end date,
  notes text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_clients_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'churned'::text]))),
  CONSTRAINT field_clients_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT field_clients_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_competitive_intel (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL,
  store_id uuid NOT NULL,
  competitor_brand text NOT NULL,
  floor_presence_pct numeric(5,2),
  display_size text,
  promotions_active text,
  pricing_notes text,
  signage_notes text,
  new_models_spotted text,
  staff_preference_notes text,
  customer_questions text,
  common_objections text,
  share_of_display numeric(5,2),
  rep_comments text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_competitive_intel_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_competitive_intel_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id),
  CONSTRAINT field_competitive_intel_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_escalations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL,
  escalation_level integer NOT NULL DEFAULT 1,
  escalated_by_user_id uuid,
  escalated_to_user_id uuid,
  reason text,
  resolved boolean DEFAULT false,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_escalations_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id),
  CONSTRAINT field_escalations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_exports (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  client_id uuid,
  export_type text NOT NULL,
  export_format text,
  filters jsonb DEFAULT '{}'::jsonb,
  file_url text,
  generated_by_user_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_exports_export_format_check CHECK ((export_format = ANY (ARRAY['pdf'::text, 'csv'::text, 'xlsx'::text, 'image_package'::text]))),
  CONSTRAINT field_exports_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_exports_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_findings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL,
  client_id uuid NOT NULL,
  store_id uuid NOT NULL,
  ai_detection_id uuid,
  brand_name text,
  product_category text,
  product_type text,
  model_number text,
  serial_number text,
  display_location text,
  condition text,
  issue_category text,
  severity text DEFAULT 'low'::text,
  recommended_action text,
  rep_comments text,
  ai_summary text,
  is_repeat boolean DEFAULT false,
  source text DEFAULT 'manual'::text,
  status text DEFAULT 'new'::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_findings_condition_check CHECK ((condition = ANY (ARRAY['excellent'::text, 'good'::text, 'fair'::text, 'service_required'::text, 'replacement_recommended'::text, 'missing'::text, 'unable_to_inspect'::text]))),
  CONSTRAINT field_findings_severity_check CHECK ((severity = ANY (ARRAY['critical'::text, 'high'::text, 'medium'::text, 'low'::text, 'info'::text]))),
  CONSTRAINT field_findings_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'ai_assisted'::text, 'ai_confirmed'::text]))),
  CONSTRAINT field_findings_ai_detection_id_fkey FOREIGN KEY (ai_detection_id) REFERENCES field_ai_detections(id),
  CONSTRAINT field_findings_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_findings_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_findings_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id) ON DELETE CASCADE,
  CONSTRAINT field_findings_pkey PRIMARY KEY (id)
);

-- =========================
-- TABLES: field_m* through h*
-- =========================

CREATE TABLE IF NOT EXISTS public.field_manufacturer_users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL,
  user_id uuid,
  email text NOT NULL,
  name text,
  role text DEFAULT 'viewer'::text,
  status text DEFAULT 'active'::text,
  last_login_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_manufacturer_users_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'account_manager'::text, 'field_manager'::text, 'viewer'::text]))),
  CONSTRAINT field_manufacturer_users_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_manufacturer_users_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_media (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL,
  media_type text NOT NULL,
  storage_path text NOT NULL,
  file_name text,
  file_size integer,
  mime_type text,
  caption text,
  capture_context text,
  gps_lat numeric(10,7),
  gps_lng numeric(10,7),
  ai_processed boolean DEFAULT false,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_media_capture_context_check CHECK ((capture_context = ANY (ARRAY['floor'::text, 'brand_section'::text, 'product'::text, 'display'::text, 'signage'::text, 'pricing'::text, 'competitive'::text, 'before_after'::text, 'training'::text, 'other'::text]))),
  CONSTRAINT field_media_media_type_check CHECK ((media_type = ANY (ARRAY['photo'::text, 'video'::text, 'voice_note'::text, 'document'::text]))),
  CONSTRAINT field_media_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id) ON DELETE CASCADE,
  CONSTRAINT field_media_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  recipient_user_id uuid,
  recipient_email text,
  notification_type text NOT NULL,
  title text NOT NULL,
  body text,
  related_action_id uuid,
  related_visit_id uuid,
  is_read boolean DEFAULT false,
  read_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_notifications_related_action_id_fkey FOREIGN KEY (related_action_id) REFERENCES field_actions(id),
  CONSTRAINT field_notifications_related_visit_id_fkey FOREIGN KEY (related_visit_id) REFERENCES field_visits(id),
  CONSTRAINT field_notifications_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_programs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  program_type text DEFAULT 'audit'::text,
  country text,
  start_date date,
  end_date date,
  status text DEFAULT 'active'::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_programs_program_type_check CHECK ((program_type = ANY (ARRAY['audit'::text, 'training'::text, 'launch'::text, 'mystery_shop'::text, 'merchandising'::text, 'competitive'::text, 'ongoing'::text]))),
  CONSTRAINT field_programs_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_programs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_replacement_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL,
  client_id uuid NOT NULL,
  store_id uuid NOT NULL,
  current_model text,
  replacement_model text,
  reason text,
  approved boolean,
  approved_by_user_id uuid,
  approved_at timestamp with time zone,
  shipped_at timestamp with time zone,
  installed_at timestamp with time zone,
  status text DEFAULT 'pending'::text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_replacement_requests_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id),
  CONSTRAINT field_replacement_requests_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_replacement_requests_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_replacement_requests_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_retailer_users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  retailer_id uuid NOT NULL,
  store_id uuid,
  email text NOT NULL,
  name text,
  role text DEFAULT 'viewer'::text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_retailer_users_retailer_id_fkey FOREIGN KEY (retailer_id) REFERENCES field_retailers(id),
  CONSTRAINT field_retailer_users_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_retailer_users_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_retailers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  country text DEFAULT 'CA'::text,
  website text,
  logo_url text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_retailers_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_score_components (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  store_score_id uuid NOT NULL,
  component_name text NOT NULL,
  score numeric(5,2),
  max_score numeric(5,2) DEFAULT 100,
  weight numeric(5,2) DEFAULT 1,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_score_components_store_score_id_fkey FOREIGN KEY (store_score_id) REFERENCES field_store_scores(id) ON DELETE CASCADE,
  CONSTRAINT field_score_components_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_service_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  action_id uuid NOT NULL,
  client_id uuid NOT NULL,
  store_id uuid NOT NULL,
  service_type text,
  provider_name text,
  provider_contact text,
  scheduled_date date,
  completed_date date,
  status text DEFAULT 'pending'::text,
  cost numeric(10,2),
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_service_requests_action_id_fkey FOREIGN KEY (action_id) REFERENCES field_actions(id),
  CONSTRAINT field_service_requests_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_service_requests_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_service_requests_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_store_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  store_id uuid NOT NULL,
  name text NOT NULL,
  title text,
  email text,
  phone text,
  is_primary boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_store_contacts_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_store_contacts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_store_scores (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL,
  store_id uuid NOT NULL,
  client_id uuid NOT NULL,
  overall_score numeric(5,2),
  score_date date NOT NULL DEFAULT CURRENT_DATE,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_store_scores_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_store_scores_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_store_scores_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id),
  CONSTRAINT field_store_scores_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_stores (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  retailer_id uuid NOT NULL,
  org_location_id uuid,
  store_name text NOT NULL,
  store_number text,
  address text,
  city text,
  province_state text,
  country text DEFAULT 'CA'::text,
  postal_zip text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  region text,
  timezone text DEFAULT 'America/Toronto'::text,
  status text DEFAULT 'active'::text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_stores_org_location_id_fkey FOREIGN KEY (org_location_id) REFERENCES org_locations(id),
  CONSTRAINT field_stores_retailer_id_fkey FOREIGN KEY (retailer_id) REFERENCES field_retailers(id),
  CONSTRAINT field_stores_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_training_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL,
  client_id uuid NOT NULL,
  store_id uuid NOT NULL,
  training_topic text NOT NULL,
  brand_name text,
  product_category text,
  models_covered _text[],
  employees_trained integer DEFAULT 0,
  employee_names _text[],
  duration_minutes integer,
  knowledge_score numeric(5,2),
  areas_of_weakness text,
  follow_up_required boolean DEFAULT false,
  rep_comments text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_training_sessions_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_training_sessions_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_training_sessions_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id),
  CONSTRAINT field_training_sessions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_visit_tasks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  visit_id uuid NOT NULL,
  task_description text NOT NULL,
  task_type text,
  is_completed boolean DEFAULT false,
  completed_at timestamp with time zone,
  sort_order integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT field_visit_tasks_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES field_visits(id) ON DELETE CASCADE,
  CONSTRAINT field_visit_tasks_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.field_visits (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  assignment_id uuid,
  client_id uuid NOT NULL,
  program_id uuid,
  store_id uuid NOT NULL,
  rep_user_id uuid NOT NULL,
  visit_date date NOT NULL DEFAULT CURRENT_DATE,
  arrival_time timestamp with time zone,
  departure_time timestamp with time zone,
  duration_minutes integer,
  gps_lat numeric(10,7),
  gps_lng numeric(10,7),
  visit_purpose text,
  status text DEFAULT 'in_progress'::text,
  findings_count integer DEFAULT 0,
  critical_count integer DEFAULT 0,
  photos_count integer DEFAULT 0,
  videos_count integer DEFAULT 0,
  training_completed boolean DEFAULT false,
  people_trained integer DEFAULT 0,
  rep_summary text,
  ai_summary text,
  store_score numeric(5,2),
  brand_score numeric(5,2),
  previous_score numeric(5,2),
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  visit_type text DEFAULT 'field_rep'::text,
  checklist_score numeric(5,2),
  checklist_total integer DEFAULT 0,
  checklist_passed integer DEFAULT 0,
  CONSTRAINT field_visits_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text]))),
  CONSTRAINT field_visits_assignment_id_fkey FOREIGN KEY (assignment_id) REFERENCES field_assignments(id),
  CONSTRAINT field_visits_client_id_fkey FOREIGN KEY (client_id) REFERENCES field_clients(id),
  CONSTRAINT field_visits_program_id_fkey FOREIGN KEY (program_id) REFERENCES field_programs(id),
  CONSTRAINT field_visits_store_id_fkey FOREIGN KEY (store_id) REFERENCES field_stores(id),
  CONSTRAINT field_visits_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.foundation_audit_log (
  id bigint NOT NULL DEFAULT nextval('foundation_audit_log_id_seq'::regclass),
  entity_table text NOT NULL,
  entity_id uuid NOT NULL,
  action text NOT NULL,
  actor uuid,
  delta jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT foundation_audit_log_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.foundation_disputes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  fact_id uuid NOT NULL,
  raised_by uuid NOT NULL,
  raised_role text NOT NULL,
  evidence text NOT NULL,
  status text NOT NULL DEFAULT 'open'::text,
  resolution text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  resolved_at timestamp with time zone,
  resolved_by uuid,
  CONSTRAINT foundation_disputes_status_check CHECK ((status = ANY (ARRAY['open'::text, 'upheld'::text, 'rejected'::text, 'withdrawn'::text]))),
  CONSTRAINT foundation_disputes_fact_id_fkey FOREIGN KEY (fact_id) REFERENCES foundation_facts(id) ON DELETE CASCADE,
  CONSTRAINT foundation_disputes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.foundation_fact_reviews (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  fact_id uuid NOT NULL,
  reviewer uuid NOT NULL,
  decision text NOT NULL,
  notes text,
  review_seconds integer,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT foundation_fact_reviews_decision_check CHECK ((decision = ANY (ARRAY['approve'::text, 'reject'::text, 'dispute'::text, 'needs_info'::text]))),
  CONSTRAINT foundation_fact_reviews_fact_id_fkey FOREIGN KEY (fact_id) REFERENCES foundation_facts(id) ON DELETE CASCADE,
  CONSTRAINT foundation_fact_reviews_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.foundation_facts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  object_id uuid NOT NULL,
  fact_type text NOT NULL,
  value_text text,
  value_num numeric,
  unit text,
  intelligence_type text NOT NULL,
  source text NOT NULL,
  source_asset uuid,
  extraction_run uuid,
  status text NOT NULL DEFAULT 'candidate'::text,
  version integer NOT NULL DEFAULT 1,
  effective_from date NOT NULL DEFAULT CURRENT_DATE,
  effective_to date,
  confidence numeric(4,3) NOT NULL DEFAULT 0.500,
  verified_by uuid,
  verified_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT foundation_facts_intelligence_type_check CHECK ((intelligence_type = ANY (ARRAY['FACT'::text, 'SPECIFICATION'::text, 'RULE'::text, 'INSTALLATION_REQUIREMENT'::text, 'SALES_KNOWLEDGE'::text, 'CUSTOMER_KNOWLEDGE'::text, 'MARKET_KNOWLEDGE'::text, 'RECOMMENDATION'::text, 'AI_INFERENCE'::text]))),
  CONSTRAINT foundation_facts_source_check CHECK ((source = ANY (ARRAY['MANUFACTURER'::text, 'INTERNAL_APPLIANCE_IQ'::text, 'INDUSTRY_ASSOCIATION'::text, 'DEALER'::text, 'INSTALLER'::text, 'TECHNICIAN'::text, 'AI_EXTRACTED'::text, 'CUSTOMER_SUBMITTED'::text, 'UNKNOWN'::text]))),
  CONSTRAINT foundation_facts_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'candidate'::text, 'verified'::text, 'disputed'::text, 'deprecated'::text, 'retired'::text]))),
  CONSTRAINT foundation_facts_object_id_fkey FOREIGN KEY (object_id) REFERENCES foundation_objects(id) ON DELETE CASCADE,
  CONSTRAINT foundation_facts_pkey PRIMARY KEY (id),
  CONSTRAINT foundation_facts_object_id_fact_type_version_key UNIQUE (object_id, fact_type, version)
);

CREATE TABLE IF NOT EXISTS public.foundation_object_types (
  type_key text NOT NULL,
  domain text NOT NULL,
  label text NOT NULL,
  attr_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
  steward_role text NOT NULL DEFAULT 'steward_general'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT foundation_object_types_domain_check CHECK ((domain = ANY (ARRAY['organization'::text, 'product'::text, 'technical'::text, 'sales'::text, 'learning'::text, 'market'::text]))),
  CONSTRAINT foundation_object_types_pkey PRIMARY KEY (type_key)
);

CREATE TABLE IF NOT EXISTS public.foundation_objects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  object_type text NOT NULL,
  name text NOT NULL,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  owner_org uuid,
  status text NOT NULL DEFAULT 'draft'::text,
  version integer NOT NULL DEFAULT 1,
  permissions jsonb NOT NULL DEFAULT '{"read": "trade", "write": "steward"}'::jsonb,
  source text NOT NULL DEFAULT 'INTERNAL_APPLIANCE_IQ'::text,
  confidence numeric(4,3) NOT NULL DEFAULT 0.500,
  verified_by uuid,
  verified_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT foundation_objects_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
  CONSTRAINT foundation_objects_source_check CHECK ((source = ANY (ARRAY['MANUFACTURER'::text, 'INTERNAL_APPLIANCE_IQ'::text, 'INDUSTRY_ASSOCIATION'::text, 'DEALER'::text, 'INSTALLER'::text, 'TECHNICIAN'::text, 'AI_EXTRACTED'::text, 'CUSTOMER_SUBMITTED'::text, 'UNKNOWN'::text]))),
  CONSTRAINT foundation_objects_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'candidate'::text, 'verified'::text, 'disputed'::text, 'deprecated'::text, 'retired'::text]))),
  CONSTRAINT foundation_objects_object_type_fkey FOREIGN KEY (object_type) REFERENCES foundation_object_types(type_key),
  CONSTRAINT foundation_objects_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.foundation_relationship_types (
  rel_key text NOT NULL,
  label text NOT NULL,
  from_domains _text[] NOT NULL,
  to_domains _text[] NOT NULL,
  attr_schema jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT foundation_relationship_types_pkey PRIMARY KEY (rel_key)
);

CREATE TABLE IF NOT EXISTS public.foundation_relationships (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  from_id uuid NOT NULL,
  to_id uuid NOT NULL,
  rel_type text NOT NULL,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'candidate'::text,
  source text NOT NULL DEFAULT 'INTERNAL_APPLIANCE_IQ'::text,
  confidence numeric(4,3) NOT NULL DEFAULT 0.500,
  verified_by uuid,
  verified_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT foundation_relationships_source_check CHECK ((source = ANY (ARRAY['MANUFACTURER'::text, 'INTERNAL_APPLIANCE_IQ'::text, 'INDUSTRY_ASSOCIATION'::text, 'DEALER'::text, 'INSTALLER'::text, 'TECHNICIAN'::text, 'AI_EXTRACTED'::text, 'CUSTOMER_SUBMITTED'::text, 'UNKNOWN'::text]))),
  CONSTRAINT foundation_relationships_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'candidate'::text, 'verified'::text, 'disputed'::text, 'deprecated'::text, 'retired'::text]))),
  CONSTRAINT foundation_relationships_from_id_fkey FOREIGN KEY (from_id) REFERENCES foundation_objects(id) ON DELETE CASCADE,
  CONSTRAINT foundation_relationships_rel_type_fkey FOREIGN KEY (rel_type) REFERENCES foundation_relationship_types(rel_key),
  CONSTRAINT foundation_relationships_to_id_fkey FOREIGN KEY (to_id) REFERENCES foundation_objects(id) ON DELETE CASCADE,
  CONSTRAINT foundation_relationships_pkey PRIMARY KEY (id),
  CONSTRAINT foundation_relationships_from_id_to_id_rel_type_key UNIQUE (from_id, to_id, rel_type)
);

-- =========================
-- TABLES: i* through iq_k*
-- =========================

CREATE TABLE IF NOT EXISTS public.installation_requirements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_category text NOT NULL,
  subcategory text,
  electrical_voltage text,
  electrical_amperage text,
  electrical_circuit text,
  gas_connection text,
  water_connection text,
  drain_required boolean DEFAULT false,
  ventilation_cfm text,
  min_clearances text,
  typical_install_time text,
  licensed_trades_required _text[],
  common_issues _text[],
  notes text,
  country text DEFAULT 'US+CA'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT installation_requirements_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.intel_companies (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  type text NOT NULL DEFAULT 'manufacturer'::text,
  parent_company text,
  headquarters text,
  country text,
  founded text,
  website text,
  brands jsonb DEFAULT '[]'::jsonb,
  leadership jsonb DEFAULT '[]'::jsonb,
  description text,
  history text,
  manufacturing_locations jsonb DEFAULT '[]'::jsonb,
  distribution_notes text,
  market_segment text,
  employee_count text,
  annual_revenue text,
  stock_ticker text,
  brand_catalog_id uuid,
  source_url text,
  scraped_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT intel_companies_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.intel_locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid,
  company_name text NOT NULL,
  location_type text DEFAULT 'store'::text,
  name text,
  address text,
  city text,
  province_state text,
  country text,
  postal_zip text,
  phone text,
  status text DEFAULT 'active'::text,
  opened_date text,
  closed_date text,
  notes text,
  source_url text,
  scraped_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT intel_locations_company_id_fkey FOREIGN KEY (company_id) REFERENCES intel_companies(id) ON DELETE CASCADE,
  CONSTRAINT intel_locations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.intel_news (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid,
  company_name text NOT NULL,
  headline text NOT NULL,
  summary text,
  category text,
  source_name text,
  source_url text,
  published_date text,
  scraped_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT intel_news_company_id_fkey FOREIGN KEY (company_id) REFERENCES intel_companies(id) ON DELETE CASCADE,
  CONSTRAINT intel_news_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.intelligence_context_cache (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  entity_id uuid,
  context_key text NOT NULL,
  context_version integer NOT NULL DEFAULT 1,
  context_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_fingerprint text,
  confidence_score numeric(5,2),
  expires_at timestamp with time zone,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_context_cache_confidence_score_check CHECK (((confidence_score >= (0)::numeric) AND (confidence_score <= (100)::numeric))),
  CONSTRAINT intelligence_context_cache_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES intelligence_entities(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_context_cache_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_context_cache_pkey PRIMARY KEY (id),
  CONSTRAINT intelligence_context_cache_organization_id_entity_id_contex_key UNIQUE (organization_id, entity_id, context_key)
);

CREATE TABLE IF NOT EXISTS public.intelligence_entities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  entity_type text NOT NULL,
  canonical_name text NOT NULL,
  slug text,
  source_system text NOT NULL DEFAULT 'intelligence_core'::text,
  source_record_id text,
  status text NOT NULL DEFAULT 'active'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid,
  updated_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_entities_entity_type_check CHECK ((entity_type = ANY (ARRAY['product'::text, 'brand'::text, 'manufacturer'::text, 'retailer'::text, 'store'::text, 'customer'::text, 'employee'::text, 'package'::text, 'quote'::text, 'comparison'::text, 'document'::text, 'manual'::text, 'image'::text, 'video'::text, 'promotion'::text, 'recall'::text, 'training_module'::text, 'field_report'::text, 'conversation'::text, 'opportunity'::text, 'project'::text, 'other'::text]))),
  CONSTRAINT intelligence_entities_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text, 'merged'::text, 'deleted'::text]))),
  CONSTRAINT intelligence_entities_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_entities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_entities_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_entities_pkey PRIMARY KEY (id),
  CONSTRAINT intelligence_entities_organization_id_entity_type_slug_key UNIQUE (organization_id, entity_type, slug),
  CONSTRAINT intelligence_entities_organization_id_source_system_source__key UNIQUE (organization_id, source_system, source_record_id)
);

CREATE TABLE IF NOT EXISTS public.intelligence_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  entity_id uuid,
  event_type text NOT NULL,
  source_system text NOT NULL,
  source_record_id text,
  actor_id uuid,
  correlation_id uuid,
  causation_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_events_causation_id_fkey FOREIGN KEY (causation_id) REFERENCES intelligence_events(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_events_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES intelligence_entities(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.intelligence_learning_signals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  context_key text NOT NULL DEFAULT 'general'::text,
  subject_type text NOT NULL,
  subject_key text NOT NULL,
  recommended_action text NOT NULL,
  observation_count bigint NOT NULL DEFAULT 0,
  success_count bigint NOT NULL DEFAULT 0,
  failure_count bigint NOT NULL DEFAULT 0,
  neutral_count bigint NOT NULL DEFAULT 0,
  weighted_success numeric(18,6) NOT NULL DEFAULT 0,
  weighted_total numeric(18,6) NOT NULL DEFAULT 0,
  success_rate numeric(8,6) NOT NULL DEFAULT 0,
  bayesian_score numeric(8,6) NOT NULL DEFAULT 0.5,
  average_outcome_value numeric(18,6),
  last_outcome_at timestamp with time zone,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_learning_signals_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_learning_signals_pkey PRIMARY KEY (id),
  CONSTRAINT intelligence_learning_signals_organization_id_context_key_s_key UNIQUE (organization_id, context_key, subject_type, subject_key, recommended_action)
);

CREATE TABLE IF NOT EXISTS public.intelligence_outcomes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  recommendation_id uuid NOT NULL,
  entity_id uuid,
  outcome_type text NOT NULL,
  outcome_value numeric,
  outcome_label text,
  success boolean,
  weight numeric(8,4) NOT NULL DEFAULT 1,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_system text NOT NULL DEFAULT 'intelligence_core'::text,
  source_record_id text,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  recorded_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_outcomes_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES intelligence_entities(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_outcomes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_outcomes_recommendation_id_fkey FOREIGN KEY (recommendation_id) REFERENCES intelligence_recommendations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_outcomes_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_outcomes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.intelligence_recommendations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  entity_id uuid,
  recommendation_type text NOT NULL,
  context_key text NOT NULL DEFAULT 'general'::text,
  subject_type text NOT NULL,
  subject_key text NOT NULL,
  recommended_action text NOT NULL,
  alternatives jsonb NOT NULL DEFAULT '[]'::jsonb,
  rationale jsonb NOT NULL DEFAULT '{}'::jsonb,
  model_name text,
  model_version text,
  confidence numeric(6,5),
  status text NOT NULL DEFAULT 'presented'::text,
  actor_id uuid,
  source_system text NOT NULL DEFAULT 'intelligence_core'::text,
  source_record_id text,
  presented_at timestamp with time zone,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_recommendations_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
  CONSTRAINT intelligence_recommendations_status_check CHECK ((status = ANY (ARRAY['generated'::text, 'presented'::text, 'accepted'::text, 'rejected'::text, 'expired'::text, 'superseded'::text]))),
  CONSTRAINT intelligence_recommendations_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_recommendations_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES intelligence_entities(id) ON DELETE SET NULL,
  CONSTRAINT intelligence_recommendations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_recommendations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.intelligence_timelines (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  entity_id uuid,
  event_id uuid,
  timeline_type text NOT NULL DEFAULT 'activity'::text,
  title text NOT NULL,
  summary text,
  visibility text NOT NULL DEFAULT 'organization'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT intelligence_timelines_visibility_check CHECK ((visibility = ANY (ARRAY['private'::text, 'organization'::text, 'public'::text]))),
  CONSTRAINT intelligence_timelines_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES intelligence_entities(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_timelines_event_id_fkey FOREIGN KEY (event_id) REFERENCES intelligence_events(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_timelines_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT intelligence_timelines_pkey PRIMARY KEY (id),
  CONSTRAINT intelligence_timelines_event_id_key UNIQUE (event_id)
);

CREATE TABLE IF NOT EXISTS public.iq_audit_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid,
  event_type text NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid,
  before_state jsonb,
  after_state jsonb,
  notes text,
  severity text NOT NULL DEFAULT 'info'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_audit_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_audit_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_audit_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_badges (
  id integer NOT NULL DEFAULT nextval('iq_badges_id_seq'::regclass),
  badge_key text NOT NULL,
  pillar text,
  badge_type text NOT NULL,
  level smallint,
  name text NOT NULL,
  description text,
  icon text,
  color text,
  course_id integer,
  brand_id uuid,
  requirements jsonb,
  sort_order smallint DEFAULT 0,
  CONSTRAINT iq_badges_badge_type_check CHECK ((badge_type = ANY (ARRAY['pillar_cert'::text, 'course_cert'::text, 'brand_cert'::text, 'zone_gate'::text, 'streak'::text, 'milestone'::text]))),
  CONSTRAINT iq_badges_pillar_check CHECK ((pillar = ANY (ARRAY['sales_iq'::text, 'product_iq'::text, 'brand_iq'::text, 'leadership_iq'::text, 'system'::text]))),
  CONSTRAINT iq_badges_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT iq_badges_course_id_fkey FOREIGN KEY (course_id) REFERENCES iq_courses(id),
  CONSTRAINT iq_badges_pkey PRIMARY KEY (id),
  CONSTRAINT iq_badges_badge_key_key UNIQUE (badge_key)
);

CREATE TABLE IF NOT EXISTS public.iq_card_completions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  card_id integer NOT NULL,
  completed_at timestamp with time zone DEFAULT now(),
  quiz_correct boolean,
  time_spent_seconds smallint,
  CONSTRAINT iq_card_completions_card_id_fkey FOREIGN KEY (card_id) REFERENCES iq_cards(id),
  CONSTRAINT iq_card_completions_pkey PRIMARY KEY (id),
  CONSTRAINT iq_card_completions_profile_id_card_id_key UNIQUE (profile_id, card_id)
);

CREATE TABLE IF NOT EXISTS public.iq_cards (
  id integer NOT NULL DEFAULT nextval('iq_cards_id_seq'::regclass),
  deck_id integer NOT NULL,
  card_type text NOT NULL,
  card_number smallint NOT NULL,
  title text NOT NULL,
  front text NOT NULL,
  back text,
  options jsonb,
  correct_option text,
  coach text,
  sort_order smallint NOT NULL,
  video_url text,
  video_thumbnail text,
  product_id uuid,
  ccr_id uuid,
  CONSTRAINT iq_cards_card_type_check CHECK ((card_type = ANY (ARRAY['fact'::text, 'script'::text, 'demo'::text, 'versus'::text, 'scenario'::text, 'quiz'::text]))),
  CONSTRAINT iq_cards_ccr_id_fkey FOREIGN KEY (ccr_id) REFERENCES competitive_cross_reference(id),
  CONSTRAINT iq_cards_deck_id_fkey FOREIGN KEY (deck_id) REFERENCES iq_decks(id),
  CONSTRAINT iq_cards_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id),
  CONSTRAINT iq_cards_pkey PRIMARY KEY (id),
  CONSTRAINT iq_cards_deck_id_card_number_key UNIQUE (deck_id, card_number)
);

CREATE TABLE IF NOT EXISTS public.iq_courses (
  id integer NOT NULL DEFAULT nextval('iq_courses_id_seq'::regclass),
  pillar text NOT NULL,
  course_key text NOT NULL,
  name text NOT NULL,
  subtitle text,
  icon text,
  brand_id uuid,
  zone_level smallint DEFAULT 1,
  category text,
  sort_order smallint NOT NULL,
  CONSTRAINT iq_courses_pillar_check CHECK ((pillar = ANY (ARRAY['sales_iq'::text, 'product_iq'::text, 'brand_iq'::text, 'leadership_iq'::text]))),
  CONSTRAINT iq_courses_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT iq_courses_pkey PRIMARY KEY (id),
  CONSTRAINT iq_courses_course_key_key UNIQUE (course_key)
);

CREATE TABLE IF NOT EXISTS public.iq_customer_interactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  shift_id uuid NOT NULL,
  queue_entry_id uuid,
  customer_waiting_id uuid,
  interaction_source text,
  interaction_type text DEFAULT 'walk_in'::text,
  salesperson_user_id uuid NOT NULL,
  queue_notification_id uuid,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  accepted_at timestamp with time zone,
  ended_at timestamp with time zone,
  outcome text,
  is_anonymous boolean NOT NULL DEFAULT false,
  contact_id uuid,
  account_id uuid,
  opportunity_id uuid,
  internal_interaction_id text,
  notes text,
  crm_sync_status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  handoff_from_user_id uuid,
  follow_up_date date,
  no_follow_up boolean NOT NULL DEFAULT false,
  reason_not_purchased text,
  CONSTRAINT iq_customer_interactions_account_id_fkey FOREIGN KEY (account_id) REFERENCES aicrm_accounts(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_interactions_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES aicrm_contacts(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_interactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_interactions_customer_waiting_id_fkey FOREIGN KEY (customer_waiting_id) REFERENCES iq_customer_waiting_queue(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_interactions_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES aicrm_opportunities(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_interactions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_customer_interactions_queue_entry_id_fkey FOREIGN KEY (queue_entry_id) REFERENCES iq_up_queue_entries(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_interactions_salesperson_user_id_fkey FOREIGN KEY (salesperson_user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_customer_interactions_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES iq_shift_records(id) ON DELETE CASCADE,
  CONSTRAINT iq_customer_interactions_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_customer_interactions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_interactions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_customer_product_interest (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid NOT NULL,
  customer_waiting_id uuid NOT NULL,
  category text,
  brand text,
  product_name text,
  price numeric,
  stock_status text,
  delivery_date date,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_customer_product_interest_customer_waiting_id_fkey FOREIGN KEY (customer_waiting_id) REFERENCES iq_customer_waiting_queue(id) ON DELETE CASCADE,
  CONSTRAINT iq_customer_product_interest_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_customer_waiting_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  shift_id uuid,
  entered_by uuid,
  assigned_user_id uuid,
  customer_display_name text,
  customer_group_size integer NOT NULL DEFAULT 1,
  customer_description text,
  customer_category text,
  requested_source text,
  requested_employee_user_id uuid,
  requested_salesperson_reason text,
  priority integer NOT NULL DEFAULT 1,
  status iq_customer_wait_status NOT NULL DEFAULT 'waiting_for_assignment'::iq_customer_wait_status,
  arrival_time timestamp with time zone NOT NULL DEFAULT now(),
  timer_started_at timestamp with time zone,
  timer_expires_at timestamp with time zone,
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 3,
  is_anonymous boolean NOT NULL DEFAULT false,
  last_notification_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  is_returning_customer boolean NOT NULL DEFAULT false,
  referred_by text,
  customer_phone text,
  customer_email text,
  purchase_timeframe text,
  lead_source text,
  customer_needs text,
  crm_contact_id uuid,
  crm_deal_id uuid,
  CONSTRAINT iq_customer_waiting_queue_priority_check CHECK (((priority >= 1) AND (priority <= 5))),
  CONSTRAINT iq_customer_waiting_queue_assigned_user_id_fkey FOREIGN KEY (assigned_user_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_waiting_queue_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_waiting_queue_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_waiting_queue_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_customer_waiting_queue_requested_employee_user_id_fkey FOREIGN KEY (requested_employee_user_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_waiting_queue_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES iq_shift_records(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_waiting_queue_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_customer_waiting_queue_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_customer_waiting_queue_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_deck_completions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  deck_id integer NOT NULL,
  completed_at timestamp with time zone DEFAULT now(),
  quiz_score smallint,
  CONSTRAINT iq_deck_completions_deck_id_fkey FOREIGN KEY (deck_id) REFERENCES iq_decks(id),
  CONSTRAINT iq_deck_completions_pkey PRIMARY KEY (id),
  CONSTRAINT iq_deck_completions_profile_id_deck_id_key UNIQUE (profile_id, deck_id)
);

CREATE TABLE IF NOT EXISTS public.iq_decks (
  id integer NOT NULL DEFAULT nextval('iq_decks_id_seq'::regclass),
  lane_id integer NOT NULL,
  deck_number smallint NOT NULL,
  title text NOT NULL,
  description text,
  estimated_minutes smallint DEFAULT 5,
  sort_order smallint NOT NULL,
  course_id integer,
  CONSTRAINT iq_decks_course_id_fkey FOREIGN KEY (course_id) REFERENCES iq_courses(id),
  CONSTRAINT iq_decks_lane_id_fkey FOREIGN KEY (lane_id) REFERENCES iq_lanes(id),
  CONSTRAINT iq_decks_pkey PRIMARY KEY (id),
  CONSTRAINT iq_decks_lane_id_deck_number_key UNIQUE (lane_id, deck_number)
);

CREATE TABLE IF NOT EXISTS public.iq_floor_managers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  manager_user_id uuid NOT NULL,
  role_name text NOT NULL DEFAULT 'sales_manager'::text,
  coverage_start timestamp with time zone NOT NULL DEFAULT now(),
  coverage_end timestamp with time zone,
  is_active boolean NOT NULL DEFAULT true,
  is_remote boolean NOT NULL DEFAULT false,
  replacement_user_id uuid,
  status_text text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  CONSTRAINT iq_floor_managers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_floor_managers_manager_user_id_fkey FOREIGN KEY (manager_user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_floor_managers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_floor_managers_replacement_user_id_fkey FOREIGN KEY (replacement_user_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_floor_managers_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_floor_managers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_floor_managers_pkey PRIMARY KEY (id),
  CONSTRAINT iq_floor_managers_organization_id_store_id_manager_user_id__key UNIQUE (organization_id, store_id, manager_user_id, is_active)
);

CREATE TABLE IF NOT EXISTS public.iq_gate_attempts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  gate_id integer NOT NULL,
  attempted_at timestamp with time zone DEFAULT now(),
  score smallint,
  passed boolean DEFAULT false,
  manager_approved boolean DEFAULT false,
  manager_notes text,
  CONSTRAINT iq_gate_attempts_gate_id_fkey FOREIGN KEY (gate_id) REFERENCES iq_gates(id),
  CONSTRAINT iq_gate_attempts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_gates (
  id integer NOT NULL DEFAULT nextval('iq_gates_id_seq'::regclass),
  from_zone_id integer NOT NULL,
  to_zone_id integer NOT NULL,
  gate_type text NOT NULL,
  quiz_questions jsonb,
  passing_score smallint DEFAULT 80,
  manager_checklist jsonb,
  description text,
  CONSTRAINT iq_gates_gate_type_check CHECK ((gate_type = ANY (ARRAY['quiz'::text, 'manager_signoff'::text, 'both'::text]))),
  CONSTRAINT iq_gates_from_zone_id_fkey FOREIGN KEY (from_zone_id) REFERENCES iq_zones(id),
  CONSTRAINT iq_gates_to_zone_id_fkey FOREIGN KEY (to_zone_id) REFERENCES iq_zones(id),
  CONSTRAINT iq_gates_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_hourly_traffic_summaries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  bucket_start timestamp with time zone NOT NULL,
  raw_traffic integer NOT NULL DEFAULT 0,
  adjusted_traffic integer NOT NULL DEFAULT 0,
  customer_groups integer NOT NULL DEFAULT 0,
  ups_created integer NOT NULL DEFAULT 0,
  customers_served integer NOT NULL DEFAULT 0,
  open_rotation_minutes integer NOT NULL DEFAULT 0,
  staffing_minimum integer NOT NULL DEFAULT 0,
  staffing_recommended integer NOT NULL DEFAULT 0,
  avg_wait_seconds integer,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_hourly_traffic_summaries_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_hourly_traffic_summaries_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_hourly_traffic_summaries_pkey PRIMARY KEY (id),
  CONSTRAINT iq_hourly_traffic_summaries_organization_id_store_id_bucket_key UNIQUE (organization_id, store_id, bucket_start)
);

CREATE TABLE IF NOT EXISTS public.iq_integration_links (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  iq_system_record_type text NOT NULL,
  iq_system_record_id uuid NOT NULL,
  crmai_record_type text,
  crmai_record_id uuid,
  external_system text,
  external_id text,
  last_synced_at timestamp with time zone,
  sync_status text NOT NULL DEFAULT 'pending'::text,
  last_error text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid DEFAULT auth.uid(),
  CONSTRAINT iq_integration_links_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_integration_links_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_integration_links_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_integration_links_pkey PRIMARY KEY (id),
  CONSTRAINT iq_integration_links_organization_id_iq_system_record_type__key UNIQUE (organization_id, iq_system_record_type, iq_system_record_id, external_system)
);

CREATE TABLE IF NOT EXISTS public.iq_intelligence_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  event_type text NOT NULL,
  event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  observed_at timestamp with time zone NOT NULL DEFAULT now(),
  actor_user_id uuid,
  correlation_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_intelligence_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_intelligence_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_intelligence_events_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_intelligence_events_pkey PRIMARY KEY (id)
);

-- =========================
-- TABLES: iq_l* through iz*
-- =========================

CREATE TABLE IF NOT EXISTS public.iq_lanes (
  id integer NOT NULL DEFAULT nextval('iq_lanes_id_seq'::regclass),
  zone_id integer NOT NULL,
  lane_key text NOT NULL,
  name text NOT NULL,
  description text,
  pillar text NOT NULL,
  sort_order smallint NOT NULL,
  CONSTRAINT iq_lanes_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES iq_zones(id),
  CONSTRAINT iq_lanes_pkey PRIMARY KEY (id),
  CONSTRAINT iq_lanes_zone_id_lane_key_key UNIQUE (zone_id, lane_key)
);

CREATE TABLE IF NOT EXISTS public.iq_missed_and_potential_missed_ups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  interaction_id uuid,
  queue_entry_id uuid,
  reported_by uuid NOT NULL,
  employee_user_id uuid,
  reason text,
  is_potential boolean NOT NULL DEFAULT false,
  is_excused boolean,
  affects_kpi boolean NOT NULL DEFAULT true,
  queue_consequence jsonb,
  manager_reviewed boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  reviewed_at timestamp with time zone,
  reviewed_by uuid,
  notes text,
  CONSTRAINT iq_missed_and_potential_missed_ups_employee_user_id_fkey FOREIGN KEY (employee_user_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_missed_and_potential_missed_ups_interaction_id_fkey FOREIGN KEY (interaction_id) REFERENCES iq_customer_interactions(id) ON DELETE CASCADE,
  CONSTRAINT iq_missed_and_potential_missed_ups_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_missed_and_potential_missed_ups_queue_entry_id_fkey FOREIGN KEY (queue_entry_id) REFERENCES iq_up_queue_entries(id) ON DELETE SET NULL,
  CONSTRAINT iq_missed_and_potential_missed_ups_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_missed_and_potential_missed_ups_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_missed_and_potential_missed_ups_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_missed_and_potential_missed_ups_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  notification_type text NOT NULL,
  title text NOT NULL,
  body text,
  icon text,
  action_url text,
  product_id uuid,
  course_id integer,
  brand_id uuid,
  ccr_id uuid,
  badge_id integer,
  target_audience text NOT NULL DEFAULT 'all_reps'::text,
  org_id uuid,
  is_read boolean NOT NULL DEFAULT false,
  read_at timestamp with time zone,
  rep_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_notifications_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES iq_badges(id) ON DELETE SET NULL,
  CONSTRAINT iq_notifications_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE SET NULL,
  CONSTRAINT iq_notifications_ccr_id_fkey FOREIGN KEY (ccr_id) REFERENCES competitive_cross_reference(id) ON DELETE SET NULL,
  CONSTRAINT iq_notifications_course_id_fkey FOREIGN KEY (course_id) REFERENCES iq_courses(id) ON DELETE SET NULL,
  CONSTRAINT iq_notifications_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE SET NULL,
  CONSTRAINT iq_notifications_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_open_rotation_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  start_at timestamp with time zone NOT NULL DEFAULT now(),
  end_at timestamp with time zone,
  started_by uuid NOT NULL,
  reason text,
  is_active boolean NOT NULL DEFAULT true,
  active_customer_count integer NOT NULL DEFAULT 0,
  waiting_customer_count integer NOT NULL DEFAULT 0,
  customer_volume integer NOT NULL DEFAULT 0,
  notes text,
  closed_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_open_rotation_sessions_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_open_rotation_sessions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_open_rotation_sessions_started_by_fkey FOREIGN KEY (started_by) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_open_rotation_sessions_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_open_rotation_sessions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_product_cards (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  brand_id uuid,
  course_id integer,
  card_type text NOT NULL DEFAULT 'product_spotlight'::text,
  title text NOT NULL,
  content jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  is_new_launch boolean NOT NULL DEFAULT false,
  is_discontinued boolean NOT NULL DEFAULT false,
  is_clearance boolean NOT NULL DEFAULT false,
  is_end_of_life boolean NOT NULL DEFAULT false,
  pim_synced_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_product_cards_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT iq_product_cards_course_id_fkey FOREIGN KEY (course_id) REFERENCES iq_courses(id),
  CONSTRAINT iq_product_cards_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT iq_product_cards_pkey PRIMARY KEY (id),
  CONSTRAINT uq_iq_product_cards_product_id UNIQUE (product_id)
);

CREATE TABLE IF NOT EXISTS public.iq_queue_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  waiting_customer_id uuid NOT NULL,
  queue_entry_id uuid NOT NULL,
  assigned_user_id uuid NOT NULL,
  generated_at timestamp with time zone NOT NULL DEFAULT now(),
  sent_at timestamp with time zone,
  delivered_at timestamp with time zone,
  opened_at timestamp with time zone,
  accepted_at timestamp with time zone,
  declined_at timestamp with time zone,
  timed_out_at timestamp with time zone,
  status iq_notification_status NOT NULL DEFAULT 'created'::iq_notification_status,
  delivery_channel _text[] NOT NULL DEFAULT '{in_app}'::text[],
  vibration boolean NOT NULL DEFAULT true,
  sound boolean NOT NULL DEFAULT true,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  CONSTRAINT iq_queue_notifications_assigned_user_id_fkey FOREIGN KEY (assigned_user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_queue_notifications_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_queue_notifications_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_queue_notifications_queue_entry_id_fkey FOREIGN KEY (queue_entry_id) REFERENCES iq_up_queue_entries(id) ON DELETE CASCADE,
  CONSTRAINT iq_queue_notifications_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_queue_notifications_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_queue_notifications_waiting_customer_id_fkey FOREIGN KEY (waiting_customer_id) REFERENCES iq_customer_waiting_queue(id) ON DELETE CASCADE,
  CONSTRAINT iq_queue_notifications_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_queue_snapshots (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  shift_id uuid,
  event_type text NOT NULL,
  queue_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  current_up_user_id uuid,
  next_in_line_user_id uuid,
  active_customer_count integer NOT NULL DEFAULT 0,
  waiting_customer_count integer NOT NULL DEFAULT 0,
  acting_user_id uuid,
  trigger_user_id uuid,
  triggered_by text,
  notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_queue_snapshots_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_queue_snapshots_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES iq_shift_records(id) ON DELETE SET NULL,
  CONSTRAINT iq_queue_snapshots_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_queue_snapshots_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_rep_badges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  org_id uuid NOT NULL,
  badge_id integer NOT NULL,
  earned_at timestamp with time zone DEFAULT now(),
  score smallint,
  verified_by uuid,
  certificate_number text,
  CONSTRAINT iq_rep_badges_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES iq_badges(id),
  CONSTRAINT iq_rep_badges_pkey PRIMARY KEY (id),
  CONSTRAINT iq_rep_badges_profile_id_badge_id_key UNIQUE (profile_id, badge_id)
);

CREATE TABLE IF NOT EXISTS public.iq_rep_progress (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  profile_id uuid NOT NULL,
  org_id uuid NOT NULL,
  current_zone_id integer,
  zone_started_at timestamp with time zone,
  placement_score jsonb,
  total_cards_completed integer DEFAULT 0,
  current_streak integer DEFAULT 0,
  longest_streak integer DEFAULT 0,
  last_activity_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT iq_rep_progress_current_zone_id_fkey FOREIGN KEY (current_zone_id) REFERENCES iq_zones(id),
  CONSTRAINT iq_rep_progress_pkey PRIMARY KEY (id),
  CONSTRAINT iq_rep_progress_profile_id_org_id_key UNIQUE (profile_id, org_id)
);

CREATE TABLE IF NOT EXISTS public.iq_roleplay_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  rep_id uuid NOT NULL,
  org_id uuid,
  persona text NOT NULL,
  session_type text NOT NULL DEFAULT 'roleplay'::text,
  topic text,
  brand_id uuid,
  product_id uuid,
  data_sources_used jsonb DEFAULT '[]'::jsonb,
  messages jsonb DEFAULT '[]'::jsonb,
  score smallint,
  feedback text,
  duration_seconds integer,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  completed_at timestamp with time zone,
  CONSTRAINT iq_roleplay_sessions_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT iq_roleplay_sessions_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id),
  CONSTRAINT iq_roleplay_sessions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_shift_records (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  user_id uuid NOT NULL,
  role_name text NOT NULL DEFAULT 'salesperson'::text,
  login_at timestamp with time zone NOT NULL DEFAULT now(),
  logout_at timestamp with time zone,
  scheduled_start timestamp with time zone,
  actual_start timestamp with time zone NOT NULL DEFAULT now(),
  device_session text,
  initial_status iq_status_type NOT NULL DEFAULT 'available'::iq_status_type,
  late_or_on_time text,
  shift_end_reason text,
  status_version integer NOT NULL DEFAULT 1,
  total_logged_in_seconds integer NOT NULL DEFAULT 0,
  available_seconds integer NOT NULL DEFAULT 0,
  unavailable_seconds integer NOT NULL DEFAULT 0,
  customer_facing_seconds integer NOT NULL DEFAULT 0,
  active_selling_seconds integer NOT NULL DEFAULT 0,
  break_seconds integer NOT NULL DEFAULT 0,
  lunch_seconds integer NOT NULL DEFAULT 0,
  administrative_seconds integer NOT NULL DEFAULT 0,
  customers_served integer NOT NULL DEFAULT 0,
  ups_accepted integer NOT NULL DEFAULT 0,
  ups_missed integer NOT NULL DEFAULT 0,
  ups_disputed integer NOT NULL DEFAULT 0,
  follow_ups_created integer NOT NULL DEFAULT 0,
  opportunities_created integer NOT NULL DEFAULT 0,
  closed_sales integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  closed_at timestamp with time zone,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  is_greeter boolean NOT NULL DEFAULT false,
  CONSTRAINT iq_shift_records_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_shift_records_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_shift_records_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_shift_records_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_shift_records_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_shift_records_pkey PRIMARY KEY (id),
  CONSTRAINT iq_shift_records_organization_id_store_id_user_id_is_active_key UNIQUE (organization_id, store_id, user_id, is_active)
);

CREATE TABLE IF NOT EXISTS public.iq_staffing_predictions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  prediction_date date NOT NULL DEFAULT CURRENT_DATE,
  bucket_start timestamp with time zone NOT NULL,
  bucket_end timestamp with time zone NOT NULL,
  predicted_customer_groups integer,
  min_sales_staff integer NOT NULL DEFAULT 0,
  recommended_sales_staff integer NOT NULL DEFAULT 0,
  recommended_manager_cover boolean NOT NULL DEFAULT false,
  expected_wait_seconds integer,
  open_rotation_probability numeric(5,2),
  confidence numeric(5,2),
  source text,
  model_version text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  CONSTRAINT iq_staffing_predictions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_staffing_predictions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_staffing_predictions_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_staffing_predictions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_status_sessions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  shift_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  store_id uuid,
  user_id uuid NOT NULL,
  status iq_status_type NOT NULL,
  is_unavailable_reason_required boolean NOT NULL DEFAULT false,
  unavailable_reason text,
  reason_note text,
  started_at timestamp with time zone NOT NULL DEFAULT now(),
  ended_at timestamp with time zone,
  source_channel text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_status_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_status_sessions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_status_sessions_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES iq_shift_records(id) ON DELETE CASCADE,
  CONSTRAINT iq_status_sessions_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_status_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_status_sessions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_store_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  queue_name text NOT NULL DEFAULT 'Main Floor'::text,
  is_open_rotation_enabled boolean NOT NULL DEFAULT true,
  break_max_per_shift integer NOT NULL DEFAULT 2,
  paid_break_minutes integer NOT NULL DEFAULT 30,
  lunch_minutes integer NOT NULL DEFAULT 30,
  lunch_minimum_per_shift integer NOT NULL DEFAULT 1,
  lunch_alert_grace_minutes integer NOT NULL DEFAULT 5,
  queue_skip_statuses jsonb NOT NULL DEFAULT '["with_customer", "break", "lunch", "temporarily_unavailable", "off_sales_floor"]'::jsonb,
  missed_up_queue_rule text NOT NULL DEFAULT 'end'::text,
  return_to_queue_after_timeout boolean NOT NULL DEFAULT true,
  auto_open_rotation_wait_threshold integer NOT NULL DEFAULT 20,
  open_rotation_reason_default text NOT NULL DEFAULT 'demand_surge'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  greeter_enabled boolean NOT NULL DEFAULT false,
  greeter_user_id uuid,
  accept_up_timeout_seconds integer NOT NULL DEFAULT 60,
  accept_up_action text NOT NULL DEFAULT 'next_in_line'::text,
  CONSTRAINT iq_store_settings_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_store_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_store_settings_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_store_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_store_settings_pkey PRIMARY KEY (id),
  CONSTRAINT iq_store_settings_organization_id_store_id_key UNIQUE (organization_id, store_id)
);

CREATE TABLE IF NOT EXISTS public.iq_traffic_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  traffic_source_id uuid NOT NULL,
  raw_entries integer NOT NULL DEFAULT 0,
  adjusted_entries integer NOT NULL DEFAULT 0,
  customer_groups integer NOT NULL DEFAULT 0,
  captured_at timestamp with time zone NOT NULL DEFAULT now(),
  event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid DEFAULT auth.uid(),
  CONSTRAINT iq_traffic_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_traffic_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_traffic_events_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_traffic_events_traffic_source_id_fkey FOREIGN KEY (traffic_source_id) REFERENCES iq_traffic_sources(id) ON DELETE CASCADE,
  CONSTRAINT iq_traffic_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_traffic_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  source_name text NOT NULL,
  source_kind text,
  device_id text,
  provider text,
  entrance_name text,
  timezone text,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid DEFAULT auth.uid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT iq_traffic_sources_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_traffic_sources_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_traffic_sources_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_traffic_sources_pkey PRIMARY KEY (id),
  CONSTRAINT iq_traffic_sources_organization_id_source_name_key UNIQUE (organization_id, source_name)
);

CREATE TABLE IF NOT EXISTS public.iq_up_disputes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  interaction_id uuid,
  queue_snapshot_before jsonb,
  queue_snapshot_after jsonb,
  disputed_by uuid NOT NULL,
  affected_employee_id uuid,
  reason text,
  status text NOT NULL DEFAULT 'open'::text,
  manager_decision text,
  manager_notes text,
  manager_id uuid,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid DEFAULT auth.uid(),
  CONSTRAINT iq_up_disputes_affected_employee_id_fkey FOREIGN KEY (affected_employee_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_up_disputes_disputed_by_fkey FOREIGN KEY (disputed_by) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_up_disputes_interaction_id_fkey FOREIGN KEY (interaction_id) REFERENCES iq_customer_interactions(id) ON DELETE SET NULL,
  CONSTRAINT iq_up_disputes_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT iq_up_disputes_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_up_disputes_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_up_disputes_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_up_disputes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.iq_up_queue_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_id uuid,
  shift_id uuid NOT NULL,
  user_id uuid NOT NULL,
  queue_position integer NOT NULL,
  join_order timestamp with time zone NOT NULL DEFAULT now(),
  is_in_queue boolean NOT NULL DEFAULT true,
  is_current_up boolean NOT NULL DEFAULT false,
  is_next_in_line boolean NOT NULL DEFAULT false,
  status_code iq_status_type NOT NULL DEFAULT 'available'::iq_status_type,
  is_available_for_assignment boolean NOT NULL DEFAULT true,
  hold_count integer NOT NULL DEFAULT 0,
  is_suspended boolean NOT NULL DEFAULT false,
  version bigint NOT NULL DEFAULT 1,
  last_assignment_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid DEFAULT auth.uid(),
  updated_by uuid DEFAULT auth.uid(),
  up_offered_at timestamp with time zone,
  CONSTRAINT iq_up_queue_entries_queue_position_check CHECK ((queue_position >= 0)),
  CONSTRAINT iq_up_queue_entries_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_up_queue_entries_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT iq_up_queue_entries_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES iq_shift_records(id) ON DELETE CASCADE,
  CONSTRAINT iq_up_queue_entries_store_id_fkey FOREIGN KEY (store_id) REFERENCES org_locations(id),
  CONSTRAINT iq_up_queue_entries_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT iq_up_queue_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT iq_up_queue_entries_pkey PRIMARY KEY (id),
  CONSTRAINT iq_up_queue_entries_shift_id_key UNIQUE (shift_id)
);

CREATE TABLE IF NOT EXISTS public.iq_zones (
  id integer NOT NULL DEFAULT nextval('iq_zones_id_seq'::regclass),
  zone_number smallint NOT NULL,
  name text NOT NULL,
  subtitle text,
  description text,
  day_start text,
  day_end text,
  gate_description text,
  sort_order smallint NOT NULL,
  CONSTRAINT iq_zones_pkey PRIMARY KEY (id),
  CONSTRAINT iq_zones_zone_number_key UNIQUE (zone_number)
);

-- =========================
-- TABLES: k* through o*
-- =========================

CREATE TABLE IF NOT EXISTS public.kpi_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid,
  event_type text NOT NULL,
  ref_table text,
  ref_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT kpi_events_event_type_check CHECK ((event_type = ANY (ARRAY['recording_uploaded'::text, 'recording_transcribed'::text, 'recording_analyzed'::text, 'roleplay_completed'::text, 'coaching_generated'::text, 'email_reviewed'::text, 'presentation_sent'::text, 'follow_up_completed'::text]))),
  CONSTRAINT kpi_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT kpi_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.media_discovery_candidates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  run_id uuid,
  brand_name text NOT NULL,
  model_raw text,
  model_normalized text,
  matched_product_id uuid,
  match_type text,
  match_confidence numeric DEFAULT 0,
  match_reasons _text[] DEFAULT '{}'::text[],
  alternate_product_ids _uuid[] DEFAULT '{}'::uuid[],
  asset_category text NOT NULL,
  asset_type text,
  title text,
  description text,
  url text NOT NULL,
  embed_url text,
  thumbnail_url text,
  file_name text,
  mime_type text,
  file_size_bytes bigint,
  checksum text,
  language text DEFAULT 'en'::text,
  country text DEFAULT 'CA'::text,
  platform text,
  external_video_id text,
  duration_seconds integer,
  resolution text,
  has_captions boolean,
  page_count integer,
  doc_version text,
  effective_date date,
  applicable_models _text[] DEFAULT '{}'::text[],
  width_px integer,
  height_px integer,
  image_role text,
  angle text,
  finish_shown text,
  background text,
  source_url text NOT NULL,
  source_domain text,
  source_type text DEFAULT 'manufacturer'::text,
  source_confidence numeric DEFAULT 0.5,
  is_official_source boolean DEFAULT false,
  publication_date date,
  status text NOT NULL DEFAULT 'discovered'::text,
  duplicate_of uuid,
  requires_review boolean DEFAULT true,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  review_notes text,
  submitted_to_table text,
  submitted_record_id uuid,
  submitted_at timestamp with time zone,
  raw_metadata jsonb DEFAULT '{}'::jsonb,
  extraction_evidence jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT media_discovery_candidates_run_id_fkey FOREIGN KEY (run_id) REFERENCES media_discovery_runs(id),
  CONSTRAINT media_discovery_candidates_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.media_discovery_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  source_id uuid,
  run_type text NOT NULL DEFAULT 'full_discovery'::text,
  brand_name text,
  model text,
  product_id uuid,
  status text NOT NULL DEFAULT 'queued'::text,
  pages_fetched integer DEFAULT 0,
  candidates_created integer DEFAULT 0,
  duplicates_found integer DEFAULT 0,
  errors_count integer DEFAULT 0,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  duration_ms integer,
  error_log jsonb DEFAULT '[]'::jsonb,
  run_config jsonb DEFAULT '{}'::jsonb,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT media_discovery_runs_source_id_fkey FOREIGN KEY (source_id) REFERENCES media_source_registry(id),
  CONSTRAINT media_discovery_runs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.media_source_registry (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  brand_name text NOT NULL,
  brand_id uuid,
  parent_company text,
  country text DEFAULT 'CA'::text,
  source_type text NOT NULL DEFAULT 'product_page'::text,
  domain text NOT NULL,
  product_page_pattern text,
  support_page_pattern text,
  document_library_url text,
  sitemap_url text,
  youtube_channel_id text,
  vimeo_account_id text,
  cdn_domains _text[] DEFAULT '{}'::text[],
  allowed_paths _text[] DEFAULT '{}'::text[],
  denied_paths _text[] DEFAULT '{}'::text[],
  crawl_frequency text DEFAULT 'weekly'::text,
  rate_limit_ms integer DEFAULT 2000,
  parser_type text DEFAULT 'generic'::text,
  is_active boolean DEFAULT true,
  priority integer DEFAULT 5,
  last_successful_run timestamp with time zone,
  last_error text,
  reliability_score numeric DEFAULT 1.0,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT media_source_registry_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.memory_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL,
  tenant_id uuid,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  scope text NOT NULL DEFAULT 'session'::text,
  consent_id uuid,
  session_id uuid,
  source_agent text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone,
  CONSTRAINT memory_events_scope_check CHECK ((scope = ANY (ARRAY['session'::text, 'durable'::text]))),
  CONSTRAINT memory_events_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES memory_subjects(id) ON DELETE CASCADE,
  CONSTRAINT memory_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.memory_facts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  subject_id uuid NOT NULL,
  tenant_id uuid,
  memory_type text NOT NULL,
  key text NOT NULL,
  value jsonb NOT NULL,
  confidence numeric(4,3) NOT NULL DEFAULT 0.7,
  freshness date NOT NULL DEFAULT CURRENT_DATE,
  derived_from uuid,
  consent_id uuid,
  superseded_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT memory_facts_derived_from_fkey FOREIGN KEY (derived_from) REFERENCES memory_events(id),
  CONSTRAINT memory_facts_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES memory_subjects(id) ON DELETE CASCADE,
  CONSTRAINT memory_facts_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES memory_facts(id),
  CONSTRAINT memory_facts_pkey PRIMARY KEY (id),
  CONSTRAINT memory_facts_subject_id_tenant_id_key_created_at_key UNIQUE (subject_id, tenant_id, key, created_at)
);

CREATE TABLE IF NOT EXISTS public.memory_subject_links (
  subject_id uuid NOT NULL,
  link_kind text NOT NULL,
  link_value text NOT NULL,
  verified boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT memory_subject_links_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES memory_subjects(id) ON DELETE CASCADE,
  CONSTRAINT memory_subject_links_pkey PRIMARY KEY (subject_id, link_kind, link_value)
);

CREATE TABLE IF NOT EXISTS public.memory_subjects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  subject_kind text NOT NULL,
  display_name text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT memory_subjects_subject_kind_check CHECK ((subject_kind = ANY (ARRAY['customer'::text, 'employee'::text, 'trade_contact'::text, 'org'::text]))),
  CONSTRAINT memory_subjects_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.metric_definitions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  metric_key text NOT NULL,
  metric_label text NOT NULL,
  metric_category text NOT NULL DEFAULT 'sales'::text,
  unit text DEFAULT 'currency'::text,
  formula text,
  is_budgetable boolean DEFAULT true,
  is_visible boolean DEFAULT true,
  sort_order integer DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT metric_definitions_metric_category_check CHECK ((metric_category = ANY (ARRAY['sales'::text, 'warranty'::text, 'brand'::text, 'coaching'::text, 'training'::text, 'floor'::text, 'custom'::text]))),
  CONSTRAINT metric_definitions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT metric_definitions_pkey PRIMARY KEY (id),
  CONSTRAINT metric_definitions_organization_id_metric_key_key UNIQUE (organization_id, metric_key)
);

CREATE TABLE IF NOT EXISTS public.metric_snapshots (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  location_id uuid,
  user_id uuid,
  period_type text NOT NULL,
  period_key text NOT NULL,
  metric_key text NOT NULL,
  actual_value numeric NOT NULL DEFAULT 0,
  target_value numeric,
  variance_value numeric,
  variance_pct numeric,
  prior_year_value numeric,
  yoy_change_pct numeric,
  computed_at timestamp with time zone NOT NULL DEFAULT now(),
  metric_subtype text,
  CONSTRAINT metric_snapshots_period_type_check CHECK ((period_type = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text, 'quarterly'::text, 'annual'::text]))),
  CONSTRAINT metric_snapshots_location_id_fkey FOREIGN KEY (location_id) REFERENCES org_locations(id),
  CONSTRAINT metric_snapshots_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT metric_snapshots_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT metric_snapshots_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.mfr_invites (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email text NOT NULL,
  vendor_slug text,
  vendor_name text,
  invite_role text DEFAULT 'manufacturer'::text,
  code text NOT NULL,
  status text DEFAULT 'pending'::text,
  invited_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  accepted_at timestamp with time zone,
  vendor_id uuid,
  persona text NOT NULL DEFAULT 'manufacturer'::text,
  expires_at timestamp with time zone DEFAULT (now() + '30 days'::interval),
  accepted_by uuid,
  group_id uuid,
  scope_type text NOT NULL DEFAULT 'brand'::text,
  retailer_brand_ids _uuid[] DEFAULT '{}'::uuid[],
  retailer_account_type text,
  retailer_company text,
  retailer_exclusive_codes _text[] DEFAULT '{}'::text[],
  CONSTRAINT mfr_invites_group_id_fkey FOREIGN KEY (group_id) REFERENCES mfr_vendor_groups(id) ON DELETE CASCADE,
  CONSTRAINT mfr_invites_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES auth.users(id),
  CONSTRAINT mfr_invites_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES mfr_vendors(id) ON DELETE CASCADE,
  CONSTRAINT mfr_invites_pkey PRIMARY KEY (id),
  CONSTRAINT mfr_invites_code_key UNIQUE (code)
);

CREATE TABLE IF NOT EXISTS public.mfr_members (
  user_id uuid NOT NULL,
  vendor_id uuid NOT NULL,
  member_role text DEFAULT 'editor'::text,
  created_at timestamp with time zone DEFAULT now(),
  role text,
  status text,
  invited_by uuid,
  approved_by uuid,
  invitation_id uuid,
  approved_at timestamp with time zone,
  activated_at timestamp with time zone,
  suspended_at timestamp with time zone,
  revoked_at timestamp with time zone,
  expires_at timestamp with time zone,
  updated_at timestamp with time zone,
  created_by uuid,
  updated_by uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT mfr_members_active_approval_check CHECK (((status IS DISTINCT FROM 'active'::text) OR ((role IS NOT NULL) AND (approved_by IS NOT NULL) AND (approved_at IS NOT NULL) AND (activated_at IS NOT NULL)))),
  CONSTRAINT mfr_members_role_check CHECK (((role IS NULL) OR (role = ANY (ARRAY['vendor_owner'::text, 'vendor_admin'::text, 'brand_admin'::text, 'product_editor'::text, 'product_reviewer'::text, 'asset_editor'::text, 'training_editor'::text, 'viewer'::text])))),
  CONSTRAINT mfr_members_status_check CHECK (((status IS NULL) OR (status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'revoked'::text])))),
  CONSTRAINT mfr_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT mfr_members_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES mfr_vendors(id) ON DELETE CASCADE,
  CONSTRAINT mfr_members_pkey PRIMARY KEY (user_id, vendor_id)
);

CREATE TABLE IF NOT EXISTS public.mfr_user_roles (
  user_id uuid NOT NULL,
  is_admin boolean DEFAULT false,
  is_manufacturer boolean DEFAULT false,
  is_retailer boolean DEFAULT true,
  is_builder boolean DEFAULT false,
  is_designer boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT mfr_user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT mfr_user_roles_pkey PRIMARY KEY (user_id)
);

CREATE TABLE IF NOT EXISTS public.mfr_vendor_groups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT mfr_vendor_groups_pkey PRIMARY KEY (id),
  CONSTRAINT mfr_vendor_groups_name_key UNIQUE (name),
  CONSTRAINT mfr_vendor_groups_slug_key UNIQUE (slug)
);

CREATE TABLE IF NOT EXISTS public.mfr_vendors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  slug text NOT NULL,
  name text NOT NULL,
  tier text,
  website text,
  logo_url text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  group_id uuid,
  brand_id uuid,
  tagline text,
  focus text,
  story text,
  "rightFor" text,
  "sellingAngles" jsonb DEFAULT '[]'::jsonb,
  "specGuides" jsonb DEFAULT '[]'::jsonb,
  videos jsonb DEFAULT '[]'::jsonb,
  "specCenter" text,
  CONSTRAINT mfr_vendors_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT mfr_vendors_group_id_fkey FOREIGN KEY (group_id) REFERENCES mfr_vendor_groups(id) ON DELETE SET NULL,
  CONSTRAINT mfr_vendors_pkey PRIMARY KEY (id),
  CONSTRAINT mfr_vendors_slug_key UNIQUE (slug)
);

CREATE TABLE IF NOT EXISTS public.org_invites (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  invited_email text NOT NULL,
  invite_code text NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'::text),
  role text NOT NULL DEFAULT 'member'::text,
  org_role_id uuid,
  manager_id uuid,
  invited_by uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  accepted_at timestamp with time zone,
  expires_at timestamp with time zone NOT NULL DEFAULT (now() + '7 days'::interval),
  CONSTRAINT org_invites_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'member'::text]))),
  CONSTRAINT org_invites_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'expired'::text, 'revoked'::text]))),
  CONSTRAINT org_invites_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES auth.users(id),
  CONSTRAINT org_invites_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES auth.users(id),
  CONSTRAINT org_invites_org_role_id_fkey FOREIGN KEY (org_role_id) REFERENCES org_roles(id),
  CONSTRAINT org_invites_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT org_invites_pkey PRIMARY KEY (id),
  CONSTRAINT org_invites_invite_code_key UNIQUE (invite_code)
);

CREATE TABLE IF NOT EXISTS public.org_kpis (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  kpi_name text NOT NULL,
  description text,
  weight numeric DEFAULT 1.0,
  target_score numeric DEFAULT 8.0,
  active boolean DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT org_kpis_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT org_kpis_pkey PRIMARY KEY (id),
  CONSTRAINT org_kpis_organization_id_kpi_name_key UNIQUE (organization_id, kpi_name)
);

CREATE TABLE IF NOT EXISTS public.org_location_members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  location_id uuid NOT NULL,
  user_id uuid NOT NULL,
  is_primary boolean DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT org_location_members_location_id_fkey FOREIGN KEY (location_id) REFERENCES org_locations(id) ON DELETE CASCADE,
  CONSTRAINT org_location_members_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT org_location_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT org_location_members_pkey PRIMARY KEY (id),
  CONSTRAINT org_location_members_location_id_user_id_key UNIQUE (location_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.org_locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  parent_id uuid,
  location_type text NOT NULL,
  name text NOT NULL,
  code text,
  address text,
  city text,
  province_state text,
  country text DEFAULT 'CA'::text,
  timezone text DEFAULT 'America/Toronto'::text,
  is_active boolean NOT NULL DEFAULT true,
  opened_at date,
  closed_at date,
  iq_store_id uuid,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT org_locations_location_type_check CHECK ((location_type = ANY (ARRAY['corporate'::text, 'region'::text, 'district'::text, 'store'::text]))),
  CONSTRAINT org_locations_iq_store_id_fkey FOREIGN KEY (iq_store_id) REFERENCES iq_store_settings(id),
  CONSTRAINT org_locations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT org_locations_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES org_locations(id),
  CONSTRAINT org_locations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.org_roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  role_name text NOT NULL,
  role_level integer NOT NULL,
  description text,
  can_view_team_analytics boolean DEFAULT false,
  can_view_all_analytics boolean DEFAULT false,
  can_manage_targets boolean DEFAULT false,
  can_manage_kpis boolean DEFAULT false,
  can_manage_users boolean DEFAULT false,
  can_manage_roles boolean DEFAULT false,
  active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT org_roles_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT org_roles_pkey PRIMARY KEY (id),
  CONSTRAINT org_roles_organization_id_role_name_key UNIQUE (organization_id, role_name)
);

CREATE TABLE IF NOT EXISTS public.org_targets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  target_type text NOT NULL,
  target_name text,
  target_value numeric,
  target_currency text DEFAULT 'CAD'::text,
  fiscal_year integer,
  fiscal_period text,
  assigned_to_role_id uuid,
  assigned_to_user_id uuid,
  created_by_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT org_targets_assigned_to_role_id_fkey FOREIGN KEY (assigned_to_role_id) REFERENCES org_roles(id) ON DELETE SET NULL,
  CONSTRAINT org_targets_assigned_to_user_id_fkey FOREIGN KEY (assigned_to_user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT org_targets_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES auth.users(id),
  CONSTRAINT org_targets_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT org_targets_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.organization_brands (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  brand_id uuid NOT NULL,
  assignment text DEFAULT 'optional'::text,
  assigned_by uuid,
  assigned_at timestamp with time zone DEFAULT now(),
  CONSTRAINT organization_brands_assignment_check CHECK ((assignment = ANY (ARRAY['required'::text, 'recommended'::text, 'optional'::text, 'manager_only'::text, 'installer_only'::text]))),
  CONSTRAINT organization_brands_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES auth.users(id),
  CONSTRAINT organization_brands_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT organization_brands_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT organization_brands_pkey PRIMARY KEY (id),
  CONSTRAINT organization_brands_organization_id_brand_id_key UNIQUE (organization_id, brand_id)
);

CREATE TABLE IF NOT EXISTS public.organization_members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text NOT NULL DEFAULT 'member'::text,
  status text NOT NULL DEFAULT 'active'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  org_role_id uuid,
  manager_id uuid,
  CONSTRAINT organization_members_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'admin'::text, 'manager'::text, 'member'::text, 'viewer'::text]))),
  CONSTRAINT organization_members_status_check CHECK ((status = ANY (ARRAY['invited'::text, 'active'::text, 'suspended'::text, 'removed'::text]))),
  CONSTRAINT organization_members_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES organization_members(id) ON DELETE SET NULL,
  CONSTRAINT organization_members_org_role_id_fkey FOREIGN KEY (org_role_id) REFERENCES org_roles(id) ON DELETE SET NULL,
  CONSTRAINT organization_members_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT organization_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT organization_members_pkey PRIMARY KEY (id),
  CONSTRAINT organization_members_organization_id_user_id_key UNIQUE (organization_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.organizations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL,
  tenant_type text NOT NULL DEFAULT 'retail_company'::text,
  status text NOT NULL DEFAULT 'active'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp with time zone,
  tier text NOT NULL DEFAULT 'starter'::text,
  stripe_customer_id text,
  stripe_subscription_id text,
  subscription_status text,
  billing_email text,
  trial_ends_at timestamp with time zone,
  canceled_at timestamp with time zone,
  CONSTRAINT organizations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'archived'::text]))),
  CONSTRAINT organizations_subscription_status_check CHECK ((subscription_status = ANY (ARRAY['active'::text, 'past_due'::text, 'canceled'::text, 'trialing'::text]))),
  CONSTRAINT organizations_tenant_type_check CHECK ((tenant_type = ANY (ARRAY['appliance_iq_internal'::text, 'retail_company'::text, 'independent_seller'::text, 'demo'::text]))),
  CONSTRAINT organizations_tier_check CHECK ((tier = ANY (ARRAY['starter'::text, 'pro'::text, 'enterprise'::text, 'demo'::text]))),
  CONSTRAINT organizations_pkey PRIMARY KEY (id),
  CONSTRAINT organizations_slug_key UNIQUE (slug)
);

-- =========================
-- TABLES: p* through pih*
-- =========================

CREATE TABLE IF NOT EXISTS public.persona_communication_protocol (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  persona_name text NOT NULL,
  handoff_triggers _text[],
  handoff_style text,
  handoff_template text,
  debate_approach text,
  defer_pattern text,
  sibling_dynamic text,
  max_response_length text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT persona_communication_protocol_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT persona_communication_protocol_pkey PRIMARY KEY (id),
  CONSTRAINT persona_communication_protocol_organization_id_persona_name_key UNIQUE (organization_id, persona_name)
);

CREATE TABLE IF NOT EXISTS public.pim_asset_types (
  id text NOT NULL,
  category text NOT NULL,
  label text NOT NULL,
  description text,
  icon text,
  sort_order integer DEFAULT 0,
  CONSTRAINT pim_asset_types_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_marketing_assets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  brand_id uuid,
  asset_type text NOT NULL,
  title text NOT NULL,
  description text,
  file_url text NOT NULL,
  file_name text,
  file_size_bytes bigint,
  mime_type text,
  dimensions text,
  color_mode text,
  dpi integer,
  language text DEFAULT 'en'::text,
  locale text,
  campaign text,
  season text,
  effective_date date,
  expiry_date date,
  is_current boolean DEFAULT true,
  usage_rights text,
  requires_approval boolean DEFAULT false,
  source text DEFAULT 'manufacturer'::text,
  uploaded_by uuid,
  approved boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  available_from timestamp with time zone,
  available_until timestamp with time zone,
  audience_tiers _text[] NOT NULL DEFAULT ARRAY['all'::text],
  exclusive_codes _text[] DEFAULT '{}'::text[],
  embargoed boolean NOT NULL DEFAULT false,
  verification_status text NOT NULL DEFAULT 'unverified'::text,
  manufacturer_verified boolean NOT NULL DEFAULT false,
  keywords _text[] NOT NULL DEFAULT '{}'::text[],
  storage_path text,
  CONSTRAINT pim_marketing_assets_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT pim_marketing_assets_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_marketing_assets_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id),
  CONSTRAINT pim_marketing_assets_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_price_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  msrp numeric,
  sale_price numeric,
  lowest_price numeric,
  lowest_price_source text,
  price_currency text DEFAULT 'CAD'::text,
  source_url text,
  checked_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT pim_price_history_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_price_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_accessories (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  accessory_product_id uuid,
  relationship_type text NOT NULL DEFAULT 'optional'::text,
  accessory_model text,
  accessory_name text NOT NULL,
  accessory_description text,
  msrp numeric,
  image_url text,
  is_required boolean DEFAULT false,
  is_included boolean DEFAULT false,
  category text,
  display_order integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT pim_product_accessories_accessory_product_id_fkey FOREIGN KEY (accessory_product_id) REFERENCES aiq_products(id),
  CONSTRAINT pim_product_accessories_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_accessories_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_certifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  cert_type text NOT NULL,
  cert_body text,
  cert_number text,
  cert_url text,
  issued_date date,
  expiry_date date,
  is_current boolean DEFAULT true,
  energy_star_rating numeric,
  energy_guide_url text,
  annual_energy_kwh numeric,
  annual_energy_cost numeric,
  water_usage_gallons numeric,
  noise_level_dba numeric,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT pim_product_certifications_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_certifications_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_dimensions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  dimension_type text NOT NULL DEFAULT 'product'::text,
  width_inches numeric,
  height_inches numeric,
  depth_inches numeric,
  depth_with_door_inches numeric,
  depth_with_handle_inches numeric,
  weight_lbs numeric,
  cutout_width numeric,
  cutout_height numeric,
  cutout_depth numeric,
  shipping_width numeric,
  shipping_height numeric,
  shipping_depth numeric,
  shipping_weight_lbs numeric,
  door_swing_clearance numeric,
  door_swing_direction text,
  ada_compliant boolean DEFAULT false,
  dim_drawing_url text,
  cad_file_url text,
  revit_file_url text,
  sketchup_file_url text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT pim_product_dimensions_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_dimensions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  brand_id uuid,
  doc_type text NOT NULL,
  title text NOT NULL,
  description text,
  file_url text NOT NULL,
  file_name text,
  file_size_bytes bigint,
  mime_type text DEFAULT 'application/pdf'::text,
  page_count integer,
  language text DEFAULT 'en'::text,
  locale text,
  version text,
  effective_date date,
  expiry_date date,
  is_current boolean DEFAULT true,
  replaces_doc_id uuid,
  requires_auth boolean DEFAULT false,
  source text DEFAULT 'manufacturer'::text,
  uploaded_by uuid,
  approved boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  available_from timestamp with time zone,
  available_until timestamp with time zone,
  audience_tiers _text[] NOT NULL DEFAULT ARRAY['all'::text],
  exclusive_codes _text[] DEFAULT '{}'::text[],
  embargoed boolean NOT NULL DEFAULT false,
  verification_status text NOT NULL DEFAULT 'unverified'::text,
  manufacturer_verified boolean NOT NULL DEFAULT false,
  keywords _text[] NOT NULL DEFAULT '{}'::text[],
  storage_path text,
  CONSTRAINT pim_product_documents_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT pim_product_documents_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_documents_replaces_doc_id_fkey FOREIGN KEY (replaces_doc_id) REFERENCES pim_product_documents(id),
  CONSTRAINT pim_product_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id),
  CONSTRAINT pim_product_documents_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_features (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  feature_category text NOT NULL,
  feature_name text NOT NULL,
  feature_value text,
  feature_description text,
  is_key_feature boolean DEFAULT false,
  is_differentiator boolean DEFAULT false,
  icon text,
  display_order integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT pim_product_features_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_features_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_images (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  brand_id uuid,
  image_type text NOT NULL DEFAULT 'hero'::text,
  file_url text NOT NULL,
  cdn_url text,
  alt_text text,
  caption text,
  width_px integer,
  height_px integer,
  file_size_bytes bigint,
  mime_type text,
  background text DEFAULT 'white'::text,
  finish_shown text,
  angle text,
  is_primary boolean DEFAULT false,
  display_order integer DEFAULT 0,
  source text DEFAULT 'manufacturer'::text,
  uploaded_by uuid,
  approved boolean DEFAULT false,
  approved_by uuid,
  approved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  available_from timestamp with time zone,
  available_until timestamp with time zone,
  audience_tiers _text[] NOT NULL DEFAULT ARRAY['all'::text],
  exclusive_codes _text[] DEFAULT '{}'::text[],
  embargoed boolean NOT NULL DEFAULT false,
  verification_status text NOT NULL DEFAULT 'unverified'::text,
  manufacturer_verified boolean NOT NULL DEFAULT false,
  keywords _text[] NOT NULL DEFAULT '{}'::text[],
  storage_path text,
  CONSTRAINT pim_product_images_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id),
  CONSTRAINT pim_product_images_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT pim_product_images_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_images_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id),
  CONSTRAINT pim_product_images_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_rebates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  brand_id uuid,
  rebate_name text NOT NULL,
  rebate_type text NOT NULL DEFAULT 'mail_in'::text,
  rebate_amount numeric,
  rebate_percent numeric,
  min_purchase numeric,
  max_rebate numeric,
  start_date date NOT NULL,
  end_date date NOT NULL,
  submission_deadline date,
  rebate_form_url text,
  terms_url text,
  promo_code text,
  stackable boolean DEFAULT false,
  regions _text[],
  eligible_channels _text[],
  notes text,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  available_from timestamp with time zone,
  available_until timestamp with time zone,
  audience_tiers _text[] NOT NULL DEFAULT ARRAY['all'::text],
  exclusive_codes _text[] DEFAULT '{}'::text[],
  embargoed boolean NOT NULL DEFAULT false,
  CONSTRAINT pim_product_rebates_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT pim_product_rebates_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_rebates_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_product_videos (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  brand_id uuid,
  video_type text NOT NULL DEFAULT 'product_overview'::text,
  title text NOT NULL,
  description text,
  video_url text,
  embed_url text,
  thumbnail_url text,
  duration_seconds integer,
  resolution text,
  language text DEFAULT 'en'::text,
  has_captions boolean DEFAULT false,
  is_360 boolean DEFAULT false,
  source text DEFAULT 'manufacturer'::text,
  display_order integer DEFAULT 0,
  uploaded_by uuid,
  approved boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  available_from timestamp with time zone,
  available_until timestamp with time zone,
  audience_tiers _text[] NOT NULL DEFAULT ARRAY['all'::text],
  exclusive_codes _text[] DEFAULT '{}'::text[],
  embargoed boolean NOT NULL DEFAULT false,
  transcript text,
  caption_url text,
  country text,
  platform text,
  external_video_id text,
  publication_date date,
  last_verified_at timestamp with time zone,
  verification_status text NOT NULL DEFAULT 'unverified'::text,
  manufacturer_verified boolean NOT NULL DEFAULT false,
  keywords _text[] NOT NULL DEFAULT '{}'::text[],
  ai_summary text,
  is_current boolean NOT NULL DEFAULT true,
  replaces_video_id uuid,
  source_reference text,
  archived_at timestamp with time zone,
  CONSTRAINT pim_product_videos_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT pim_product_videos_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_product_videos_replaces_video_id_fkey FOREIGN KEY (replaces_video_id) REFERENCES pim_product_videos(id) ON DELETE SET NULL,
  CONSTRAINT pim_product_videos_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id),
  CONSTRAINT pim_product_videos_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_retailer_prices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  brand_name text NOT NULL,
  model text NOT NULL,
  retailer_name text NOT NULL,
  retailer_url text,
  product_url text,
  price numeric,
  regular_price numeric,
  on_sale boolean DEFAULT false,
  sale_label text,
  in_stock boolean,
  stock_note text,
  condition text DEFAULT 'new'::text,
  is_open_box boolean DEFAULT false,
  is_clearance boolean DEFAULT false,
  is_refurbished boolean DEFAULT false,
  is_floor_model boolean DEFAULT false,
  shipping_available boolean,
  shipping_cost numeric,
  free_delivery boolean,
  price_currency text DEFAULT 'CAD'::text,
  checked_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  country text DEFAULT 'CA'::text,
  CONSTRAINT pim_retailer_prices_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_retailer_prices_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_spec_discovery_jobs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'queued'::text,
  source_url text,
  attempts integer NOT NULL DEFAULT 0,
  specs_found integer DEFAULT 0,
  dimensions_found boolean DEFAULT false,
  images_found integer DEFAULT 0,
  description_found boolean DEFAULT false,
  extraction_method text,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  last_error text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT pim_spec_discovery_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'needs_source'::text, 'running'::text, 'completed'::text, 'failed'::text, 'skipped'::text]))),
  CONSTRAINT pim_spec_discovery_jobs_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id),
  CONSTRAINT pim_spec_discovery_jobs_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pim_video_discovery_jobs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'queued'::text,
  source_url text,
  attempts integer NOT NULL DEFAULT 0,
  videos_found integer NOT NULL DEFAULT 0,
  last_error text,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT pim_video_discovery_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'completed'::text, 'needs_source'::text, 'failed'::text]))),
  CONSTRAINT pim_video_discovery_jobs_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_video_discovery_jobs_pkey PRIMARY KEY (id),
  CONSTRAINT pim_video_discovery_jobs_product_id_key UNIQUE (product_id)
);

CREATE TABLE IF NOT EXISTS public.pim_warranty_details (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  warranty_type text NOT NULL DEFAULT 'standard'::text,
  coverage_name text NOT NULL,
  coverage_years integer,
  coverage_months integer,
  coverage_description text,
  parts_covered boolean DEFAULT true,
  labor_covered boolean DEFAULT false,
  in_home_service boolean DEFAULT false,
  transferable boolean DEFAULT false,
  registration_required boolean DEFAULT false,
  registration_url text,
  warranty_doc_url text,
  extended_available boolean DEFAULT false,
  extended_provider text,
  extended_years integer,
  extended_cost numeric,
  notes text,
  display_order integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT pim_warranty_details_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT pim_warranty_details_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.pipeline_stages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_terminal boolean NOT NULL DEFAULT false,
  is_default boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  color text DEFAULT '#5b6b85'::text,
  required_fields jsonb DEFAULT '[]'::jsonb,
  win_probability integer,
  CONSTRAINT pipeline_stages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT pipeline_stages_pkey PRIMARY KEY (id)
);

-- =========================
-- TABLES: piq* through q*
-- =========================

CREATE TABLE IF NOT EXISTS public.piq_audience_tiers (
  id text NOT NULL,
  label text NOT NULL,
  description text,
  icon text,
  sort_order integer DEFAULT 0,
  CONSTRAINT piq_audience_tiers_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.piq_notification_reads (
  notification_id uuid NOT NULL,
  user_id uuid NOT NULL,
  read_at timestamp with time zone DEFAULT now(),
  CONSTRAINT piq_notification_reads_notification_id_fkey FOREIGN KEY (notification_id) REFERENCES piq_notifications(id) ON DELETE CASCADE,
  CONSTRAINT piq_notification_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT piq_notification_reads_pkey PRIMARY KEY (notification_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.piq_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  kind text NOT NULL,
  title text NOT NULL,
  body text,
  brand_name text,
  product_id uuid,
  asset_table text,
  asset_id uuid,
  link_url text,
  audience_tiers _text[] NOT NULL DEFAULT ARRAY['all'::text],
  exclusive_codes _text[] DEFAULT '{}'::text[],
  publish_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT piq_notifications_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.piq_retailer_brands (
  user_id uuid NOT NULL,
  brand_id uuid NOT NULL,
  granted_by uuid,
  granted_at timestamp with time zone DEFAULT now(),
  CONSTRAINT piq_retailer_brands_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT piq_retailer_brands_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT piq_retailer_brands_pkey PRIMARY KEY (user_id, brand_id)
);

CREATE TABLE IF NOT EXISTS public.piq_retailer_profiles (
  user_id uuid NOT NULL,
  organization_id uuid,
  company_name text,
  account_type text NOT NULL DEFAULT 'independent'::text,
  buying_group text,
  exclusive_codes _text[] DEFAULT '{}'::text[],
  region text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT piq_retailer_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT piq_retailer_profiles_pkey PRIMARY KEY (user_id)
);

CREATE TABLE IF NOT EXISTS public.privacy_jurisdictions (
  code text NOT NULL,
  label text NOT NULL,
  recording_mode text NOT NULL DEFAULT 'structured_notes_only'::text,
  employee_policy_required boolean NOT NULL DEFAULT true,
  notes text,
  counsel_signoff boolean NOT NULL DEFAULT false,
  signoff_by text,
  signoff_at timestamp with time zone,
  version integer NOT NULL DEFAULT 1,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT privacy_jurisdictions_recording_mode_check CHECK ((recording_mode = ANY (ARRAY['structured_notes_only'::text, 'transcription_optin'::text, 'prohibited'::text]))),
  CONSTRAINT privacy_jurisdictions_pkey PRIMARY KEY (code)
);

CREATE TABLE IF NOT EXISTS public.privacy_purge_log (
  id bigint NOT NULL DEFAULT nextval('privacy_purge_log_id_seq'::regclass),
  data_class text NOT NULL,
  purged_rows integer NOT NULL,
  job_run uuid NOT NULL,
  ran_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT privacy_purge_log_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.privacy_retention_policies (
  data_class text NOT NULL,
  retain_days integer NOT NULL,
  legal_hold_exempt boolean NOT NULL DEFAULT false,
  notes text,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT privacy_retention_policies_pkey PRIMARY KEY (data_class)
);

CREATE TABLE IF NOT EXISTS public.product_design_assets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  brand_id uuid,
  model_number text NOT NULL,
  asset_type text NOT NULL,
  file_format text NOT NULL,
  file_url text,
  storage_path text,
  source_type text NOT NULL DEFAULT 'manufacturer'::text,
  source_url text,
  version text,
  is_official boolean NOT NULL DEFAULT false,
  is_verified boolean NOT NULL DEFAULT false,
  manufacturer_verified boolean NOT NULL DEFAULT false,
  registration_required boolean NOT NULL DEFAULT false,
  licence_notes text,
  verification_status text NOT NULL DEFAULT 'unverified'::text,
  verified_by uuid,
  verified_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  replaces_asset_id uuid,
  is_current boolean NOT NULL DEFAULT true,
  title text,
  description text,
  file_size_bytes bigint,
  keywords _text[] NOT NULL DEFAULT '{}'::text[],
  display_order integer DEFAULT 0,
  audience_tiers _text[] NOT NULL DEFAULT ARRAY['all'::text],
  exclusive_codes _text[] DEFAULT '{}'::text[],
  embargoed boolean NOT NULL DEFAULT false,
  available_from timestamp with time zone,
  available_until timestamp with time zone,
  approved boolean NOT NULL DEFAULT false,
  approved_by uuid,
  approved_at timestamp with time zone,
  CONSTRAINT product_design_assets_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE SET NULL,
  CONSTRAINT product_design_assets_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT product_design_assets_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT product_design_assets_replaces_asset_id_fkey FOREIGN KEY (replaces_asset_id) REFERENCES product_design_assets(id),
  CONSTRAINT product_design_assets_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT product_design_assets_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.product_installation_geometry (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  measurement_unit text NOT NULL DEFAULT 'in'::text,
  width numeric,
  height numeric,
  depth numeric,
  cutout_width numeric,
  cutout_height numeric,
  cutout_depth numeric,
  door_clearance numeric,
  side_clearance numeric,
  rear_clearance numeric,
  top_clearance numeric,
  electrical_location jsonb,
  gas_location jsonb,
  water_location jsonb,
  drain_location jsonb,
  geometry_notes text,
  source_url text,
  is_verified boolean NOT NULL DEFAULT false,
  verified_by uuid,
  verified_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT product_installation_geometry_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id) ON DELETE CASCADE,
  CONSTRAINT product_installation_geometry_verified_by_fkey FOREIGN KEY (verified_by) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT product_installation_geometry_pkey PRIMARY KEY (id),
  CONSTRAINT product_installation_geometry_product_id_key UNIQUE (product_id)
);

CREATE TABLE IF NOT EXISTS public.product_iq_brand_scopes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  brand_id uuid,
  vendor_id uuid,
  capabilities _text[] NOT NULL DEFAULT '{}'::text[],
  status text NOT NULL DEFAULT 'active'::text,
  approved_by uuid,
  approved_at timestamp with time zone,
  expires_at timestamp with time zone,
  reason text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_iq_brand_scopes_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id) ON DELETE CASCADE,
  CONSTRAINT product_iq_brand_scopes_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.product_iq_governance_audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  product_id uuid,
  entity_type text,
  entity_id uuid,
  action text,
  actor_id uuid,
  actor_kind text,
  reason text,
  old_record jsonb,
  new_record jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_iq_governance_audit_log_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.product_iq_platform_roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  user_id uuid NOT NULL,
  role text NOT NULL,
  status text NOT NULL DEFAULT 'active'::text,
  granted_by uuid,
  granted_at timestamp with time zone DEFAULT now(),
  expires_at timestamp with time zone,
  reason text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_iq_platform_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT product_iq_platform_roles_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.product_lifecycle (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid,
  brand_id uuid,
  brand_name text NOT NULL,
  model_number text NOT NULL,
  product_name text,
  category text,
  announced_date date,
  launch_date date,
  discontinued_date date,
  end_of_life_date date,
  lifecycle_status text NOT NULL DEFAULT 'active'::text,
  predecessor_model text,
  predecessor_product_id uuid,
  successor_model text,
  successor_product_id uuid,
  generation integer,
  model_year integer,
  changes_from_predecessor text,
  discontinuation_reason text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_lifecycle_lifecycle_status_check CHECK ((lifecycle_status = ANY (ARRAY['announced'::text, 'active'::text, 'discontinued'::text, 'end_of_life'::text, 'replaced'::text]))),
  CONSTRAINT product_lifecycle_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT product_lifecycle_predecessor_product_id_fkey FOREIGN KEY (predecessor_product_id) REFERENCES aiq_products(id),
  CONSTRAINT product_lifecycle_product_id_fkey FOREIGN KEY (product_id) REFERENCES aiq_products(id),
  CONSTRAINT product_lifecycle_successor_product_id_fkey FOREIGN KEY (successor_product_id) REFERENCES aiq_products(id),
  CONSTRAINT product_lifecycle_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  brand text NOT NULL,
  model text NOT NULL,
  name text NOT NULL,
  category text,
  msrp numeric(12,2),
  cost numeric(12,2),
  margin_pct numeric(5,2),
  warranty_months integer,
  in_stock boolean NOT NULL DEFAULT true,
  description text,
  embedding vector,
  embedding_model text,
  source_hash text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  aiq_product_id uuid,
  CONSTRAINT products_aiq_product_id_fkey FOREIGN KEY (aiq_product_id) REFERENCES aiq_products(id),
  CONSTRAINT products_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT products_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.profiles (
  user_id uuid NOT NULL,
  full_name text,
  email text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  id uuid NOT NULL,
  CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT profiles_pkey PRIMARY KEY (user_id)
);

-- =========================
-- TABLES: r* through z*
-- =========================

CREATE TABLE IF NOT EXISTS public.recording_transcripts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  recording_id uuid NOT NULL,
  content text NOT NULL,
  language text,
  model text,
  status text NOT NULL DEFAULT 'completed'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT recording_transcripts_status_check CHECK ((status = ANY (ARRAY['completed'::text, 'failed'::text]))),
  CONSTRAINT recording_transcripts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT recording_transcripts_recording_id_fkey FOREIGN KEY (recording_id) REFERENCES sales_recordings(id) ON DELETE CASCADE,
  CONSTRAINT recording_transcripts_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.retailer_buying_groups (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  retailer_id uuid NOT NULL,
  buying_group_id uuid NOT NULL,
  membership_tier text,
  CONSTRAINT retailer_buying_groups_buying_group_id_fkey FOREIGN KEY (buying_group_id) REFERENCES buying_groups(id) ON DELETE CASCADE,
  CONSTRAINT retailer_buying_groups_retailer_id_fkey FOREIGN KEY (retailer_id) REFERENCES aiq_retailers(id) ON DELETE CASCADE,
  CONSTRAINT retailer_buying_groups_pkey PRIMARY KEY (id),
  CONSTRAINT retailer_buying_groups_retailer_id_buying_group_id_key UNIQUE (retailer_id, buying_group_id)
);

CREATE TABLE IF NOT EXISTS public.retailer_locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  retailer_id uuid NOT NULL,
  store_name text,
  address_line1 text NOT NULL,
  address_line2 text,
  city text NOT NULL,
  province_state text NOT NULL,
  postal_zip text,
  country text NOT NULL DEFAULT 'CA'::text,
  phone text,
  email text,
  latitude numeric(10,7),
  longitude numeric(10,7),
  is_flagship boolean DEFAULT false,
  is_showroom boolean DEFAULT true,
  is_outlet boolean DEFAULT false,
  is_warehouse boolean DEFAULT false,
  store_type text DEFAULT 'retail'::text,
  operating_hours text,
  services _text[],
  brands_featured _text[],
  notes text,
  status text DEFAULT 'active'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT retailer_locations_retailer_id_fkey FOREIGN KEY (retailer_id) REFERENCES aiq_retailers(id) ON DELETE CASCADE,
  CONSTRAINT retailer_locations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.sales_recordings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid,
  kind text NOT NULL DEFAULT 'sales_pitch'::text,
  file_path text NOT NULL,
  mime_type text,
  duration_seconds integer,
  status text NOT NULL DEFAULT 'uploaded'::text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  crm_record_id uuid,
  crm_record_type text,
  recording_source text NOT NULL DEFAULT 'browser'::text,
  file_name text,
  file_size_bytes bigint,
  consent_confirmed boolean NOT NULL DEFAULT false,
  consent_confirmed_at timestamp with time zone,
  transcript_id uuid,
  coaching_review_id uuid,
  deal_id uuid,
  CONSTRAINT sales_recordings_crm_record_type_check CHECK (((crm_record_type IS NULL) OR (crm_record_type = ANY (ARRAY['deal'::text, 'contact'::text, 'company'::text])))),
  CONSTRAINT sales_recordings_kind_check CHECK ((kind = ANY (ARRAY['sales_pitch'::text, 'voice_call'::text]))),
  CONSTRAINT sales_recordings_recording_source_check CHECK ((recording_source = ANY (ARRAY['browser'::text, 'wearable'::text, 'phone_system'::text, 'uploaded_file'::text, 'meeting_platform'::text]))),
  CONSTRAINT sales_recordings_status_check CHECK ((status = ANY (ARRAY['uploaded'::text, 'transcribing'::text, 'transcribed'::text, 'analyzing'::text, 'complete'::text, 'failed'::text]))),
  CONSTRAINT sales_recordings_coaching_review_id_fkey FOREIGN KEY (coaching_review_id) REFERENCES ai_coaching_reviews(id) ON DELETE SET NULL,
  CONSTRAINT sales_recordings_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id) ON DELETE SET NULL,
  CONSTRAINT sales_recordings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT sales_recordings_transcript_id_fkey FOREIGN KEY (transcript_id) REFERENCES recording_transcripts(id) ON DELETE SET NULL,
  CONSTRAINT sales_recordings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL,
  CONSTRAINT sales_recordings_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.sales_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  location_id uuid,
  user_id uuid,
  deal_id uuid,
  transaction_date date NOT NULL DEFAULT CURRENT_DATE,
  item_count integer NOT NULL DEFAULT 1,
  item_value numeric NOT NULL DEFAULT 0,
  order_total numeric NOT NULL DEFAULT 0,
  warranty_offered boolean DEFAULT false,
  warranty_sold boolean DEFAULT false,
  warranty_value numeric DEFAULT 0,
  warranty_type text,
  brand text,
  product_category text,
  delivery_value numeric DEFAULT 0,
  install_value numeric DEFAULT 0,
  haul_away_value numeric DEFAULT 0,
  invoice_number text,
  is_return boolean DEFAULT false,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT sales_transactions_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id),
  CONSTRAINT sales_transactions_location_id_fkey FOREIGN KEY (location_id) REFERENCES org_locations(id),
  CONSTRAINT sales_transactions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
  CONSTRAINT sales_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT sales_transactions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.service_iq_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  category text NOT NULL,
  name text NOT NULL,
  channel text NOT NULL,
  subject text,
  body text NOT NULL,
  usage_notes text,
  tags _text[] DEFAULT '{}'::text[],
  sort_order integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT service_iq_templates_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'phone'::text, 'text'::text, 'internal'::text, 'review_response'::text]))),
  CONSTRAINT service_iq_templates_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_approval_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  submission_id text,
  quote_version integer,
  submitted_by uuid,
  submitted_at timestamp with time zone DEFAULT now(),
  assigned_manager uuid,
  approval_trigger text,
  requested_discount numeric DEFAULT 0,
  requested_expiry timestamp with time zone,
  requested_validity_days integer,
  manager_decision text,
  approved_discount numeric,
  approved_expiry timestamp with time zone,
  conditions text,
  comments text,
  decision_at timestamp with time zone,
  escalated_to uuid,
  escalation_reason text,
  returned_to_rep_at timestamp with time zone,
  customer_send_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_approval_history_assigned_manager_fkey FOREIGN KEY (assigned_manager) REFERENCES auth.users(id),
  CONSTRAINT speciq_approval_history_escalated_to_fkey FOREIGN KEY (escalated_to) REFERENCES auth.users(id),
  CONSTRAINT speciq_approval_history_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_approval_history_package_id_fkey FOREIGN KEY (package_id) REFERENCES speciq_packages(id) ON DELETE CASCADE,
  CONSTRAINT speciq_approval_history_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_approval_history_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_extension_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  existing_expiry timestamp with time zone NOT NULL,
  requested_expiry timestamp with time zone NOT NULL,
  additional_days integer,
  reason text,
  pricing_revalidated boolean DEFAULT false,
  promo_revalidated boolean DEFAULT false,
  inventory_revalidated boolean DEFAULT false,
  rep_notes text,
  requested_by uuid,
  requested_at timestamp with time zone DEFAULT now(),
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  decision text,
  approved_expiry timestamp with time zone,
  manager_comments text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_extension_requests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_extension_requests_package_id_fkey FOREIGN KEY (package_id) REFERENCES speciq_packages(id) ON DELETE CASCADE,
  CONSTRAINT speciq_extension_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_extension_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_extension_requests_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_followup_sequences (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  step_order integer NOT NULL,
  delay_days integer NOT NULL DEFAULT 0,
  action_type text NOT NULL,
  action_label text NOT NULL,
  email_template text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_followup_sequences_action_type_check CHECK ((action_type = ANY (ARRAY['send_package'::text, 'confirm_receipt'::text, 'ask_questions'::text, 'review_pricing'::text, 'followup_promo'::text, 'custom'::text]))),
  CONSTRAINT speciq_followup_sequences_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_followup_sequences_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_package_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  event_type text NOT NULL,
  event_data jsonb DEFAULT '{}'::jsonb,
  ip_address text,
  user_agent text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_package_events_event_type_check CHECK ((event_type = ANY (ARRAY['created'::text, 'sent'::text, 'email_delivered'::text, 'link_opened'::text, 'page_viewed'::text, 'product_clicked'::text, 'downloaded'::text, 'pricing_viewed'::text, 'revision_requested'::text, 'customer_response'::text]))),
  CONSTRAINT speciq_package_events_package_id_fkey FOREIGN KEY (package_id) REFERENCES speciq_packages(id) ON DELETE CASCADE,
  CONSTRAINT speciq_package_events_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_package_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  product_name text NOT NULL,
  brand text,
  model_number text,
  category text,
  subcategory text,
  finish text,
  image_url text,
  width_inches numeric,
  height_inches numeric,
  depth_inches numeric,
  weight_lbs numeric,
  electrical_requirements text,
  gas_requirements text,
  water_requirements text,
  drain_requirements text,
  ventilation_requirements text,
  clearances jsonb DEFAULT '{}'::jsonb,
  cutout_dimensions jsonb DEFAULT '{}'::jsonb,
  door_swing text,
  installation_type text,
  key_benefits text,
  warranty_summary text,
  included_accessories text,
  required_accessories text,
  retailer_notes text,
  specifications jsonb DEFAULT '{}'::jsonb,
  msrp numeric,
  promo_price numeric,
  negotiated_price numeric,
  discount_reason text,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  quantity integer NOT NULL DEFAULT 1,
  extended_msrp numeric,
  extended_promo numeric,
  extended_negotiated numeric,
  aiq_product_id uuid,
  brand_id uuid,
  series text,
  product_line text,
  spec_snapshot jsonb DEFAULT '{}'::jsonb,
  short_description text,
  selected_warranty_id uuid,
  warranty_status text DEFAULT 'none'::text,
  warranty_snapshot jsonb,
  source_comparison_id uuid,
  selection_reason text,
  CONSTRAINT speciq_package_products_aiq_product_id_fkey FOREIGN KEY (aiq_product_id) REFERENCES aiq_products(id),
  CONSTRAINT speciq_package_products_brand_id_fkey FOREIGN KEY (brand_id) REFERENCES brand_catalog(id),
  CONSTRAINT speciq_package_products_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_package_products_package_id_fkey FOREIGN KEY (package_id) REFERENCES speciq_packages(id) ON DELETE CASCADE,
  CONSTRAINT speciq_package_products_selected_warranty_id_fkey FOREIGN KEY (selected_warranty_id) REFERENCES speciq_product_warranties(id),
  CONSTRAINT speciq_package_products_source_comparison_id_fkey FOREIGN KEY (source_comparison_id) REFERENCES ai_product_comparisons(id) ON DELETE SET NULL,
  CONSTRAINT speciq_package_products_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_package_services (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  service_type text NOT NULL,
  description text,
  amount numeric NOT NULL DEFAULT 0,
  taxable boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  product_warranty_id uuid,
  linked_product_id uuid,
  cost numeric DEFAULT 0,
  promo_price numeric,
  msrp numeric DEFAULT 0,
  gross_margin numeric DEFAULT 0,
  CONSTRAINT speciq_package_services_service_type_check CHECK ((service_type = ANY (ARRAY['delivery'::text, 'installation'::text, 'haul_away'::text, 'extended_warranty'::text, 'accessories'::text, 'environmental_fee'::text, 'other'::text]))),
  CONSTRAINT speciq_package_services_linked_product_id_fkey FOREIGN KEY (linked_product_id) REFERENCES speciq_package_products(id),
  CONSTRAINT speciq_package_services_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_package_services_package_id_fkey FOREIGN KEY (package_id) REFERENCES speciq_packages(id) ON DELETE CASCADE,
  CONSTRAINT speciq_package_services_product_warranty_id_fkey FOREIGN KEY (product_warranty_id) REFERENCES speciq_product_warranties(id),
  CONSTRAINT speciq_package_services_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_package_versions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  version_number integer NOT NULL,
  snapshot jsonb NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_package_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_package_versions_package_id_fkey FOREIGN KEY (package_id) REFERENCES speciq_packages(id) ON DELETE CASCADE,
  CONSTRAINT speciq_package_versions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_packages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  project_id uuid NOT NULL,
  package_name text NOT NULL,
  version integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'draft'::text,
  cover_image_url text,
  welcome_message text,
  retailer_disclaimer text,
  include_pricing boolean NOT NULL DEFAULT false,
  share_token text,
  share_url text,
  pdf_url text,
  total_msrp numeric DEFAULT 0,
  total_promo numeric DEFAULT 0,
  total_negotiated numeric DEFAULT 0,
  total_services numeric DEFAULT 0,
  total_tax numeric DEFAULT 0,
  total_final numeric DEFAULT 0,
  total_savings numeric DEFAULT 0,
  promo_expiry_date date,
  created_by uuid,
  approved_by uuid,
  sent_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  volume_discount numeric DEFAULT 0,
  delivery_method text DEFAULT 'delivery'::text,
  tax_rule_id uuid,
  contact_id uuid,
  deal_id uuid,
  salesperson_name text,
  updated_by uuid,
  customer_facing_pricing boolean DEFAULT false,
  project_type text DEFAULT 'single'::text,
  unit_type text,
  unit_count integer DEFAULT 1,
  phase text,
  quote_number text,
  quote_issued_at timestamp with time zone,
  quote_expires_at timestamp with time zone,
  validity_days integer DEFAULT 14,
  validity_type text DEFAULT 'days'::text,
  validity_reason text,
  timezone text DEFAULT 'America/Toronto'::text,
  quote_version integer DEFAULT 1,
  last_revised_at timestamp with time zone,
  approved_at timestamp with time zone,
  customer_facing_pdf_url text,
  approved_pdf_url text,
  approval_status text DEFAULT 'not_required'::text,
  approval_required boolean DEFAULT false,
  approval_reason text,
  submitted_by uuid,
  submitted_at timestamp with time zone,
  assigned_manager_id uuid,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  manager_comments text,
  approval_conditions text,
  approved_expiry_at timestamp with time zone,
  approved_discount numeric DEFAULT 0,
  rejection_reason text,
  escalated_to uuid,
  returned_to_rep_at timestamp with time zone,
  locked boolean DEFAULT false,
  superseded_by uuid,
  supersedes uuid,
  warranty_total numeric DEFAULT 0,
  CONSTRAINT speciq_packages_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'in_progress'::text, 'ready_for_review'::text, 'generated'::text, 'sent'::text, 'accepted'::text, 'archived'::text]))),
  CONSTRAINT speciq_packages_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_packages_assigned_manager_id_fkey FOREIGN KEY (assigned_manager_id) REFERENCES auth.users(id),
  CONSTRAINT speciq_packages_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id),
  CONSTRAINT speciq_packages_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_packages_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id),
  CONSTRAINT speciq_packages_escalated_to_fkey FOREIGN KEY (escalated_to) REFERENCES auth.users(id),
  CONSTRAINT speciq_packages_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_packages_project_id_fkey FOREIGN KEY (project_id) REFERENCES speciq_projects(id) ON DELETE CASCADE,
  CONSTRAINT speciq_packages_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_packages_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_packages_tax_rule_id_fkey FOREIGN KEY (tax_rule_id) REFERENCES speciq_tax_rules(id),
  CONSTRAINT speciq_packages_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_packages_pkey PRIMARY KEY (id),
  CONSTRAINT speciq_packages_share_token_key UNIQUE (share_token)
);

CREATE TABLE IF NOT EXISTS public.speciq_pricing_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  rule_type text NOT NULL,
  rule_value numeric NOT NULL,
  requires_approval boolean NOT NULL DEFAULT false,
  approval_role text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_pricing_rules_rule_type_check CHECK ((rule_type = ANY (ARRAY['min_margin'::text, 'approval_threshold'::text, 'map_alert'::text, 'max_discount_pct'::text, 'volume_discount'::text, 'bundle_discount'::text]))),
  CONSTRAINT speciq_pricing_rules_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_pricing_rules_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_product_warranties (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL,
  package_product_id uuid NOT NULL,
  organization_id uuid NOT NULL,
  warranty_catalog_id uuid,
  warranty_name text NOT NULL,
  warranty_type text NOT NULL,
  warranty_provider text,
  coverage_length_months integer,
  coverage_label text,
  parts_coverage boolean DEFAULT true,
  labour_coverage boolean DEFAULT true,
  designation text DEFAULT 'residential'::text,
  registration_required boolean DEFAULT false,
  transferable boolean DEFAULT false,
  coverage_summary text,
  exclusions text,
  customer_facing_notes text,
  internal_notes text,
  coverage_start_date date,
  coverage_end_date date,
  selling_price numeric DEFAULT 0,
  promo_price numeric,
  msrp numeric DEFAULT 0,
  cost numeric DEFAULT 0,
  taxable boolean DEFAULT true,
  is_included boolean DEFAULT false,
  selection_status text DEFAULT 'selected'::text,
  selected_at timestamp with time zone DEFAULT now(),
  selected_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_product_warranties_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_product_warranties_package_id_fkey FOREIGN KEY (package_id) REFERENCES speciq_packages(id) ON DELETE CASCADE,
  CONSTRAINT speciq_product_warranties_package_product_id_fkey FOREIGN KEY (package_product_id) REFERENCES speciq_package_products(id) ON DELETE CASCADE,
  CONSTRAINT speciq_product_warranties_selected_by_fkey FOREIGN KEY (selected_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_product_warranties_warranty_catalog_id_fkey FOREIGN KEY (warranty_catalog_id) REFERENCES speciq_warranty_catalog(id),
  CONSTRAINT speciq_product_warranties_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_projects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  customer_name text NOT NULL,
  customer_email text,
  customer_phone text,
  project_name text NOT NULL,
  property_address text,
  room_name text,
  builder_name text,
  designer_name text,
  expected_purchase_date date,
  delivery_date date,
  notes text,
  status text NOT NULL DEFAULT 'active'::text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  contact_id uuid,
  deal_id uuid,
  CONSTRAINT speciq_projects_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'archived'::text]))),
  CONSTRAINT speciq_projects_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts(id),
  CONSTRAINT speciq_projects_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_projects_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES crm_deals(id),
  CONSTRAINT speciq_projects_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_projects_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_retailer_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  store_name text,
  store_phone text,
  store_email text,
  store_address text,
  store_city text,
  store_province text,
  store_postal text,
  store_website text,
  logo_url text,
  primary_color text DEFAULT '#0f1f3d'::text,
  secondary_color text DEFAULT '#2f6fed'::text,
  default_disclaimer text,
  default_welcome_message text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  default_validity_days integer DEFAULT 14,
  max_rep_validity_days integer DEFAULT 14,
  max_manager_validity_days integer DEFAULT 30,
  max_store_manager_validity_days integer DEFAULT 60,
  require_approval_for_discount boolean DEFAULT true,
  require_approval_above_amount numeric DEFAULT 0,
  min_margin_percent numeric DEFAULT 0,
  approval_notification_email text,
  commercial_disclaimer text,
  validity_disclaimer text DEFAULT 'This proposal and its pricing are valid for the stated period, subject to product availability and any earlier manufacturer promotion expiry.'::text,
  CONSTRAINT speciq_retailer_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_retailer_settings_pkey PRIMARY KEY (id),
  CONSTRAINT speciq_retailer_settings_organization_id_key UNIQUE (organization_id)
);

CREATE TABLE IF NOT EXISTS public.speciq_subscriptions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  plan text NOT NULL DEFAULT 'starter'::text,
  status text NOT NULL DEFAULT 'trialing'::text,
  max_users integer NOT NULL DEFAULT 1,
  stripe_subscription_id text,
  trial_ends_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_subscriptions_plan_check CHECK ((plan = ANY (ARRAY['starter'::text, 'professional'::text, 'retail_location'::text, 'multi_location'::text, 'builder_designer'::text]))),
  CONSTRAINT speciq_subscriptions_status_check CHECK ((status = ANY (ARRAY['trialing'::text, 'active'::text, 'past_due'::text, 'canceled'::text, 'suspended'::text]))),
  CONSTRAINT speciq_subscriptions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_subscriptions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_tax_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  jurisdiction_name text NOT NULL,
  province_state text,
  country text NOT NULL DEFAULT 'CA'::text,
  gst_rate numeric DEFAULT 0,
  hst_rate numeric DEFAULT 0,
  pst_rate numeric DEFAULT 0,
  qst_rate numeric DEFAULT 0,
  env_fee_rate numeric DEFAULT 0,
  delivery_taxable boolean NOT NULL DEFAULT true,
  installation_taxable boolean NOT NULL DEFAULT true,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_tax_rules_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_tax_rules_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  template_name text NOT NULL,
  cover_config jsonb DEFAULT '{}'::jsonb,
  welcome_message text,
  disclaimer text,
  include_pricing boolean NOT NULL DEFAULT false,
  is_default boolean NOT NULL DEFAULT false,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT speciq_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_templates_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.speciq_warranty_catalog (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  warranty_name text NOT NULL,
  warranty_type text NOT NULL,
  warranty_provider text,
  coverage_length_months integer,
  coverage_label text,
  parts_coverage boolean DEFAULT true,
  labour_coverage boolean DEFAULT true,
  designation text DEFAULT 'residential'::text,
  registration_required boolean DEFAULT false,
  transferable boolean DEFAULT false,
  coverage_summary text,
  exclusions text,
  customer_facing_notes text,
  internal_notes text,
  selling_price numeric DEFAULT 0,
  promo_price numeric,
  msrp numeric DEFAULT 0,
  cost numeric DEFAULT 0,
  taxable boolean DEFAULT true,
  is_included boolean DEFAULT false,
  is_default boolean DEFAULT false,
  applies_to_categories _text[],
  active boolean DEFAULT true,
  sort_order integer DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT speciq_warranty_catalog_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id),
  CONSTRAINT speciq_warranty_catalog_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS public.stripe_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid,
  event_type text NOT NULL,
  event_id text NOT NULL,
  object_id text,
  payload jsonb NOT NULL,
  processed_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT stripe_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
  CONSTRAINT stripe_events_pkey PRIMARY KEY (id),
  CONSTRAINT stripe_events_event_id_key UNIQUE (event_id)
);

-- =========================
-- INDEXES
-- =========================

CREATE INDEX idx_brand_cert_brand ON public.academy_brand_certifications USING btree (brand_id);

CREATE INDEX idx_brand_cert_user ON public.academy_brand_certifications USING btree (user_id);

CREATE INDEX idx_brand_progress_brand ON public.academy_brand_progress USING btree (brand_id);

CREATE INDEX idx_brand_progress_user ON public.academy_brand_progress USING btree (user_id);

CREATE INDEX idx_adm_user_date ON public.academy_daily_metrics USING btree (user_id, metric_date DESC);

CREATE INDEX idx_notifications_org ON public.academy_notifications USING btree (organization_id);

CREATE INDEX idx_notifications_user ON public.academy_notifications USING btree (user_id, read);

CREATE INDEX activities_org_idx ON public.activities USING btree (organization_id, created_at DESC);

CREATE INDEX activities_recording_idx ON public.activities USING btree (related_recording_id) WHERE (related_recording_id IS NOT NULL);

CREATE INDEX ai_assistants_org_idx ON public.ai_assistants USING btree (organization_id);

CREATE INDEX ai_audit_org_idx ON public.ai_audit_events USING btree (organization_id, created_at DESC);

CREATE INDEX abp_org_idx ON public.ai_budget_predictions USING btree (organization_id, prediction_type, created_at DESC);

CREATE INDEX ai_coaching_reviews_act_idx ON public.ai_coaching_reviews USING btree (activity_id);

CREATE INDEX ai_coaching_reviews_org_idx ON public.ai_coaching_reviews USING btree (organization_id, created_at DESC);

CREATE INDEX ai_coaching_reviews_recording_idx ON public.ai_coaching_reviews USING btree (recording_id) WHERE (recording_id IS NOT NULL);

CREATE INDEX ai_conversation_memory_profile_gin_idx ON public.ai_conversation_memory USING gin (profile);

CREATE INDEX ai_conversation_turns_conversation_created_idx ON public.ai_conversation_turns USING btree (conversation_id, created_at);

CREATE INDEX ai_conversations_crm_idx ON public.ai_conversations USING btree (crm_record_type, crm_record_id) WHERE (crm_record_id IS NOT NULL);

CREATE INDEX ai_conversations_user_last_idx ON public.ai_conversations USING btree (user_id, last_message_at DESC);

CREATE INDEX ai_chunks_embedding_idx ON public.ai_knowledge_chunks USING hnsw (embedding vector_cosine_ops);

CREATE INDEX ai_chunks_org_idx ON public.ai_knowledge_chunks USING btree (organization_id, status);

CREATE UNIQUE INDEX ai_manager_assignment_active_case_uq ON public.ai_manager_assignments USING btree (decision_case_id) WHERE (status = ANY (ARRAY['open'::text, 'accepted'::text, 'in_progress'::text, 'blocked'::text]));

CREATE INDEX ai_manager_assignments_assignee_idx ON public.ai_manager_assignments USING btree (organization_id, assigned_to, status, due_at);

CREATE INDEX ai_manager_assignments_org_status_due_idx ON public.ai_manager_assignments USING btree (organization_id, status, due_at);

CREATE UNIQUE INDEX ai_manager_briefs_org_type_period_uidx ON public.ai_manager_briefs USING btree (organization_id, brief_type, COALESCE(period_start, brief_date), COALESCE(period_end, brief_date));

CREATE UNIQUE INDEX ai_manager_escalation_open_uq ON public.ai_manager_escalations USING btree (assignment_id, level) WHERE (status = 'open'::text);

CREATE INDEX ai_manager_escalations_org_status_idx ON public.ai_manager_escalations USING btree (organization_id, status, created_at DESC);

CREATE INDEX ai_manager_task_attachments_assignment_idx ON public.ai_manager_task_attachments USING btree (assignment_id, created_at);

CREATE INDEX ai_manager_task_comments_assignment_idx ON public.ai_manager_task_comments USING btree (assignment_id, created_at);

CREATE INDEX ai_manager_task_history_assignment_idx ON public.ai_manager_task_history USING btree (assignment_id, created_at DESC);

CREATE INDEX ai_personas_org_idx ON public.ai_personas USING btree (organization_id, active);

CREATE INDEX ai_product_comparisons_conversation_idx ON public.ai_product_comparisons USING btree (conversation_id) WHERE (conversation_id IS NOT NULL);

CREATE INDEX ai_product_comparisons_crm_idx ON public.ai_product_comparisons USING btree (crm_record_type, crm_record_id) WHERE (crm_record_id IS NOT NULL);

CREATE INDEX ai_product_comparisons_org_updated_idx ON public.ai_product_comparisons USING btree (organization_id, updated_at DESC);

CREATE INDEX ai_product_comparisons_user_updated_idx ON public.ai_product_comparisons USING btree (user_id, updated_at DESC);

CREATE INDEX ai_actions_org_idx ON public.ai_proposed_actions USING btree (organization_id, status);

CREATE INDEX ai_requests_org_idx ON public.ai_requests USING btree (organization_id, created_at DESC);

CREATE INDEX ai_roleplay_sessions_org_user_idx ON public.ai_roleplay_sessions USING btree (organization_id, user_id, created_at DESC);

CREATE INDEX ai_sessions_org_idx ON public.ai_sessions USING btree (organization_id, user_id);

CREATE INDEX ai_token_limits_org_idx ON public.ai_token_limits USING btree (organization_id);

CREATE INDEX idx_ait_msgs_session ON public.ai_trainer_messages USING btree (session_id, created_at);

CREATE INDEX ai_usage_org_idx ON public.ai_usage_meter USING btree (organization_id, created_at DESC);

CREATE INDEX aicrm_account_custom_field_values_account_idx ON public.aicrm_account_custom_field_values USING btree (account_id);

CREATE INDEX aicrm_account_custom_field_values_org_idx ON public.aicrm_account_custom_field_values USING btree (organization_id);

CREATE UNIQUE INDEX aicrm_account_custom_field_values_unique ON public.aicrm_account_custom_field_values USING btree (account_id, custom_field_id);

CREATE INDEX aicrm_account_custom_fields_active_idx ON public.aicrm_account_custom_fields USING btree (organization_id) WHERE is_active;

CREATE INDEX aicrm_account_custom_fields_org_idx ON public.aicrm_account_custom_fields USING btree (organization_id, sort_order);

CREATE UNIQUE INDEX aicrm_account_execution_briefs_org_account_unique_idx ON public.aicrm_account_execution_briefs USING btree (organization_id, account_id);

CREATE INDEX aicrm_account_execution_briefs_org_idx ON public.aicrm_account_execution_briefs USING btree (organization_id, confidence DESC NULLS LAST, last_calculated_at DESC NULLS LAST);

CREATE INDEX aicrm_account_product_fit_org_account_idx ON public.aicrm_account_product_fit USING btree (organization_id, account_id);

CREATE UNIQUE INDEX aicrm_account_product_fit_org_account_product_unique_idx ON public.aicrm_account_product_fit USING btree (organization_id, account_id, product_id);

CREATE INDEX aicrm_account_product_fit_org_fit_score_idx ON public.aicrm_account_product_fit USING btree (organization_id, fit_score DESC NULLS LAST);

CREATE INDEX aicrm_account_product_fit_org_fit_tier_idx ON public.aicrm_account_product_fit USING btree (organization_id, fit_tier);

CREATE INDEX aicrm_account_product_fit_org_product_idx ON public.aicrm_account_product_fit USING btree (organization_id, product_id);

CREATE INDEX aicrm_account_product_fit_org_reviewed_status_idx ON public.aicrm_account_product_fit USING btree (organization_id, reviewed_status);

CREATE INDEX aicrm_account_tags_org_idx ON public.aicrm_account_tags USING btree (organization_id, account_id, tag_id);

CREATE INDEX aicrm_accounts_city_idx ON public.aicrm_accounts USING btree (city);

CREATE INDEX aicrm_accounts_company_name_idx ON public.aicrm_accounts USING btree (organization_id, lower(TRIM(BOTH FROM company_name)));

CREATE INDEX aicrm_accounts_google_place_idx ON public.aicrm_accounts USING btree (google_place_id);

CREATE INDEX aicrm_accounts_org_dashboard_target_idx ON public.aicrm_accounts USING btree (organization_id, do_not_contact, status, priority_score DESC NULLS LAST);

CREATE INDEX aicrm_accounts_org_geo_activity_idx ON public.aicrm_accounts USING btree (organization_id, province, city, last_touch DESC NULLS LAST);

CREATE INDEX aicrm_accounts_org_geo_idx ON public.aicrm_accounts USING btree (organization_id, country, province, city, status);

CREATE INDEX aicrm_accounts_org_idx ON public.aicrm_accounts USING btree (organization_id);

CREATE INDEX aicrm_accounts_owner_idx ON public.aicrm_accounts USING btree (owner_id);

CREATE INDEX aicrm_accounts_scoring_review_required_idx ON public.aicrm_accounts USING btree (organization_id, scoring_review_required);

CREATE INDEX aicrm_accounts_signature_idx ON public.aicrm_accounts USING btree (organization_id, lower(TRIM(BOTH FROM COALESCE(company_name, ''::text))), lower(TRIM(BOTH FROM COALESCE(province, ''::text))), lower(TRIM(BOTH FROM COALESCE(city, ''::text))));

CREATE UNIQUE INDEX aicrm_accounts_signature_unique_idx ON public.aicrm_accounts USING btree (organization_id, lower(TRIM(BOTH FROM COALESCE(company_name, ''::text))), lower(TRIM(BOTH FROM COALESCE(province, ''::text))), lower(TRIM(BOTH FROM COALESCE(city, ''::text))));

CREATE INDEX aicrm_accounts_website_idx ON public.aicrm_accounts USING btree (website);

CREATE INDEX aicrm_activities_account_idx ON public.aicrm_activities USING btree (account_id);

CREATE INDEX aicrm_activities_contact_idx ON public.aicrm_activities USING btree (contact_id);

CREATE INDEX aicrm_activities_opportunity_idx ON public.aicrm_activities USING btree (opportunity_id);

CREATE INDEX aicrm_activities_org_idx ON public.aicrm_activities USING btree (organization_id, activity_date DESC);

CREATE INDEX aicrm_activities_org_opportunity_idx ON public.aicrm_activities USING btree (organization_id, opportunity_id, activity_date DESC);

CREATE INDEX aicrm_ai_enrichment_jobs_account_idx ON public.aicrm_ai_enrichment_jobs USING btree (organization_id, account_id);

CREATE INDEX aicrm_ai_enrichment_jobs_org_idx ON public.aicrm_ai_enrichment_jobs USING btree (organization_id, status, created_at DESC);

CREATE INDEX aicrm_ai_enrichment_jobs_org_model_idx ON public.aicrm_ai_enrichment_jobs USING btree (organization_id, model, status, created_at DESC);

CREATE INDEX aicrm_ai_enrichment_jobs_org_status_idx ON public.aicrm_ai_enrichment_jobs USING btree (organization_id, status, created_at DESC);

CREATE INDEX aicrm_ai_enrichment_jobs_requested_by_idx ON public.aicrm_ai_enrichment_jobs USING btree (requested_by);

CREATE INDEX aicrm_ai_profiles_org_idx ON public.aicrm_ai_profiles USING btree (organization_id, business_unit_id, brand_id, active, is_default);

CREATE UNIQUE INDEX aicrm_ai_profiles_org_name_unique_idx ON public.aicrm_ai_profiles USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_ai_research_org_account_idx ON public.aicrm_ai_research USING btree (organization_id, account_id);

CREATE UNIQUE INDEX aicrm_ai_research_org_account_unique ON public.aicrm_ai_research USING btree (organization_id, account_id);

CREATE INDEX aicrm_ai_research_org_confidence_idx ON public.aicrm_ai_research USING btree (organization_id, confidence DESC NULLS LAST);

CREATE INDEX aicrm_ai_research_org_idx ON public.aicrm_ai_research USING btree (organization_id);

CREATE INDEX aicrm_ai_research_org_review_status_idx ON public.aicrm_ai_research USING btree (organization_id, review_status, priority_score DESC NULLS LAST);

CREATE INDEX aicrm_audit_log_account_idx ON public.aicrm_audit_log USING btree (account_id);

CREATE INDEX aicrm_audit_log_actor_idx ON public.aicrm_audit_log USING btree (actor_user_id);

CREATE INDEX aicrm_audit_log_org_idx ON public.aicrm_audit_log USING btree (organization_id, created_at DESC);

CREATE INDEX aicrm_brands_org_idx ON public.aicrm_brands USING btree (organization_id, business_unit_id, display_order, active);

CREATE UNIQUE INDEX aicrm_brands_org_name_unique_idx ON public.aicrm_brands USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_business_units_org_idx ON public.aicrm_business_units USING btree (organization_id, display_order, active);

CREATE UNIQUE INDEX aicrm_business_units_org_name_unique_idx ON public.aicrm_business_units USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_buying_committee_org_account_idx ON public.aicrm_buying_committee USING btree (organization_id, account_id, committee_role, influence_level DESC);

CREATE UNIQUE INDEX aicrm_buying_committee_org_account_person_role_unique_idx ON public.aicrm_buying_committee USING btree (organization_id, account_id, person_id, committee_role);

CREATE INDEX aicrm_buying_committee_org_person_idx ON public.aicrm_buying_committee USING btree (organization_id, person_id, current DESC, influence_level DESC);

CREATE INDEX aicrm_campaign_categories_org_idx ON public.aicrm_campaign_categories USING btree (organization_id, business_unit_id, display_order, active);

CREATE UNIQUE INDEX aicrm_campaign_categories_org_name_unique_idx ON public.aicrm_campaign_categories USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_campaign_sequences_org_idx ON public.aicrm_campaign_sequences USING btree (organization_id, campaign_type_id, active, is_default);

CREATE UNIQUE INDEX aicrm_campaign_sequences_org_name_unique_idx ON public.aicrm_campaign_sequences USING btree (organization_id, campaign_type_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_campaign_types_org_idx ON public.aicrm_campaign_types USING btree (organization_id, campaign_category_id, business_unit_id, display_order, active);

CREATE UNIQUE INDEX aicrm_campaign_types_org_name_unique_idx ON public.aicrm_campaign_types USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_channels_org_idx ON public.aicrm_channels USING btree (organization_id, business_unit_id, display_order, active);

CREATE UNIQUE INDEX aicrm_channels_org_name_unique_idx ON public.aicrm_channels USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_collaboration_audit_entity_idx ON public.aicrm_collaboration_audit_log USING btree (entity_type, entity_id);

CREATE INDEX aicrm_collaboration_audit_org_idx ON public.aicrm_collaboration_audit_log USING btree (organization_id, created_at DESC);

CREATE INDEX aicrm_collaboration_audit_partner_idx ON public.aicrm_collaboration_audit_log USING btree (partner_organization_id, created_at DESC);

CREATE INDEX aicrm_consent_records_org_idx ON public.aicrm_consent_records USING btree (organization_id, consent_status, email);

CREATE UNIQUE INDEX aicrm_consent_records_unique_idx ON public.aicrm_consent_records USING btree (organization_id, account_id, contact_id, lower(TRIM(BOTH FROM email)), channel);

CREATE INDEX aicrm_contacts_account_idx ON public.aicrm_contacts USING btree (account_id);

CREATE INDEX aicrm_contacts_email_idx ON public.aicrm_contacts USING btree (lower((email)::text));

CREATE INDEX aicrm_contacts_full_name_idx ON public.aicrm_contacts USING btree (full_name);

CREATE INDEX aicrm_contacts_org_account_role_idx ON public.aicrm_contacts USING btree (organization_id, account_id, role_type, decision_maker);

CREATE INDEX aicrm_contacts_org_idx ON public.aicrm_contacts USING btree (organization_id);

CREATE INDEX aicrm_daily_execution_queue_org_account_idx ON public.aicrm_daily_execution_queue USING btree (organization_id, account_id, status);

CREATE UNIQUE INDEX aicrm_daily_execution_queue_org_day_unique_idx ON public.aicrm_daily_execution_queue USING btree (organization_id, queue_date, account_id, COALESCE(contact_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(opportunity_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(TRIM(BOTH FROM recommended_action)));

CREATE INDEX aicrm_daily_execution_queue_org_idx ON public.aicrm_daily_execution_queue USING btree (organization_id, queue_date, status, priority DESC NULLS LAST);

CREATE INDEX aicrm_daily_execution_queue_org_opportunity_idx ON public.aicrm_daily_execution_queue USING btree (organization_id, opportunity_id, status);

CREATE INDEX aicrm_employment_history_org_company_idx ON public.aicrm_employment_history USING btree (organization_id, company_id, current DESC, start_date DESC NULLS LAST);

CREATE INDEX aicrm_employment_history_org_person_idx ON public.aicrm_employment_history USING btree (organization_id, person_id, current DESC, start_date DESC NULLS LAST, created_at DESC);

CREATE INDEX aicrm_employment_history_org_title_idx ON public.aicrm_employment_history USING btree (organization_id, lower(COALESCE(title, ''::text)));

CREATE INDEX aicrm_enrichment_runs_account_idx ON public.aicrm_enrichment_runs USING btree (organization_id, account_id, created_at DESC);

CREATE INDEX aicrm_enrichment_runs_job_idx ON public.aicrm_enrichment_runs USING btree (organization_id, job_type);

CREATE INDEX aicrm_enrichment_runs_org_idx ON public.aicrm_enrichment_runs USING btree (organization_id, created_at DESC);

CREATE INDEX aicrm_enrichment_runs_org_model_idx ON public.aicrm_enrichment_runs USING btree (organization_id, model, created_at DESC);

CREATE INDEX aicrm_execution_history_org_account_idx ON public.aicrm_execution_history USING btree (organization_id, account_id, occurred_at DESC);

CREATE INDEX aicrm_execution_history_org_idx ON public.aicrm_execution_history USING btree (organization_id, occurred_at DESC);

CREATE INDEX aicrm_execution_history_org_opportunity_idx ON public.aicrm_execution_history USING btree (organization_id, opportunity_id, occurred_at DESC);

CREATE INDEX aicrm_forecasts_org_account_idx ON public.aicrm_forecasts USING btree (organization_id, account_id, period_type, projected_revenue DESC NULLS LAST);

CREATE INDEX aicrm_forecasts_org_channel_idx ON public.aicrm_forecasts USING btree (organization_id, channel, period_type, projected_revenue DESC NULLS LAST);

CREATE INDEX aicrm_forecasts_org_geo_idx ON public.aicrm_forecasts USING btree (organization_id, province, territory, product_name, channel, period_type);

CREATE INDEX aicrm_forecasts_org_idx ON public.aicrm_forecasts USING btree (organization_id, period_type, period_start DESC, confidence DESC NULLS LAST);

CREATE UNIQUE INDEX aicrm_forecasts_org_period_dimension_unique_idx ON public.aicrm_forecasts USING btree (organization_id, period_type, period_start, COALESCE(business_unit_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(brand_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(product_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(province, ''::text), COALESCE(territory, ''::text), COALESCE(channel, ''::text), COALESCE(account_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(salesperson_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(campaign_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX aicrm_forecasts_org_product_idx ON public.aicrm_forecasts USING btree (organization_id, product_id, period_type, projected_revenue DESC NULLS LAST);

CREATE INDEX aicrm_forecasts_org_salesperson_idx ON public.aicrm_forecasts USING btree (organization_id, salesperson_id, period_type, projected_revenue DESC NULLS LAST);

CREATE INDEX aicrm_forecasts_org_territory_idx ON public.aicrm_forecasts USING btree (organization_id, province, period_type, projected_revenue DESC NULLS LAST);

CREATE INDEX aicrm_graph_edges_from_idx ON public.aicrm_graph_edges USING btree (organization_id, from_node_id, relationship_type);

CREATE INDEX aicrm_graph_edges_org_from_idx ON public.aicrm_graph_edges USING btree (organization_id, from_node_id);

CREATE INDEX aicrm_graph_edges_org_strength_idx ON public.aicrm_graph_edges USING btree (organization_id, strength DESC NULLS LAST);

CREATE INDEX aicrm_graph_edges_org_to_idx ON public.aicrm_graph_edges USING btree (organization_id, to_node_id);

CREATE INDEX aicrm_graph_edges_org_type_idx ON public.aicrm_graph_edges USING btree (organization_id, relationship_type);

CREATE UNIQUE INDEX aicrm_graph_edges_relation_uq ON public.aicrm_graph_edges USING btree (organization_id, from_node_id, to_node_id, relationship_type);

CREATE INDEX aicrm_graph_edges_to_idx ON public.aicrm_graph_edges USING btree (organization_id, to_node_id, relationship_type);

CREATE UNIQUE INDEX aicrm_graph_nodes_entity_uq ON public.aicrm_graph_nodes USING btree (organization_id, node_type, entity_type, entity_id) WHERE (entity_id IS NOT NULL);

CREATE INDEX aicrm_graph_nodes_label_idx ON public.aicrm_graph_nodes USING gin (to_tsvector('simple'::regconfig, ((COALESCE(label, ''::text) || ' '::text) || COALESCE(description, ''::text))));

CREATE INDEX aicrm_graph_nodes_org_label_idx ON public.aicrm_graph_nodes USING btree (organization_id, lower(label));

CREATE UNIQUE INDEX aicrm_graph_nodes_org_type_entity_idx ON public.aicrm_graph_nodes USING btree (organization_id, node_type, entity_type, entity_id) WHERE (entity_id IS NOT NULL);

CREATE INDEX aicrm_graph_nodes_org_type_idx ON public.aicrm_graph_nodes USING btree (organization_id, node_type);

CREATE INDEX aicrm_import_mappings_import_idx ON public.aicrm_import_mappings USING btree (import_id);

CREATE INDEX aicrm_import_mappings_org_idx ON public.aicrm_import_mappings USING btree (organization_id);

CREATE INDEX aicrm_import_rows_import_idx ON public.aicrm_import_rows USING btree (import_id, status, row_number);

CREATE INDEX aicrm_import_rows_org_idx ON public.aicrm_import_rows USING btree (organization_id);

CREATE INDEX aicrm_imports_organization_idx ON public.aicrm_imports USING btree (organization_id, created_at DESC);

CREATE INDEX aicrm_imports_status_idx ON public.aicrm_imports USING btree (import_status);

CREATE INDEX aicrm_kpis_org_idx ON public.aicrm_kpis USING btree (organization_id, kpi_category, business_unit_id, display_order, active);

CREATE UNIQUE INDEX aicrm_kpis_org_key_unique_idx ON public.aicrm_kpis USING btree (organization_id, lower(TRIM(BOTH FROM kpi_key)));

CREATE INDEX aicrm_market_connectors_org_idx ON public.aicrm_market_connectors USING btree (organization_id, active, status);

CREATE UNIQUE INDEX aicrm_market_connectors_org_provider_unique_idx ON public.aicrm_market_connectors USING btree (organization_id, lower(TRIM(BOTH FROM provider)));

CREATE INDEX aicrm_market_coverage_org_channel_idx ON public.aicrm_market_coverage USING btree (organization_id, coverage_dimension, channel, coverage_percentage DESC NULLS LAST);

CREATE INDEX aicrm_market_coverage_org_product_idx ON public.aicrm_market_coverage USING btree (organization_id, coverage_dimension, product_id, coverage_percentage DESC NULLS LAST);

CREATE UNIQUE INDEX aicrm_market_coverage_org_scope_unique_idx ON public.aicrm_market_coverage USING btree (organization_id, coverage_dimension, COALESCE((territory_id)::text, '__none__'::text), COALESCE((product_id)::text, '__none__'::text), COALESCE(lower(TRIM(BOTH FROM channel)), ''::text), COALESCE(lower(TRIM(BOTH FROM country)), ''::text), COALESCE(lower(TRIM(BOTH FROM province)), ''::text), COALESCE(lower(TRIM(BOTH FROM region)), ''::text), COALESCE(lower(TRIM(BOTH FROM city)), ''::text), COALESCE(lower(TRIM(BOTH FROM postal_area)), ''::text));

CREATE INDEX aicrm_market_coverage_org_territory_idx ON public.aicrm_market_coverage USING btree (organization_id, coverage_dimension, territory_type, territory_name, coverage_percentage DESC NULLS LAST);

CREATE INDEX aicrm_market_coverage_org_white_space_idx ON public.aicrm_market_coverage USING btree (organization_id, white_space_score DESC NULLS LAST, remaining_opportunity DESC NULLS LAST);

CREATE INDEX aicrm_market_discovery_queue_company_name_trgm_idx ON public.aicrm_market_discovery_queue USING gin (company_name gin_trgm_ops);

CREATE INDEX aicrm_market_discovery_queue_org_confidence_idx ON public.aicrm_market_discovery_queue USING btree (organization_id, confidence DESC NULLS LAST);

CREATE INDEX aicrm_market_discovery_queue_org_source_idx ON public.aicrm_market_discovery_queue USING btree (organization_id, source, created_at DESC);

CREATE INDEX aicrm_market_discovery_queue_org_status_idx ON public.aicrm_market_discovery_queue USING btree (organization_id, review_status, created_at DESC);

CREATE INDEX aicrm_market_events_org_account_idx ON public.aicrm_market_events USING btree (organization_id, account_id, occurred_at DESC);

CREATE INDEX aicrm_market_events_org_type_idx ON public.aicrm_market_events USING btree (organization_id, event_type, occurred_at DESC);

CREATE UNIQUE INDEX aicrm_market_refresh_queue_org_account_reason_unique_idx ON public.aicrm_market_refresh_queue USING btree (organization_id, account_id, lower(TRIM(BOTH FROM reason)));

CREATE INDEX aicrm_market_refresh_queue_org_status_idx ON public.aicrm_market_refresh_queue USING btree (organization_id, status, priority DESC NULLS LAST, suggested_at DESC);

CREATE INDEX aicrm_market_watchlists_org_idx ON public.aicrm_market_watchlists USING btree (organization_id, active, name);

CREATE UNIQUE INDEX aicrm_market_watchlists_org_name_unique_idx ON public.aicrm_market_watchlists USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_notes_account_idx ON public.aicrm_notes USING btree (account_id);

CREATE INDEX aicrm_notes_contact_idx ON public.aicrm_notes USING btree (contact_id);

CREATE INDEX aicrm_notes_opportunity_idx ON public.aicrm_notes USING btree (opportunity_id);

CREATE INDEX aicrm_notes_org_idx ON public.aicrm_notes USING btree (organization_id, created_at DESC);

CREATE INDEX aicrm_opportunities_account_idx ON public.aicrm_opportunities USING btree (organization_id, account_id);

CREATE INDEX aicrm_opportunities_expected_close_idx ON public.aicrm_opportunities USING btree (expected_close_date);

CREATE INDEX aicrm_opportunities_org_account_activity_idx ON public.aicrm_opportunities USING btree (organization_id, account_id, status, updated_at DESC NULLS LAST);

CREATE INDEX aicrm_opportunities_org_idx ON public.aicrm_opportunities USING btree (organization_id, stage);

CREATE INDEX aicrm_opportunities_org_stage_status_close_idx ON public.aicrm_opportunities USING btree (organization_id, stage, status, expected_close_date DESC NULLS LAST);

CREATE INDEX aicrm_opportunities_owner_idx ON public.aicrm_opportunities USING btree (owner_id);

CREATE INDEX aicrm_opportunity_health_org_idx ON public.aicrm_opportunity_health USING btree (organization_id, health_status, health_score DESC NULLS LAST, last_calculated_at DESC NULLS LAST);

CREATE UNIQUE INDEX aicrm_opportunity_health_org_opportunity_unique_idx ON public.aicrm_opportunity_health USING btree (organization_id, opportunity_id);

CREATE INDEX aicrm_opportunity_timelines_org_account_idx ON public.aicrm_opportunity_timelines USING btree (organization_id, account_id, occurred_at DESC);

CREATE INDEX aicrm_opportunity_timelines_org_event_idx ON public.aicrm_opportunity_timelines USING btree (organization_id, event_type, occurred_at DESC);

CREATE INDEX aicrm_opportunity_timelines_org_opportunity_idx ON public.aicrm_opportunity_timelines USING btree (organization_id, opportunity_id, occurred_at DESC);

CREATE INDEX aicrm_organization_settings_ai_enabled_idx ON public.aicrm_organization_settings USING btree (organization_id, ai_enabled);

CREATE INDEX aicrm_outcomes_org_account_idx ON public.aicrm_outcomes USING btree (organization_id, account_id, occurred_at DESC);

CREATE INDEX aicrm_outcomes_org_campaign_idx ON public.aicrm_outcomes USING btree (organization_id, campaign_id, occurred_at DESC);

CREATE INDEX aicrm_outcomes_org_created_by_idx ON public.aicrm_outcomes USING btree (organization_id, created_by, occurred_at DESC);

CREATE INDEX aicrm_outcomes_org_idx ON public.aicrm_outcomes USING btree (organization_id, occurred_at DESC);

CREATE INDEX aicrm_outcomes_org_outcome_idx ON public.aicrm_outcomes USING btree (organization_id, outcome, occurred_at DESC);

CREATE INDEX aicrm_outcomes_org_product_idx ON public.aicrm_outcomes USING btree (organization_id, product_id, occurred_at DESC);

CREATE INDEX aicrm_outcomes_org_recommendation_idx ON public.aicrm_outcomes USING btree (organization_id, recommendation, occurred_at DESC);

CREATE INDEX aicrm_outcomes_org_territory_idx ON public.aicrm_outcomes USING btree (organization_id, territory, occurred_at DESC);

CREATE INDEX aicrm_outreach_campaigns_org_idx ON public.aicrm_outreach_campaigns USING btree (organization_id, status, created_at DESC);

CREATE UNIQUE INDEX aicrm_outreach_campaigns_org_name_idx ON public.aicrm_outreach_campaigns USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_outreach_messages_campaign_idx ON public.aicrm_outreach_messages USING btree (campaign_id, status);

CREATE INDEX aicrm_outreach_messages_enrollment_idx ON public.aicrm_outreach_messages USING btree (enrollment_id, status, created_at DESC);

CREATE INDEX aicrm_outreach_messages_org_idx ON public.aicrm_outreach_messages USING btree (organization_id, status, created_at DESC);

CREATE INDEX aicrm_partner_organizations_org_name_idx ON public.aicrm_partner_organizations USING btree (lower(organization_name));

CREATE UNIQUE INDEX aicrm_partner_organizations_org_unique_idx ON public.aicrm_partner_organizations USING btree (organization_id);

CREATE INDEX aicrm_partner_organizations_public_visible_idx ON public.aicrm_partner_organizations USING btree (public_visible);

CREATE INDEX aicrm_partner_organizations_status_idx ON public.aicrm_partner_organizations USING btree (status);

CREATE UNIQUE INDEX aicrm_partnerships_org_partner_unique_idx ON public.aicrm_partnerships USING btree (organization_id, partner_organization_id);

CREATE INDEX aicrm_partnerships_org_status_idx ON public.aicrm_partnerships USING btree (organization_id, status);

CREATE INDEX aicrm_partnerships_partner_status_idx ON public.aicrm_partnerships USING btree (partner_organization_id, status);

CREATE INDEX aicrm_partnerships_updated_idx ON public.aicrm_partnerships USING btree (updated_at DESC NULLS LAST);

CREATE INDEX aicrm_people_org_buying_authority_idx ON public.aicrm_people USING btree (organization_id, buying_authority, current_company_id);

CREATE INDEX aicrm_people_org_current_company_idx ON public.aicrm_people USING btree (organization_id, current_company_id);

CREATE UNIQUE INDEX aicrm_people_org_email_unique_idx ON public.aicrm_people USING btree (organization_id, lower(TRIM(BOTH FROM email))) WHERE ((email IS NOT NULL) AND (TRIM(BOTH FROM email) <> ''::text));

CREATE INDEX aicrm_people_org_name_idx ON public.aicrm_people USING btree (organization_id, lower(last_name), lower(first_name));

CREATE INDEX aicrm_people_org_score_idx ON public.aicrm_people USING btree (organization_id, relationship_score DESC, influence_score DESC, relationship_strength DESC);

CREATE INDEX aicrm_pipeline_stages_org_idx ON public.aicrm_pipeline_stages USING btree (organization_id, sort_order, is_active);

CREATE UNIQUE INDEX aicrm_pipeline_stages_org_name ON public.aicrm_pipeline_stages USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_products_org_active_idx ON public.aicrm_products USING btree (organization_id, active);

CREATE INDEX aicrm_products_org_archived_idx ON public.aicrm_products USING btree (organization_id, archived_at DESC NULLS LAST);

CREATE INDEX aicrm_products_org_brand_idx ON public.aicrm_products USING btree (organization_id, brand_id, active);

CREATE INDEX aicrm_products_org_business_unit_idx ON public.aicrm_products USING btree (organization_id, business_unit_id, active);

CREATE UNIQUE INDEX aicrm_products_org_name_unique_idx ON public.aicrm_products USING btree (organization_id, name);

CREATE INDEX aicrm_referrals_destination_idx ON public.aicrm_referrals USING btree (destination_organization_id, created_at DESC);

CREATE INDEX aicrm_referrals_org_status_idx ON public.aicrm_referrals USING btree (organization_id, status);

CREATE INDEX aicrm_referrals_origin_idx ON public.aicrm_referrals USING btree (origin_organization_id, created_at DESC);

CREATE INDEX aicrm_referrals_type_idx ON public.aicrm_referrals USING btree (referral_type);

CREATE INDEX aicrm_relationships_org_account_idx ON public.aicrm_relationships USING btree (organization_id, account_id, relationship_strength DESC);

CREATE UNIQUE INDEX aicrm_relationships_org_pair_type_unique_idx ON public.aicrm_relationships USING btree (organization_id, person_id, related_person_id, relationship_type);

CREATE INDEX aicrm_relationships_org_person_idx ON public.aicrm_relationships USING btree (organization_id, person_id, relationship_strength DESC, last_interaction DESC NULLS LAST);

CREATE INDEX aicrm_relationships_org_related_idx ON public.aicrm_relationships USING btree (organization_id, related_person_id, relationship_strength DESC, last_interaction DESC NULLS LAST);

CREATE INDEX aicrm_relationships_org_type_idx ON public.aicrm_relationships USING btree (organization_id, relationship_type, relationship_strength DESC);

CREATE INDEX aicrm_route_plans_org_destination_idx ON public.aicrm_route_plans USING btree (organization_id, destination_province, destination_city);

CREATE INDEX aicrm_route_plans_org_idx ON public.aicrm_route_plans USING btree (organization_id, travel_date DESC NULLS LAST, status);

CREATE INDEX aicrm_sales_motions_org_idx ON public.aicrm_sales_motions USING btree (organization_id, business_unit_id, display_order, active);

CREATE UNIQUE INDEX aicrm_sales_motions_org_name_unique_idx ON public.aicrm_sales_motions USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_sales_playbooks_org_idx ON public.aicrm_sales_playbooks USING btree (organization_id, business_unit_id, channel_id, product_id, active, is_default, display_order);

CREATE UNIQUE INDEX aicrm_sales_playbooks_org_name_unique_idx ON public.aicrm_sales_playbooks USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE UNIQUE INDEX aicrm_saved_views_name_uniq ON public.aicrm_saved_views USING btree (organization_id, view_entity, lower(TRIM(BOTH FROM view_name)));

CREATE INDEX aicrm_saved_views_org_idx ON public.aicrm_saved_views USING btree (organization_id, view_entity, created_at DESC);

CREATE INDEX aicrm_sequence_enrollments_account_idx ON public.aicrm_sequence_enrollments USING btree (account_id, status, next_action_at);

CREATE INDEX aicrm_sequence_enrollments_contact_idx ON public.aicrm_sequence_enrollments USING btree (contact_id, status, next_action_at);

CREATE INDEX aicrm_sequence_enrollments_org_idx ON public.aicrm_sequence_enrollments USING btree (organization_id, status, next_action_at);

CREATE INDEX aicrm_sequence_steps_campaign_idx ON public.aicrm_sequence_steps USING btree (campaign_id, step_number);

CREATE INDEX aicrm_shared_market_intelligence_org_idx ON public.aicrm_shared_market_intelligence USING btree (organization_id, created_at DESC);

CREATE INDEX aicrm_shared_market_intelligence_visibility_idx ON public.aicrm_shared_market_intelligence USING btree (visibility_level);

CREATE INDEX aicrm_shared_projects_org_status_idx ON public.aicrm_shared_projects USING btree (organization_id, status);

CREATE INDEX aicrm_shared_projects_partner_status_idx ON public.aicrm_shared_projects USING btree (partner_organization_id, status);

CREATE INDEX aicrm_shared_projects_type_idx ON public.aicrm_shared_projects USING btree (project_type);

CREATE INDEX aicrm_suppression_list_account_idx ON public.aicrm_suppression_list USING btree (organization_id, account_id);

CREATE INDEX aicrm_suppression_list_contact_idx ON public.aicrm_suppression_list USING btree (organization_id, contact_id);

CREATE INDEX aicrm_suppression_list_org_idx ON public.aicrm_suppression_list USING btree (organization_id, is_active);

CREATE UNIQUE INDEX aicrm_suppression_list_unique_idx ON public.aicrm_suppression_list USING btree (organization_id, COALESCE(lower(TRIM(BOTH FROM email)), ''::text), COALESCE((contact_id)::text, ''::text));

CREATE UNIQUE INDEX aicrm_tags_name_uniq ON public.aicrm_tags USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_tags_org_idx ON public.aicrm_tags USING btree (organization_id, lower(TRIM(BOTH FROM name)));

CREATE INDEX aicrm_tasks_account_idx ON public.aicrm_tasks USING btree (organization_id, account_id);

CREATE INDEX aicrm_tasks_contact_idx ON public.aicrm_tasks USING btree (contact_id);

CREATE INDEX aicrm_tasks_opportunity_idx ON public.aicrm_tasks USING btree (opportunity_id);

CREATE INDEX aicrm_tasks_org_idx ON public.aicrm_tasks USING btree (organization_id, status, due_date);

CREATE INDEX aicrm_territories_org_geo_idx ON public.aicrm_territories USING btree (organization_id, country, province, region, city, postal_area);

CREATE UNIQUE INDEX aicrm_territories_org_parent_name_type_unique_idx ON public.aicrm_territories USING btree (organization_id, COALESCE((parent_id)::text, '__root__'::text), lower(TRIM(BOTH FROM name)), territory_type);

CREATE INDEX aicrm_territories_org_type_idx ON public.aicrm_territories USING btree (organization_id, territory_type, active, display_order);

CREATE UNIQUE INDEX aicrm_territory_heatmaps_org_geo_unique_idx ON public.aicrm_territory_heatmaps USING btree (organization_id, geography_type, lower(TRIM(BOTH FROM geography_key)));

CREATE INDEX aicrm_territory_heatmaps_org_type_idx ON public.aicrm_territory_heatmaps USING btree (organization_id, geography_type, coverage_percentage DESC NULLS LAST);

CREATE INDEX aicrm_territory_heatmaps_org_white_space_idx ON public.aicrm_territory_heatmaps USING btree (organization_id, white_space_score DESC NULLS LAST);

CREATE INDEX aicrm_training_exchanges_org_status_idx ON public.aicrm_training_exchanges USING btree (organization_id, status);

CREATE INDEX aicrm_training_exchanges_partner_status_idx ON public.aicrm_training_exchanges USING btree (partner_organization_id, status);

CREATE INDEX aicrm_training_exchanges_type_idx ON public.aicrm_training_exchanges USING btree (training_type);

CREATE INDEX idx_aiq_distributors_name ON public.aiq_distributors USING btree (name);

CREATE INDEX idx_aiq_distributors_status ON public.aiq_distributors USING btree (status);

CREATE INDEX aiq_products_brand_id_idx ON public.aiq_products USING btree (brand_id);

CREATE INDEX aiq_products_brand_model_ci_idx ON public.aiq_products USING btree (lower(brand_name), lower(regexp_replace(model, '[^a-zA-Z0-9]'::text, ''::text, 'g'::text)));

CREATE INDEX aiq_products_manufacturer_id_idx ON public.aiq_products USING btree (manufacturer_id);

CREATE INDEX aiq_products_org_brand_idx ON public.aiq_products USING btree (organization_id, brand_name, model);

CREATE INDEX aiq_products_org_status_idx ON public.aiq_products USING btree (organization_id, status, approval_status, updated_at DESC NULLS LAST);

CREATE UNIQUE INDEX idx_aiq_products_brand_model_market ON public.aiq_products USING btree (brand_name, model, market);

CREATE INDEX idx_aiq_products_finish ON public.aiq_products USING btree (finish) WHERE (finish IS NOT NULL);

CREATE INDEX idx_aiq_products_market ON public.aiq_products USING btree (market);

CREATE INDEX idx_aiq_products_upc ON public.aiq_products USING btree (upc) WHERE (upc IS NOT NULL);

CREATE INDEX idx_aiq_rebates_country ON public.aiq_rebate_programs USING btree (country);

CREATE INDEX idx_aiq_rebates_region ON public.aiq_rebate_programs USING btree (region);

CREATE INDEX idx_aiq_rebates_status ON public.aiq_rebate_programs USING btree (status);

CREATE INDEX idx_aiq_recalls_brand ON public.aiq_recalls USING btree (brand_name);

CREATE INDEX idx_aiq_recalls_country ON public.aiq_recalls USING btree (country);

CREATE INDEX idx_aiq_recalls_date ON public.aiq_recalls USING btree (recall_date DESC);

CREATE UNIQUE INDEX idx_aiq_recalls_source_id ON public.aiq_recalls USING btree (source, source_recall_id) WHERE (source_recall_id IS NOT NULL);

CREATE INDEX idx_retailers_country ON public.aiq_retailers USING btree (country);

CREATE INDEX idx_retailers_status ON public.aiq_retailers USING btree (status);

CREATE INDEX idx_sp_brands ON public.aiq_service_providers USING gin (brands_authorized);

CREATE INDEX idx_sp_country ON public.aiq_service_providers USING btree (country);

CREATE INDEX idx_sp_province ON public.aiq_service_providers USING btree (province_state);

CREATE INDEX idx_sp_type ON public.aiq_service_providers USING btree (service_type);

CREATE UNIQUE INDEX idx_aiq_vendor_contacts_brand_country ON public.aiq_vendor_contacts USING btree (brand_name, country);

CREATE INDEX idx_aiq_warranty_brand ON public.aiq_warranty_policies USING btree (brand_name);

CREATE UNIQUE INDEX idx_aiq_warranty_brand_category ON public.aiq_warranty_policies USING btree (brand_name, category);

CREATE INDEX idx_brand_catalog_academy ON public.brand_catalog USING btree (academy_status);

CREATE UNIQUE INDEX idx_brand_catalog_slug_org ON public.brand_catalog USING btree (organization_id, slug);

CREATE INDEX idx_brand_catalog_tier ON public.brand_catalog USING btree (brand_tier);

CREATE INDEX idx_brand_training_cards_brand ON public.brand_training_cards USING btree (brand_id);

CREATE INDEX idx_brand_training_cards_org ON public.brand_training_cards USING btree (organization_id);

CREATE INDEX idx_brand_training_cards_status ON public.brand_training_cards USING btree (status);

CREATE INDEX bn_location_idx ON public.budget_nodes USING btree (location_id, period_key);

CREATE INDEX bn_plan_idx ON public.budget_nodes USING btree (budget_plan_id, period_type, metric_type);

CREATE INDEX bn_user_idx ON public.budget_nodes USING btree (user_id, period_key) WHERE (user_id IS NOT NULL);

CREATE INDEX cad_bim_sources_status_idx ON public.cad_bim_sources USING btree (availability_status);

CREATE INDEX idx_cae_org ON public.communication_audit_events USING btree (organization_id);

CREATE INDEX idx_cem_org ON public.communication_email_messages USING btree (organization_id);

CREATE INDEX idx_cem_provider ON public.communication_email_messages USING btree (provider_message_id);

CREATE INDEX idx_ct_org ON public.communication_templates USING btree (organization_id);

CREATE INDEX idx_cwe_org ON public.communication_webhook_events USING btree (organization_id);

CREATE INDEX idx_cwe_provider ON public.communication_webhook_events USING btree (provider_message_id);

CREATE INDEX companies_org_idx ON public.companies USING btree (organization_id);

CREATE INDEX companies_org_name_idx ON public.companies USING btree (organization_id, lower(name));

CREATE INDEX idx_cross_ref_category ON public.competitive_cross_reference USING btree (category);

CREATE INDEX idx_cross_ref_tier ON public.competitive_cross_reference USING btree (tier);

CREATE INDEX idx_consent_active ON public.consent_ledger USING btree (subject_id, scope) WHERE (revoked_at IS NULL);

CREATE INDEX contacts_company_idx ON public.contacts USING btree (company_id);

CREATE INDEX contacts_org_idx ON public.contacts USING btree (organization_id);

CREATE INDEX idx_contacts_assigned ON public.contacts USING btree (assigned_salesperson_id);

CREATE INDEX idx_contacts_last_comm ON public.contacts USING btree (last_communication_at);

CREATE INDEX idx_crm_buying_groups_org ON public.crm_buying_groups USING btree (organization_id);

CREATE INDEX idx_coaching_queue_org ON public.crm_coaching_queue USING btree (organization_id);

CREATE INDEX idx_coaching_queue_pending ON public.crm_coaching_queue USING btree (organization_id, status) WHERE (status = 'pending'::text);

CREATE INDEX idx_crm_daily_five_user_date ON public.crm_daily_five USING btree (user_id, work_date);

CREATE INDEX idx_crm_deal_participants_contact ON public.crm_deal_participants USING btree (contact_id);

CREATE INDEX idx_crm_deal_participants_deal ON public.crm_deal_participants USING btree (deal_id);

CREATE INDEX crm_deals_org_idx ON public.crm_deals USING btree (organization_id, stage);

CREATE INDEX idx_crm_deals_archived ON public.crm_deals USING btree (is_archived);

CREATE INDEX idx_crm_deals_buying_group ON public.crm_deals USING btree (buying_group_id);

CREATE INDEX idx_crm_deals_priority ON public.crm_deals USING btree (priority);

CREATE INDEX idx_crm_deals_record_type ON public.crm_deals USING btree (record_type);

CREATE INDEX idx_crm_deals_stage ON public.crm_deals USING btree (stage);

CREATE INDEX idx_delivery_deal ON public.crm_delivery_workflows USING btree (deal_id);

CREATE INDEX idx_delivery_org ON public.crm_delivery_workflows USING btree (organization_id);

CREATE INDEX crm_emails_org_created_idx ON public.crm_emails USING btree (organization_id, created_at DESC);

CREATE INDEX crm_emails_org_idx ON public.crm_emails USING btree (organization_id, sent_at DESC);

CREATE INDEX idx_crm_emails_contact ON public.crm_emails USING btree (contact_id);

CREATE INDEX idx_crm_emails_deal ON public.crm_emails USING btree (deal_id);

CREATE INDEX idx_iq_leads_org ON public.crm_iq_lead_assignments USING btree (organization_id);

CREATE INDEX idx_crm_postmortems_deal ON public.crm_postmortems USING btree (deal_id);

CREATE INDEX crm_presentations_org_idx ON public.crm_presentations USING btree (organization_id, created_at DESC);

CREATE INDEX idx_sla_events_contact ON public.crm_sla_events USING btree (contact_id);

CREATE INDEX idx_sla_events_org ON public.crm_sla_events USING btree (organization_id);

CREATE INDEX idx_crm_stage_history_deal ON public.crm_stage_history USING btree (deal_id);

CREATE INDEX crm_tasks_org_idx ON public.crm_tasks USING btree (organization_id, due_at);

CREATE INDEX idx_temp_history_entity ON public.crm_temperature_history USING btree (entity_type, entity_id);

CREATE INDEX idx_temp_history_org ON public.crm_temperature_history USING btree (organization_id);

CREATE INDEX daily_coaching_focus_date_idx ON public.daily_coaching_focus USING btree (focus_date DESC);

CREATE INDEX dashboard_metric_settings_org_idx ON public.dashboard_metric_settings USING btree (organization_id, visible);

CREATE INDEX decision_actions_case_idx ON public.decision_actions USING btree (decision_case_id, status, created_at DESC);

CREATE INDEX decision_cases_org_priority_idx ON public.decision_cases USING btree (organization_id, status, priority_score DESC, created_at DESC);

CREATE INDEX decision_cases_source_idx ON public.decision_cases USING btree (organization_id, source_system, source_record_id);

CREATE INDEX decision_evidence_case_idx ON public.decision_evidence USING btree (decision_case_id, weight DESC);

CREATE INDEX idx_decision_model_performance_org ON public.decision_model_performance USING btree (organization_id, module, prediction_type);

CREATE INDEX decision_predictions_case_idx ON public.decision_predictions USING btree (decision_case_id, generated_at DESC);

CREATE INDEX idx_decision_predictions_org_status ON public.decision_predictions USING btree (organization_id, status, generated_at DESC);

CREATE INDEX executive_insights_org_status_priority_idx ON public.executive_intelligence_insights USING btree (organization_id, status, priority_score DESC);

CREATE INDEX executive_insights_snapshot_idx ON public.executive_intelligence_insights USING btree (snapshot_id);

CREATE INDEX executive_queries_org_created_idx ON public.executive_intelligence_queries USING btree (organization_id, created_at DESC);

CREATE INDEX executive_snapshots_org_generated_idx ON public.executive_intelligence_snapshots USING btree (organization_id, generated_at DESC);

CREATE INDEX idx_field_actions_assigned ON public.field_actions USING btree (assigned_to_user_id);

CREATE INDEX idx_field_actions_client ON public.field_actions USING btree (client_id);

CREATE INDEX idx_field_actions_status ON public.field_actions USING btree (status);

CREATE INDEX idx_field_actions_store ON public.field_actions USING btree (store_id);

CREATE INDEX idx_field_assignments_rep ON public.field_assignments USING btree (rep_user_id);

CREATE INDEX idx_field_assignments_store ON public.field_assignments USING btree (store_id);

CREATE INDEX idx_checklist_items_category ON public.field_checklist_items USING btree (category_id);

CREATE INDEX idx_checklist_responses_item ON public.field_checklist_responses USING btree (checklist_item_id);

CREATE INDEX idx_checklist_responses_visit ON public.field_checklist_responses USING btree (visit_id);

CREATE INDEX idx_field_competitive_visit ON public.field_competitive_intel USING btree (visit_id);

CREATE INDEX idx_field_findings_status ON public.field_findings USING btree (status);

CREATE INDEX idx_field_findings_store ON public.field_findings USING btree (store_id);

CREATE INDEX idx_field_findings_visit ON public.field_findings USING btree (visit_id);

CREATE INDEX idx_field_media_visit ON public.field_media USING btree (visit_id);

CREATE INDEX idx_field_store_scores_date ON public.field_store_scores USING btree (score_date);

CREATE INDEX idx_field_store_scores_store ON public.field_store_scores USING btree (store_id);

CREATE INDEX idx_field_visits_client ON public.field_visits USING btree (client_id);

CREATE INDEX idx_field_visits_date ON public.field_visits USING btree (visit_date);

CREATE INDEX idx_field_visits_rep ON public.field_visits USING btree (rep_user_id);

CREATE INDEX idx_field_visits_store ON public.field_visits USING btree (store_id);

CREATE INDEX idx_freviews_fact ON public.foundation_fact_reviews USING btree (fact_id);

CREATE INDEX idx_ffacts_current ON public.foundation_facts USING btree (object_id) WHERE (effective_to IS NULL);

CREATE INDEX idx_ffacts_object ON public.foundation_facts USING btree (object_id, fact_type);

CREATE INDEX idx_ffacts_status ON public.foundation_facts USING btree (status);

CREATE INDEX idx_fobjects_attrs ON public.foundation_objects USING gin (attributes);

CREATE INDEX idx_fobjects_name ON public.foundation_objects USING gin (to_tsvector('english'::regconfig, name));

CREATE INDEX idx_fobjects_status ON public.foundation_objects USING btree (status);

CREATE INDEX idx_fobjects_type ON public.foundation_objects USING btree (object_type);

CREATE INDEX idx_frel_from ON public.foundation_relationships USING btree (from_id, rel_type);

CREATE INDEX idx_frel_to ON public.foundation_relationships USING btree (to_id, rel_type);

CREATE INDEX idx_intel_companies_name ON public.intel_companies USING btree (name);

CREATE INDEX idx_intel_companies_type ON public.intel_companies USING btree (type);

CREATE INDEX idx_intel_locations_company ON public.intel_locations USING btree (company_id);

CREATE INDEX idx_intel_locations_status ON public.intel_locations USING btree (status);

CREATE INDEX idx_intel_news_category ON public.intel_news USING btree (category);

CREATE INDEX idx_intel_news_company ON public.intel_news USING btree (company_id);

CREATE INDEX idx_intel_news_date ON public.intel_news USING btree (scraped_at);

CREATE INDEX intelligence_context_cache_data_idx ON public.intelligence_context_cache USING gin (context_data);

CREATE INDEX intelligence_context_cache_expiry_idx ON public.intelligence_context_cache USING btree (expires_at);

CREATE INDEX intelligence_context_cache_lookup_idx ON public.intelligence_context_cache USING btree (organization_id, entity_id, context_key);

CREATE INDEX intelligence_entities_metadata_idx ON public.intelligence_entities USING gin (metadata);

CREATE INDEX intelligence_entities_name_idx ON public.intelligence_entities USING gin (to_tsvector('simple'::regconfig, canonical_name));

CREATE INDEX intelligence_entities_org_type_idx ON public.intelligence_entities USING btree (organization_id, entity_type, status);

CREATE INDEX intelligence_entities_source_idx ON public.intelligence_entities USING btree (source_system, source_record_id);

CREATE INDEX intelligence_events_correlation_idx ON public.intelligence_events USING btree (correlation_id);

CREATE INDEX intelligence_events_entity_time_idx ON public.intelligence_events USING btree (entity_id, occurred_at DESC);

CREATE INDEX intelligence_events_org_time_idx ON public.intelligence_events USING btree (organization_id, occurred_at DESC);

CREATE INDEX intelligence_events_payload_idx ON public.intelligence_events USING gin (payload);

CREATE INDEX intelligence_events_type_time_idx ON public.intelligence_events USING btree (event_type, occurred_at DESC);

CREATE INDEX intelligence_learning_signals_rank_idx ON public.intelligence_learning_signals USING btree (organization_id, context_key, subject_type, subject_key, bayesian_score DESC, observation_count DESC);

CREATE INDEX intelligence_outcomes_org_type_idx ON public.intelligence_outcomes USING btree (organization_id, outcome_type, occurred_at DESC);

CREATE INDEX intelligence_outcomes_recommendation_idx ON public.intelligence_outcomes USING btree (recommendation_id, occurred_at DESC);

CREATE UNIQUE INDEX intelligence_outcomes_source_uniq ON public.intelligence_outcomes USING btree (organization_id, source_system, source_record_id) WHERE (source_record_id IS NOT NULL);

CREATE INDEX intelligence_recommendations_entity_idx ON public.intelligence_recommendations USING btree (entity_id, created_at DESC);

CREATE INDEX intelligence_recommendations_lookup_idx ON public.intelligence_recommendations USING btree (organization_id, context_key, subject_type, subject_key, created_at DESC);

CREATE UNIQUE INDEX intelligence_recommendations_source_uniq ON public.intelligence_recommendations USING btree (organization_id, source_system, source_record_id) WHERE (source_record_id IS NOT NULL);

CREATE INDEX intelligence_timelines_entity_time_idx ON public.intelligence_timelines USING btree (entity_id, occurred_at DESC);

CREATE INDEX intelligence_timelines_org_time_idx ON public.intelligence_timelines USING btree (organization_id, occurred_at DESC);

CREATE INDEX idx_iq_badges_brand ON public.iq_badges USING btree (brand_id);

CREATE INDEX idx_iq_badges_pillar ON public.iq_badges USING btree (pillar);

CREATE INDEX idx_iq_badges_type ON public.iq_badges USING btree (badge_type);

CREATE INDEX idx_iq_card_completions_profile ON public.iq_card_completions USING btree (profile_id);

CREATE INDEX idx_iq_cards_deck ON public.iq_cards USING btree (deck_id);

CREATE INDEX idx_iq_courses_brand ON public.iq_courses USING btree (brand_id);

CREATE INDEX idx_iq_courses_pillar ON public.iq_courses USING btree (pillar);

CREATE INDEX iq_customer_interactions_org_idx ON public.iq_customer_interactions USING btree (organization_id, store_id, outcome);

CREATE INDEX iq_customer_waiting_queue_org_idx ON public.iq_customer_waiting_queue USING btree (organization_id, store_id, status, created_at DESC);

CREATE INDEX idx_iq_deck_completions_profile ON public.iq_deck_completions USING btree (profile_id);

CREATE INDEX idx_iq_decks_lane ON public.iq_decks USING btree (lane_id);

CREATE INDEX idx_iq_lanes_zone ON public.iq_lanes USING btree (zone_id);

CREATE INDEX idx_iq_notifications_created ON public.iq_notifications USING btree (created_at DESC);

CREATE INDEX idx_iq_notifications_rep ON public.iq_notifications USING btree (rep_id, is_read);

CREATE INDEX idx_iq_notifications_type ON public.iq_notifications USING btree (notification_type);

CREATE INDEX idx_iq_product_cards_active ON public.iq_product_cards USING btree (is_active) WHERE (is_active = true);

CREATE INDEX idx_iq_product_cards_brand ON public.iq_product_cards USING btree (brand_id);

CREATE INDEX idx_iq_product_cards_course ON public.iq_product_cards USING btree (course_id);

CREATE INDEX idx_iq_product_cards_product ON public.iq_product_cards USING btree (product_id);

CREATE UNIQUE INDEX uq_iq_product_cards_product_id ON public.iq_product_cards USING btree (product_id);

CREATE INDEX iq_queue_notifications_org_idx ON public.iq_queue_notifications USING btree (organization_id, status, waiting_customer_id);

CREATE INDEX iq_queue_snapshots_org_idx ON public.iq_queue_snapshots USING btree (organization_id, store_id, created_at DESC);

CREATE INDEX idx_iq_rep_badges_profile ON public.iq_rep_badges USING btree (profile_id);

CREATE INDEX idx_iq_rep_progress_profile ON public.iq_rep_progress USING btree (profile_id);

CREATE INDEX idx_iq_roleplay_brand ON public.iq_roleplay_sessions USING btree (brand_id);

CREATE INDEX idx_iq_roleplay_rep ON public.iq_roleplay_sessions USING btree (rep_id);

CREATE INDEX iq_shift_records_org_idx ON public.iq_shift_records USING btree (organization_id, is_active);

CREATE INDEX iq_shift_records_store_idx ON public.iq_shift_records USING btree (store_id, login_at DESC);

CREATE INDEX iq_shift_records_user_idx ON public.iq_shift_records USING btree (user_id);

CREATE INDEX iq_status_sessions_shift_idx ON public.iq_status_sessions USING btree (shift_id);

CREATE INDEX iq_status_sessions_store_idx ON public.iq_status_sessions USING btree (organization_id, store_id, started_at DESC);

CREATE INDEX iq_store_settings_org_idx ON public.iq_store_settings USING btree (organization_id);

CREATE INDEX iq_up_queue_entries_eligible_idx ON public.iq_up_queue_entries USING btree (organization_id, store_id, is_in_queue, is_available_for_assignment, queue_position);

CREATE INDEX iq_up_queue_entries_org_store_active_idx ON public.iq_up_queue_entries USING btree (organization_id, store_id, is_in_queue, is_current_up DESC, queue_position);

CREATE INDEX iq_up_queue_entries_shift_idx ON public.iq_up_queue_entries USING btree (shift_id);

CREATE INDEX kpi_events_org_created_idx ON public.kpi_events USING btree (organization_id, created_at DESC);

CREATE INDEX kpi_events_org_type_idx ON public.kpi_events USING btree (organization_id, event_type);

CREATE INDEX idx_mdc_brand ON public.media_discovery_candidates USING btree (brand_name);

CREATE INDEX idx_mdc_category ON public.media_discovery_candidates USING btree (asset_category);

CREATE INDEX idx_mdc_product ON public.media_discovery_candidates USING btree (matched_product_id);

CREATE INDEX idx_mdc_run ON public.media_discovery_candidates USING btree (run_id);

CREATE INDEX idx_mdc_status ON public.media_discovery_candidates USING btree (status);

CREATE INDEX idx_mdc_url ON public.media_discovery_candidates USING btree (url);

CREATE INDEX idx_mdr_brand ON public.media_discovery_runs USING btree (brand_name);

CREATE INDEX idx_mdr_status ON public.media_discovery_runs USING btree (status);

CREATE INDEX idx_msr_brand ON public.media_source_registry USING btree (brand_name);

CREATE INDEX idx_msr_domain ON public.media_source_registry USING btree (domain);

CREATE INDEX idx_mev_expiry ON public.memory_events USING btree (expires_at) WHERE (expires_at IS NOT NULL);

CREATE INDEX idx_mev_subject ON public.memory_events USING btree (subject_id, created_at DESC);

CREATE INDEX idx_mf_subject ON public.memory_facts USING btree (subject_id) WHERE (superseded_by IS NULL);

CREATE UNIQUE INDEX metric_snapshots_store_period_metric_uq ON public.metric_snapshots USING btree (organization_id, location_id, period_type, period_key, metric_key) WHERE (user_id IS NULL);

CREATE INDEX ms_location_idx ON public.metric_snapshots USING btree (location_id, metric_key, period_key);

CREATE INDEX ms_lookup_idx ON public.metric_snapshots USING btree (organization_id, metric_key, period_type, period_key);

CREATE INDEX ms_user_idx ON public.metric_snapshots USING btree (user_id, metric_key, period_key) WHERE (user_id IS NOT NULL);

CREATE UNIQUE INDEX idx_mfr_invites_code ON public.mfr_invites USING btree (code);

CREATE INDEX mfr_members_vendor_active_role_idx ON public.mfr_members USING btree (vendor_id, role) WHERE (status = 'active'::text);

CREATE INDEX org_invites_code_idx ON public.org_invites USING btree (invite_code) WHERE (status = 'pending'::text);

CREATE INDEX org_invites_email_idx ON public.org_invites USING btree (invited_email, status);

CREATE INDEX org_invites_org_idx ON public.org_invites USING btree (organization_id, status);

CREATE INDEX org_kpis_org_idx ON public.org_kpis USING btree (organization_id);

CREATE INDEX org_locations_org_idx ON public.org_locations USING btree (organization_id, location_type);

CREATE INDEX org_locations_parent_idx ON public.org_locations USING btree (parent_id);

CREATE INDEX org_roles_org_idx ON public.org_roles USING btree (organization_id, active);

CREATE INDEX org_targets_org_idx ON public.org_targets USING btree (organization_id, fiscal_year, fiscal_period);

CREATE INDEX idx_org_brands_org ON public.organization_brands USING btree (organization_id);

CREATE INDEX org_members_manager_idx ON public.organization_members USING btree (manager_id);

CREATE INDEX org_members_org_role_idx ON public.organization_members USING btree (org_role_id);

CREATE INDEX idx_pim_marketing_brand ON public.pim_marketing_assets USING btree (brand_id);

CREATE INDEX idx_pim_marketing_product ON public.pim_marketing_assets USING btree (product_id);

CREATE INDEX idx_pim_marketing_verification ON public.pim_marketing_assets USING btree (verification_status);

CREATE INDEX idx_price_history_checked ON public.pim_price_history USING btree (checked_at);

CREATE INDEX idx_price_history_product ON public.pim_price_history USING btree (product_id);

CREATE INDEX idx_pim_accessories_product ON public.pim_product_accessories USING btree (product_id);

CREATE INDEX idx_pim_certs_product ON public.pim_product_certifications USING btree (product_id);

CREATE INDEX idx_pim_dims_product ON public.pim_product_dimensions USING btree (product_id);

CREATE INDEX idx_pim_docs_product ON public.pim_product_documents USING btree (product_id);

CREATE INDEX idx_pim_docs_type ON public.pim_product_documents USING btree (doc_type);

CREATE INDEX idx_pim_docs_verification ON public.pim_product_documents USING btree (verification_status);

CREATE INDEX idx_pim_features_product ON public.pim_product_features USING btree (product_id);

CREATE INDEX idx_pim_images_brand ON public.pim_product_images USING btree (brand_id);

CREATE INDEX idx_pim_images_product ON public.pim_product_images USING btree (product_id);

CREATE INDEX idx_pim_images_verification ON public.pim_product_images USING btree (verification_status);

CREATE INDEX idx_pim_rebates_active ON public.pim_product_rebates USING btree (is_active, start_date, end_date);

CREATE INDEX idx_pim_rebates_brand ON public.pim_product_rebates USING btree (brand_id);

CREATE INDEX idx_pim_rebates_product ON public.pim_product_rebates USING btree (product_id);

CREATE INDEX idx_pim_product_videos_brand ON public.pim_product_videos USING btree (brand_id);

CREATE INDEX idx_pim_product_videos_external ON public.pim_product_videos USING btree (platform, external_video_id) WHERE (external_video_id IS NOT NULL);

CREATE INDEX idx_pim_product_videos_keywords ON public.pim_product_videos USING gin (keywords);

CREATE INDEX idx_pim_product_videos_product_current ON public.pim_product_videos USING btree (product_id, is_current, display_order) WHERE (archived_at IS NULL);

CREATE INDEX idx_pim_product_videos_type ON public.pim_product_videos USING btree (video_type);

CREATE INDEX idx_pim_videos_product ON public.pim_product_videos USING btree (product_id);

CREATE INDEX idx_retailer_prices_checked ON public.pim_retailer_prices USING btree (checked_at);

CREATE INDEX idx_retailer_prices_country ON public.pim_retailer_prices USING btree (country);

CREATE INDEX idx_retailer_prices_model ON public.pim_retailer_prices USING btree (brand_name, model);

CREATE INDEX idx_retailer_prices_product ON public.pim_retailer_prices USING btree (product_id);

CREATE INDEX idx_retailer_prices_retailer ON public.pim_retailer_prices USING btree (retailer_name);

CREATE UNIQUE INDEX idx_spec_discovery_product ON public.pim_spec_discovery_jobs USING btree (product_id);

CREATE INDEX idx_spec_discovery_status ON public.pim_spec_discovery_jobs USING btree (status, updated_at);

CREATE INDEX idx_pim_video_jobs_product ON public.pim_video_discovery_jobs USING btree (product_id);

CREATE INDEX idx_pim_video_jobs_status ON public.pim_video_discovery_jobs USING btree (status, updated_at);

CREATE INDEX idx_pim_warranty_product ON public.pim_warranty_details USING btree (product_id);

CREATE INDEX pipeline_stages_org_idx ON public.pipeline_stages USING btree (organization_id, sort_order);

CREATE INDEX idx_piq_notif_publish ON public.piq_notifications USING btree (publish_at DESC);

CREATE INDEX idx_piq_retailer_brands_user ON public.piq_retailer_brands USING btree (user_id);

CREATE INDEX idx_pda_asset_type ON public.product_design_assets USING btree (asset_type);

CREATE INDEX idx_pda_product_current ON public.product_design_assets USING btree (product_id, is_current) WHERE (is_current = true);

CREATE INDEX idx_pda_verification ON public.product_design_assets USING btree (verification_status);

CREATE INDEX product_design_assets_brand_idx ON public.product_design_assets USING btree (brand_id);

CREATE INDEX product_design_assets_product_idx ON public.product_design_assets USING btree (product_id);

CREATE INDEX product_design_assets_type_idx ON public.product_design_assets USING btree (asset_type);

CREATE INDEX idx_piq_brand_scopes_brand ON public.product_iq_brand_scopes USING btree (brand_id, vendor_id, status);

CREATE INDEX idx_piq_audit_created ON public.product_iq_governance_audit_log USING btree (created_at DESC);

CREATE INDEX idx_piq_platform_roles_user ON public.product_iq_platform_roles USING btree (user_id, status);

CREATE INDEX idx_lifecycle_brand ON public.product_lifecycle USING btree (brand_id);

CREATE INDEX idx_lifecycle_category ON public.product_lifecycle USING btree (category);

CREATE INDEX idx_lifecycle_model ON public.product_lifecycle USING btree (model_number);

CREATE INDEX idx_lifecycle_status ON public.product_lifecycle USING btree (lifecycle_status);

CREATE INDEX idx_products_aiq_product_id ON public.products USING btree (aiq_product_id);

CREATE INDEX products_embedding_idx ON public.products USING hnsw (embedding vector_cosine_ops);

CREATE INDEX products_org_idx ON public.products USING btree (organization_id, category);

CREATE UNIQUE INDEX profiles_id_unique_idx ON public.profiles USING btree (id);

CREATE INDEX recording_transcripts_org_idx ON public.recording_transcripts USING btree (organization_id);

CREATE INDEX recording_transcripts_rec_idx ON public.recording_transcripts USING btree (recording_id);

CREATE INDEX idx_retailer_locations_city ON public.retailer_locations USING btree (city);

CREATE INDEX idx_retailer_locations_country ON public.retailer_locations USING btree (country);

CREATE INDEX idx_retailer_locations_geo ON public.retailer_locations USING btree (latitude, longitude);

CREATE INDEX idx_retailer_locations_province ON public.retailer_locations USING btree (province_state);

CREATE INDEX idx_retailer_locations_retailer ON public.retailer_locations USING btree (retailer_id);

CREATE INDEX idx_sales_recordings_deal_id ON public.sales_recordings USING btree (deal_id) WHERE (deal_id IS NOT NULL);

CREATE INDEX sales_recordings_crm_record_idx ON public.sales_recordings USING btree (crm_record_type, crm_record_id) WHERE (crm_record_id IS NOT NULL);

CREATE INDEX sales_recordings_org_created_idx ON public.sales_recordings USING btree (organization_id, created_at DESC);

CREATE INDEX sales_recordings_review_idx ON public.sales_recordings USING btree (coaching_review_id) WHERE (coaching_review_id IS NOT NULL);

CREATE INDEX sales_recordings_transcript_idx ON public.sales_recordings USING btree (transcript_id) WHERE (transcript_id IS NOT NULL);

CREATE INDEX sales_recordings_user_idx ON public.sales_recordings USING btree (user_id);

CREATE INDEX st_brand_idx ON public.sales_transactions USING btree (organization_id, brand, transaction_date DESC);

CREATE INDEX st_location_idx ON public.sales_transactions USING btree (location_id, transaction_date DESC);

CREATE INDEX st_org_date_idx ON public.sales_transactions USING btree (organization_id, transaction_date DESC);

CREATE INDEX st_user_idx ON public.sales_transactions USING btree (user_id, transaction_date DESC);

CREATE INDEX idx_siq_templates_category ON public.service_iq_templates USING btree (category);

CREATE INDEX idx_siq_templates_channel ON public.service_iq_templates USING btree (channel);

CREATE INDEX idx_speciq_approval_history_package ON public.speciq_approval_history USING btree (package_id);

CREATE INDEX idx_speciq_extension_requests_package ON public.speciq_extension_requests USING btree (package_id);

CREATE INDEX idx_speciq_package_events_pkg ON public.speciq_package_events USING btree (package_id);

CREATE INDEX idx_speciq_package_products_pkg ON public.speciq_package_products USING btree (package_id);

CREATE INDEX idx_speciq_pp_aiq_product_id ON public.speciq_package_products USING btree (aiq_product_id);

CREATE INDEX idx_speciq_pp_brand_id ON public.speciq_package_products USING btree (brand_id);

CREATE INDEX speciq_package_products_source_comparison_idx ON public.speciq_package_products USING btree (source_comparison_id);

CREATE INDEX idx_speciq_packages_approval_status ON public.speciq_packages USING btree (approval_status);

CREATE INDEX idx_speciq_packages_contact ON public.speciq_packages USING btree (contact_id) WHERE (contact_id IS NOT NULL);

CREATE INDEX idx_speciq_packages_deal ON public.speciq_packages USING btree (deal_id) WHERE (deal_id IS NOT NULL);

CREATE INDEX idx_speciq_packages_expires ON public.speciq_packages USING btree (quote_expires_at);

CREATE INDEX idx_speciq_packages_org ON public.speciq_packages USING btree (organization_id);

CREATE INDEX idx_speciq_packages_org_status ON public.speciq_packages USING btree (organization_id, status);

CREATE INDEX idx_speciq_packages_project ON public.speciq_packages USING btree (project_id);

CREATE INDEX idx_speciq_packages_quote_number ON public.speciq_packages USING btree (quote_number);

CREATE INDEX idx_speciq_packages_share ON public.speciq_packages USING btree (share_token);

CREATE INDEX idx_speciq_packages_status ON public.speciq_packages USING btree (status);

CREATE INDEX idx_product_warranties_package ON public.speciq_product_warranties USING btree (package_id);

CREATE INDEX idx_product_warranties_product ON public.speciq_product_warranties USING btree (package_product_id);

CREATE INDEX idx_speciq_projects_contact_id ON public.speciq_projects USING btree (contact_id);

CREATE INDEX idx_speciq_projects_deal_id ON public.speciq_projects USING btree (deal_id);

CREATE INDEX idx_speciq_projects_org ON public.speciq_projects USING btree (organization_id);

CREATE INDEX idx_speciq_retailer_settings_org ON public.speciq_retailer_settings USING btree (organization_id);

CREATE INDEX idx_speciq_tax_rules_org ON public.speciq_tax_rules USING btree (organization_id);

CREATE INDEX idx_warranty_catalog_org ON public.speciq_warranty_catalog USING btree (organization_id);

CREATE INDEX idx_warranty_catalog_type ON public.speciq_warranty_catalog USING btree (warranty_type);

CREATE INDEX stripe_events_org_idx ON public.stripe_events USING btree (organization_id);

CREATE INDEX stripe_events_type_idx ON public.stripe_events USING btree (event_type);

-- =========================
-- FUNCTIONS
-- =========================

CREATE OR REPLACE FUNCTION public.accept_invite(p_invite_code text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  v_invite record;
  v_user_id uuid;
  v_existing record;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    return jsonb_build_object('error', 'not_authenticated');
  end if;

  select * into v_invite from public.org_invites
  where invite_code = p_invite_code and status = 'pending'
  for update;

  if not found then
    return jsonb_build_object('error', 'invite_not_found_or_used');
  end if;

  if v_invite.expires_at < now() then
    update public.org_invites set status = 'expired' where id = v_invite.id;
    return jsonb_build_object('error', 'invite_expired');
  end if;

  -- Check email matches (case-insensitive)
  if lower((select email from auth.users where id = v_user_id)) != lower(v_invite.invited_email) then
    return jsonb_build_object('error', 'email_mismatch', 'detail', 'Sign in with the email that was invited.');
  end if;

  -- Check if already a member
  select * into v_existing from public.organization_members
  where organization_id = v_invite.organization_id and user_id = v_user_id;
  if found then
    update public.org_invites set status = 'accepted', accepted_at = now() where id = v_invite.id;
    return jsonb_build_object('ok', true, 'already_member', true);
  end if;

  -- Create membership
  insert into public.organization_members (organization_id, user_id, role, status, org_role_id, manager_id)
  values (v_invite.organization_id, v_user_id, v_invite.role, 'active', v_invite.org_role_id, v_invite.manager_id);

  update public.org_invites set status = 'accepted', accepted_at = now() where id = v_invite.id;

  -- Initialize token limits if org has billing
  insert into public.ai_token_limits (organization_id, monthly_limit, tokens_used_this_month)
  select v_invite.organization_id, 
    case (select tier from public.organizations where id = v_invite.organization_id)
      when 'starter' then 100000
      when 'pro' then 1000000
      when 'enterprise' then 10000000
      else 10000
    end, 0
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'organization_id', v_invite.organization_id);
end;

$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_add_comment(p_assignment_id uuid, p_body text, p_comment_type text DEFAULT 'comment'::text) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare a public.ai_manager_assignments%rowtype; cid uuid;
begin
 select * into a from public.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not public.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 insert into public.ai_manager_task_comments(organization_id,assignment_id,author_id,body,comment_type) values(a.organization_id,a.id,(select auth.uid()),trim(p_body),p_comment_type) returning id into cid;
 insert into public.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,note) values(a.organization_id,a.id,(select auth.uid()),'comment_added',left(trim(p_body),500));
 return jsonb_build_object('ok',true,'comment_id',cid);
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_assign_task(p_assignment_id uuid, p_assigned_to uuid DEFAULT NULL::uuid, p_assigned_role text DEFAULT NULL::text, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare a public.ai_manager_assignments%rowtype; old_owner uuid;
begin
 select * into a from public.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not public.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 if p_assigned_to is not null and not exists(select 1 from public.organization_members m where m.organization_id=a.organization_id and m.user_id=p_assigned_to and coalesce(m.status,'active')='active') then return jsonb_build_object('error','assignee_not_in_organization'); end if;
 old_owner:=a.assigned_to;
 update public.ai_manager_assignments set assigned_to=p_assigned_to,assigned_role=nullif(trim(p_assigned_role),''),assigned_by=(select auth.uid()),due_at=coalesce(p_due_at,due_at),updated_at=now() where id=a.id;
 insert into public.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,from_value,to_value,metadata) values(a.organization_id,a.id,(select auth.uid()),case when old_owner is null then 'assigned' else 'reassigned' end,old_owner::text,p_assigned_to::text,jsonb_build_object('assigned_role',p_assigned_role,'due_at',p_due_at));
 return jsonb_build_object('ok',true);
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text DEFAULT 'morning'::text, p_brief_date date DEFAULT CURRENT_DATE) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare
  v_start date;
  v_end date;
  v_open integer;
  v_overdue integer;
  v_completed integer;
  v_critical integer;
  v_exposure numeric;
  v_predicted numeric;
  v_top jsonb;
  v_risks jsonb;
  v_wins jsonb;
  v_headline text;
  v_summary text;
  v_id uuid;
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'organization_access_denied';
  end if;
  if p_brief_type not in ('morning','end_of_day','weekly') then
    raise exception 'unsupported_brief_type';
  end if;

  if p_brief_type='weekly' then
    v_start := date_trunc('week',p_brief_date)::date;
    v_end := v_start + 6;
  else
    v_start := p_brief_date;
    v_end := p_brief_date;
  end if;

  select count(*) filter(where status not in ('completed','cancelled')),
         count(*) filter(where status not in ('completed','cancelled') and due_at < now()),
         count(*) filter(where status='completed' and completed_at::date between v_start and v_end)
  into v_open,v_overdue,v_completed
  from public.ai_manager_assignments
  where organization_id=p_organization_id;

  select count(*) filter(where severity='critical' and status not in ('completed','dismissed','rejected','expired')),
         coalesce(sum(financial_impact_cad) filter(where status not in ('completed','dismissed','rejected','expired')),0)
  into v_critical,v_exposure
  from public.decision_cases
  where organization_id=p_organization_id;

  select coalesce(sum(financial_impact_cad) filter(where status='active'),0)
  into v_predicted
  from public.decision_predictions
  where organization_id=p_organization_id;

  select coalesce(jsonb_agg(x order by (x->>'priority_score')::numeric desc),'[]'::jsonb)
  into v_top
  from (
    select jsonb_build_object(
      'id',id,'title',title,'module',module,'severity',severity,
      'priority_score',priority_score,'financial_impact_cad',financial_impact_cad,
      'recommendation',recommendation,'due_at',due_at
    ) x
    from public.decision_cases
    where organization_id=p_organization_id
      and status not in ('completed','dismissed','rejected','expired')
    order by priority_score desc nulls last
    limit 5
  ) s;

  select coalesce(jsonb_agg(x),'[]'::jsonb)
  into v_risks
  from (
    select jsonb_build_object('title',title,'priority',priority,'due_at',due_at,'status',status,'blocked_reason',blocked_reason) x
    from public.ai_manager_assignments
    where organization_id=p_organization_id
      and (status='blocked' or (status not in ('completed','cancelled') and due_at < now()))
    order by due_at asc nulls last
    limit 5
  ) s;

  select coalesce(jsonb_agg(x),'[]'::jsonb)
  into v_wins
  from (
    select jsonb_build_object('title',title,'completed_at',completed_at,'priority',priority) x
    from public.ai_manager_assignments
    where organization_id=p_organization_id and status='completed'
      and completed_at::date between v_start and v_end
    order by completed_at desc
    limit 5
  ) s;

  if p_brief_type='morning' then
    v_headline := case when v_critical>0 then v_critical||' critical issue'||case when v_critical=1 then '' else 's' end||' require attention today'
      when v_overdue>0 then v_overdue||' overdue assignment'||case when v_overdue=1 then '' else 's' end||' require action'
      else 'Operations are stable; focus on the highest-value opportunity' end;
    v_summary := format('Start the day with %s active assignments, %s overdue, and %s in open financial exposure. Current predicted opportunity is %s.',v_open,v_overdue,to_char(v_exposure,'FM$999,999,990'),to_char(v_predicted,'FM$999,999,990'));
  elsif p_brief_type='end_of_day' then
    v_headline := v_completed||' assignment'||case when v_completed=1 then '' else 's' end||' completed today';
    v_summary := format('The day closed with %s completed assignments, %s still open, and %s overdue. Remaining exposure is %s.',v_completed,v_open,v_overdue,to_char(v_exposure,'FM$999,999,990'));
  else
    v_headline := format('Weekly operating review: %s completed, %s open, %s overdue',v_completed,v_open,v_overdue);
    v_summary := format('For %s through %s, the organization completed %s assignments. Open financial exposure is %s and active predicted opportunity is %s.',to_char(v_start,'Mon DD'),to_char(v_end,'Mon DD'),v_completed,to_char(v_exposure,'FM$999,999,990'),to_char(v_predicted,'FM$999,999,990'));
  end if;

  insert into public.ai_manager_briefs(
    organization_id,brief_date,brief_type,period_start,period_end,headline,executive_summary,
    priorities,risks,wins,workload,financial_exposure_cad,narrative,generated_by,generated_at
  ) values (
    p_organization_id,p_brief_date,p_brief_type,v_start,v_end,v_headline,v_summary,
    v_top,v_risks,v_wins,
    jsonb_build_object('open',v_open,'overdue',v_overdue,'completed',v_completed,'critical',v_critical),
    v_exposure,
    jsonb_build_object('predicted_opportunity_cad',v_predicted,'recommended_focus',coalesce(v_top->0->>'recommendation','Review the highest-priority open assignment.')),
    auth.uid(),now()
  )
  on conflict (organization_id,brief_type,coalesce(period_start,brief_date),coalesce(period_end,brief_date))
  do update set headline=excluded.headline,executive_summary=excluded.executive_summary,priorities=excluded.priorities,
    risks=excluded.risks,wins=excluded.wins,workload=excluded.workload,financial_exposure_cad=excluded.financial_exposure_cad,
    narrative=excluded.narrative,generated_by=excluded.generated_by,generated_at=now()
  returning id into v_id;

  return public.ai_manager_get_executive_briefs(p_organization_id,10,v_id);
end 
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_get_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare v_result jsonb;
begin
 if not public.is_org_member(p_organization_id) then raise exception 'not_authorized'; end if;
 select jsonb_build_object(
  'brief',(select to_jsonb(b) from public.ai_manager_briefs b where b.organization_id=p_organization_id order by b.brief_date desc,b.generated_at desc limit 1),
  'summary',jsonb_build_object(
    'open',(select count(*) from public.ai_manager_assignments where organization_id=p_organization_id and status in ('open','accepted','in_progress')),
    'blocked',(select count(*) from public.ai_manager_assignments where organization_id=p_organization_id and status='blocked'),
    'overdue',(select count(*) from public.ai_manager_assignments where organization_id=p_organization_id and status not in ('completed','cancelled') and due_at<now()),
    'completed_7d',(select count(*) from public.ai_manager_assignments where organization_id=p_organization_id and status='completed' and completed_at>=now()-interval '7 days'),
    'open_escalations',(select count(*) from public.ai_manager_escalations where organization_id=p_organization_id and status='open')
  ),
  'assignments',(select coalesce(jsonb_agg(to_jsonb(a) order by case a.priority when 'critical' then 4 when 'high' then 3 when 'medium' then 2 else 1 end desc,a.due_at asc),'[]'::jsonb) from public.ai_manager_assignments a where a.organization_id=p_organization_id and a.status not in ('completed','cancelled')),
  'recent_completed',(select coalesce(jsonb_agg(to_jsonb(a) order by a.completed_at desc),'[]'::jsonb) from (select * from public.ai_manager_assignments where organization_id=p_organization_id and status='completed' order by completed_at desc limit 10) a),
  'escalations',(select coalesce(jsonb_agg(to_jsonb(e) order by e.level desc,e.created_at desc),'[]'::jsonb) from public.ai_manager_escalations e where e.organization_id=p_organization_id and e.status='open')
 ) into v_result;
 return v_result;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_get_executive_briefs(p_organization_id uuid, p_limit integer DEFAULT 20, p_focus_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql AS $fn$

  select case when public.is_org_member(p_organization_id) then jsonb_build_object(
    'summary',jsonb_build_object(
      'latest_generated_at',(select max(generated_at) from public.ai_manager_briefs where organization_id=p_organization_id),
      'draft_count',(select count(*) from public.ai_manager_briefs where organization_id=p_organization_id and delivery_status='draft'),
      'delivered_count',(select count(*) from public.ai_manager_briefs where organization_id=p_organization_id and delivery_status='delivered')
    ),
    'briefs',coalesce((select jsonb_agg(to_jsonb(b) order by b.generated_at desc)
      from (select * from public.ai_manager_briefs where organization_id=p_organization_id and (p_focus_id is null or id=p_focus_id) order by generated_at desc limit greatest(1,least(p_limit,50))) b),'[]'::jsonb)
  ) else jsonb_build_object('error','organization_access_denied') end

$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_get_members(p_organization_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$

begin
 if not public.is_org_member(p_organization_id) then return jsonb_build_object('error','access_denied'); end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'role',m.role,'manager_id',m.manager_id,'name',coalesce(p.full_name,p.email,m.user_id::text),'email',p.email) order by coalesce(p.full_name,p.email,m.user_id::text)) from public.organization_members m left join public.profiles p on p.user_id=m.user_id where m.organization_id=p_organization_id and coalesce(m.status,'active')='active'),'[]'::jsonb);
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_get_my_work(p_organization_id uuid, p_scope text DEFAULT 'mine'::text) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare uid uuid:=(select auth.uid());
begin
 if not public.is_org_member(p_organization_id) then return jsonb_build_object('error','access_denied'); end if;
 return jsonb_build_object(
 'members',(select public.ai_manager_get_members(p_organization_id)),
 'assignments',coalesce((select jsonb_agg(x order by (x->>'due_at') nulls last) from (select jsonb_build_object('id',a.id,'title',a.title,'instructions',a.instructions,'priority',a.priority,'status',a.status,'due_at',a.due_at,'assigned_to',a.assigned_to,'assigned_role',a.assigned_role,'assignee_name',coalesce(p.full_name,p.email,a.assigned_to::text),'approval_status',a.approval_status,'proof_required',a.proof_required,'completion_summary',a.completion_summary,'rejection_reason',a.rejection_reason,'escalation_level',a.escalation_level,'comments',(select count(*) from public.ai_manager_task_comments c where c.assignment_id=a.id),'attachments',(select count(*) from public.ai_manager_task_attachments f where f.assignment_id=a.id),'proofs',(select count(*) from public.ai_manager_task_attachments f where f.assignment_id=a.id and f.attachment_type='proof')) x from public.ai_manager_assignments a left join public.profiles p on p.user_id=a.assigned_to where a.organization_id=p_organization_id and (p_scope='team' or a.assigned_to=uid or (a.assigned_to is null and a.assigned_role in (select m.role from public.organization_members m where m.organization_id=p_organization_id and m.user_id=uid)))) s),'[]'::jsonb),
 'pending_approvals',(select count(*) from public.ai_manager_assignments a where a.organization_id=p_organization_id and a.approval_status='pending'),
 'overdue',(select count(*) from public.ai_manager_assignments a where a.organization_id=p_organization_id and a.status not in ('completed','cancelled') and a.due_at<now() and (p_scope='team' or a.assigned_to=uid))
 );
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_get_task_detail(p_assignment_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare a public.ai_manager_assignments%rowtype;
begin
 select * into a from public.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not public.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 return jsonb_build_object('assignment',to_jsonb(a),'comments',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'body',c.body,'type',c.comment_type,'created_at',c.created_at,'author_name',coalesce(p.full_name,p.email,c.author_id::text)) order by c.created_at) from public.ai_manager_task_comments c left join public.profiles p on p.user_id=c.author_id where c.assignment_id=a.id),'[]'::jsonb),'attachments',coalesce((select jsonb_agg(to_jsonb(f) order by f.created_at) from public.ai_manager_task_attachments f where f.assignment_id=a.id),'[]'::jsonb),'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from public.ai_manager_task_history h where h.assignment_id=a.id),'[]'::jsonb),'escalations',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.ai_manager_escalations e where e.assignment_id=a.id),'[]'::jsonb));
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_mark_brief_delivered(p_brief_id uuid, p_channels jsonb DEFAULT '["in_app"]'::jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare v_row public.ai_manager_briefs;
begin
  select * into v_row from public.ai_manager_briefs where id=p_brief_id;
  if v_row.id is null or not public.is_org_member(v_row.organization_id) then raise exception 'brief_access_denied'; end if;
  update public.ai_manager_briefs set delivery_status='delivered',delivery_channels=coalesce(p_channels,'[]'::jsonb),delivered_at=now() where id=p_brief_id returning * into v_row;
  return to_jsonb(v_row);
end 
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_register_attachment(p_assignment_id uuid, p_storage_path text, p_file_name text, p_mime_type text, p_file_size_bytes bigint, p_attachment_type text DEFAULT 'supporting'::text) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare a public.ai_manager_assignments%rowtype; aid uuid;
begin
 select * into a from public.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not public.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 if split_part(p_storage_path,'/',1)<>a.organization_id::text or split_part(p_storage_path,'/',2)<>a.id::text then return jsonb_build_object('error','invalid_storage_path'); end if;
 insert into public.ai_manager_task_attachments(organization_id,assignment_id,uploaded_by,storage_path,file_name,mime_type,file_size_bytes,attachment_type) values(a.organization_id,a.id,(select auth.uid()),p_storage_path,p_file_name,p_mime_type,p_file_size_bytes,p_attachment_type) returning id into aid;
 insert into public.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,note,metadata) values(a.organization_id,a.id,(select auth.uid()),'attachment_added',p_file_name,jsonb_build_object('attachment_type',p_attachment_type));
 return jsonb_build_object('ok',true,'attachment_id',aid);
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_review_completion(p_assignment_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare a public.ai_manager_assignments%rowtype;
begin
 select * into a from public.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not public.is_org_admin(a.organization_id) then return jsonb_build_object('error','admin_required'); end if;
 if a.approval_status<>'pending' then return jsonb_build_object('error','not_pending_approval'); end if;
 if p_approve then
  update public.ai_manager_assignments set approval_status='approved',approved_at=now(),approved_by=(select auth.uid()),rejection_reason=null,updated_at=now() where id=a.id;
  update public.decision_cases set status='completed',resolved_at=now(),updated_by=(select auth.uid()),updated_at=now() where id=a.decision_case_id;
  insert into public.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,from_value,to_value) values(a.organization_id,a.id,(select auth.uid()),'completion_approved','pending','approved');
 else
  update public.ai_manager_assignments set status='in_progress',approval_status='rejected',rejection_reason=coalesce(nullif(trim(p_reason),''),'Revision required'),completed_at=null,updated_at=now() where id=a.id;
  insert into public.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,from_value,to_value,note) values(a.organization_id,a.id,(select auth.uid()),'completion_rejected','pending','rejected',coalesce(nullif(trim(p_reason),''),'Revision required'));
 end if;
 return jsonb_build_object('ok',true,'approval_status',case when p_approve then 'approved' else 'rejected' end);
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_run_cycle(p_organization_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare
  v_created int := 0;
  v_overdue int := 0;
  v_escalated int := 0;
  v_open int := 0;
  v_blocked int := 0;
  v_completed_7d int := 0;
  v_financial numeric := 0;
  v_priorities jsonb;
  v_risks jsonb;
  v_wins jsonb;
  v_headline text;
  v_summary text;
begin
  if not public.is_org_member(p_organization_id) then raise exception 'not_authorized'; end if;

  insert into public.ai_manager_assignments(organization_id,decision_case_id,title,instructions,assigned_to,assigned_by,priority,status,due_at,metadata)
  select c.organization_id,c.id,c.title,
    coalesce(c.recommendation,'Review the evidence, choose an action, and record the result.'),
    c.owner_id,auth.uid(),
    case c.severity when 'critical' then 'critical' when 'high' then 'high' when 'medium' then 'medium' else 'low' end,
    'open',
    coalesce(c.due_at, now() + case c.severity when 'critical' then interval '4 hours' when 'high' then interval '1 day' when 'medium' then interval '3 days' else interval '7 days' end),
    jsonb_build_object('module',c.module,'priority_score',c.priority_score,'financial_impact_cad',c.financial_impact_cad,'source_system',c.source_system)
  from public.decision_cases c
  where c.organization_id=p_organization_id and c.status in ('open','accepted','in_progress')
    and not exists(select 1 from public.ai_manager_assignments a where a.decision_case_id=c.id and a.status in ('open','accepted','in_progress','blocked'))
  on conflict do nothing;
  get diagnostics v_created = row_count;

  update public.ai_manager_assignments a
  set escalation_level=least(5,case when now()>a.due_at+interval '7 days' then 3 when now()>a.due_at+interval '2 days' then 2 when now()>a.due_at then 1 else a.escalation_level end),updated_at=now()
  where a.organization_id=p_organization_id and a.status not in ('completed','cancelled') and a.due_at<now();
  get diagnostics v_overdue = row_count;

  insert into public.ai_manager_escalations(organization_id,assignment_id,level,reason,escalated_to,metadata)
  select a.organization_id,a.id,a.escalation_level,
    case a.escalation_level when 3 then 'Task is more than seven days overdue.' when 2 then 'Task is more than two days overdue.' else 'Task is overdue.' end,
    a.assigned_by,jsonb_build_object('due_at',a.due_at,'priority',a.priority)
  from public.ai_manager_assignments a
  where a.organization_id=p_organization_id and a.escalation_level>0 and a.status not in ('completed','cancelled')
  on conflict do nothing;
  get diagnostics v_escalated = row_count;

  select count(*) filter(where status in ('open','accepted','in_progress')),count(*) filter(where status='blocked'),count(*) filter(where status='completed' and completed_at>=now()-interval '7 days')
  into v_open,v_blocked,v_completed_7d from public.ai_manager_assignments where organization_id=p_organization_id;

  select coalesce(sum(coalesce(financial_impact_cad,0)),0) into v_financial from public.decision_cases where organization_id=p_organization_id and status in ('open','accepted','in_progress');

  select coalesce(jsonb_agg(x order by (x->>'priority_score')::numeric desc),'[]'::jsonb) into v_priorities from (
    select jsonb_build_object('case_id',c.id,'title',c.title,'module',c.module,'severity',c.severity,'priority_score',coalesce(c.priority_score,0),'financial_impact_cad',coalesce(c.financial_impact_cad,0),'recommendation',c.recommendation) x
    from public.decision_cases c where c.organization_id=p_organization_id and c.status in ('open','accepted','in_progress') order by c.priority_score desc nulls last limit 5
  ) q;

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_risks from (
    select jsonb_build_object('assignment_id',a.id,'title',a.title,'priority',a.priority,'status',a.status,'due_at',a.due_at,'escalation_level',a.escalation_level) x
    from public.ai_manager_assignments a where a.organization_id=p_organization_id and (a.status='blocked' or a.due_at<now()) order by a.escalation_level desc,a.due_at asc limit 5
  ) q;

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_wins from (
    select jsonb_build_object('assignment_id',a.id,'title',a.title,'completed_at',a.completed_at) x
    from public.ai_manager_assignments a where a.organization_id=p_organization_id and a.status='completed' and a.completed_at>=now()-interval '7 days' order by a.completed_at desc limit 5
  ) q;

  v_headline := case when v_overdue>0 then v_overdue||' overdue task'||case when v_overdue=1 then '' else 's' end||' require attention' when v_open>0 then v_open||' active management priorit'||case when v_open=1 then 'y' else 'ies' end when v_completed_7d>0 then v_completed_7d||' task'||case when v_completed_7d=1 then '' else 's' end||' completed this week' else 'No active management exceptions' end;
  v_summary := format('The AI Manager created %s new assignment(s), is tracking %s active item(s), %s blocked item(s), and %s escalation(s). Open decisions represent approximately C$%s in stated financial impact.',v_created,v_open,v_blocked,v_escalated,to_char(v_financial,'FM999G999G999G990'));

  insert into public.ai_manager_briefs(organization_id,brief_date,brief_type,headline,executive_summary,priorities,risks,wins,workload,financial_exposure_cad,generated_by,generated_at)
  values(p_organization_id,current_date,'daily',v_headline,v_summary,v_priorities,v_risks,v_wins,jsonb_build_object('open',v_open,'blocked',v_blocked,'overdue',v_overdue,'completed_7d',v_completed_7d,'new_assignments',v_created,'new_escalations',v_escalated),v_financial,auth.uid(),now())
  on conflict(organization_id,brief_date,brief_type) do update set headline=excluded.headline,executive_summary=excluded.executive_summary,priorities=excluded.priorities,risks=excluded.risks,wins=excluded.wins,workload=excluded.workload,financial_exposure_cad=excluded.financial_exposure_cad,generated_by=excluded.generated_by,generated_at=now();

  return jsonb_build_object('new_assignments',v_created,'overdue',v_overdue,'new_escalations',v_escalated,'open',v_open,'blocked',v_blocked,'completed_7d',v_completed_7d,'financial_exposure_cad',v_financial);
end 
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_submit_completion(p_assignment_id uuid, p_completion_summary text) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare a public.ai_manager_assignments%rowtype; proofs int;
begin
 select * into a from public.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not public.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 if a.assigned_to is distinct from (select auth.uid()) and not public.is_org_admin(a.organization_id) then return jsonb_build_object('error','only_owner_or_admin_can_submit'); end if;
 select count(*) into proofs from public.ai_manager_task_attachments where assignment_id=a.id and attachment_type='proof';
 if a.proof_required and proofs=0 then return jsonb_build_object('error','proof_required'); end if;
 update public.ai_manager_assignments set status='completed',submitted_at=now(),submitted_by=(select auth.uid()),completion_summary=trim(p_completion_summary),approval_status='pending',completed_at=now(),updated_at=now() where id=a.id;
 insert into public.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,to_value,note) values(a.organization_id,a.id,(select auth.uid()),'submitted_for_approval','pending',trim(p_completion_summary));
 return jsonb_build_object('ok',true,'approval_status','pending');
end
$fn$;

CREATE OR REPLACE FUNCTION public.ai_manager_update_assignment(p_assignment_id uuid, p_status text, p_blocked_reason text DEFAULT NULL::text, p_assigned_to uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare v public.ai_manager_assignments;
begin
 select * into v from public.ai_manager_assignments where id=p_assignment_id;
 if v.id is null or not public.is_org_member(v.organization_id) then raise exception 'not_authorized'; end if;
 if p_status not in ('open','accepted','in_progress','blocked','completed','cancelled') then raise exception 'invalid_status'; end if;
 update public.ai_manager_assignments set status=p_status,blocked_reason=case when p_status='blocked' then p_blocked_reason else null end,assigned_to=coalesce(p_assigned_to,assigned_to),due_at=coalesce(p_due_at,due_at),accepted_at=case when p_status='accepted' and accepted_at is null then now() else accepted_at end,started_at=case when p_status='in_progress' and started_at is null then now() else started_at end,completed_at=case when p_status='completed' then now() else completed_at end,updated_at=now() where id=p_assignment_id returning * into v;
 if p_status='completed' then
   update public.decision_cases set status='completed',resolved_at=now(),updated_at=now() where id=v.decision_case_id;
   update public.ai_manager_escalations set status='resolved',resolved_at=now() where assignment_id=v.id and status='open';
 end if;
 return to_jsonb(v);
end 
$fn$;

CREATE OR REPLACE FUNCTION public.ai_submit_request(p_organization_id uuid DEFAULT NULL::uuid, p_assistant_key text DEFAULT NULL::text, p_prompt text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_assistant public.ai_assistants%rowtype;
  v_session uuid;
  v_request uuid;
  v_grounded jsonb;
  v_action uuid;
begin
  if v_user is null then
    raise exception 'Authentication required.';
  end if;
  if p_assistant_key is null or coalesce(length(trim(p_prompt)),0) < 3 then
    raise exception 'assistant_key and prompt are required.';
  end if;

  if p_organization_id is not null then
    if not public.is_org_member(p_organization_id) then
      raise exception 'Access denied for organization.';
    end if;
    v_org := p_organization_id;
  else
    select organization_id into v_org
      from public.organization_members
     where user_id = v_user and status = 'active'
     order by created_at limit 1;
    if v_org is null then
      raise exception 'Access denied: no active organization membership.';
    end if;
  end if;

  select * into v_assistant from public.ai_assistants
   where assistant_key = p_assistant_key and status = 'active';
  if not found then
    raise exception 'Unknown or inactive assistant.';
  end if;
  if v_assistant.organization_id is not null and v_assistant.organization_id <> v_org then
    raise exception 'Access denied: assistant not available for this organization.';
  end if;

  insert into public.ai_sessions (organization_id, user_id, assistant_key)
  values (v_org, v_user, p_assistant_key)
  returning id into v_session;

  v_grounded := jsonb_build_object(
    'record_counts', jsonb_build_object(
      'companies', (select count(*) from public.companies c where c.organization_id = v_org),
      'contacts', (select count(*) from public.contacts c where c.organization_id = v_org),
      'deals', (select count(*) from public.crm_deals d where d.organization_id = v_org),
      'open_tasks', (select count(*) from public.crm_tasks t where t.organization_id = v_org and t.completed_at is null),
      'products', (select count(*) from public.products p where p.organization_id = v_org)
    ),
    'pipeline', (select coalesce(jsonb_object_agg(stage, cnt), '{}'::jsonb)
                 from (select stage, count(*) cnt from public.crm_deals d
                       where d.organization_id = v_org and d.closed_at is null
                       group by stage) s),
    'generated_at', now()
  );

  insert into public.ai_requests
    (organization_id, session_id, user_id, assistant_key, request_status, prompt, context, grounded_context,
     output, explanation, model_provider, model_name, completed_at)
  values
    (v_org, v_session, v_user, p_assistant_key, 'completed', p_prompt, coalesce(p_context,'{}'::jsonb), v_grounded,
     jsonb_build_object('mode','foundation','assistant_key',p_assistant_key,
       'notice','Governed request recorded. Model layer produces the final answer.'),
     'Foundation envelope: auth, tenancy, assistant visibility, grounded context, and audit recorded at the database layer.',
     'foundation','deterministic', now())
  returning id into v_request;

  if v_assistant.approval_required then
    insert into public.ai_proposed_actions (organization_id, request_id, assistant_key, action_type, action_payload)
    values (v_org, v_request, p_assistant_key, 'advisory_output_review',
            jsonb_build_object('prompt_preview', left(p_prompt, 200)))
    returning id into v_action;
  end if;

  insert into public.ai_audit_events (organization_id, request_id, assistant_key, event_type, event_payload)
  values (v_org, v_request, p_assistant_key, 'ai.request.submitted',
          jsonb_build_object('approval_required', v_assistant.approval_required));

  insert into public.ai_usage_meter (organization_id, assistant_key, request_id, usage_kind, quantity, limit_key)
  values (v_org, p_assistant_key, v_request, 'request', 1, 'ai.requests.monthly');

  return jsonb_build_object(
    'request_id', v_request,
    'session_id', v_session,
    'organization_id', v_org,
    'approval_required', v_assistant.approval_required,
    'proposed_action_id', v_action,
    'output', (select output from public.ai_requests where id = v_request)
  );
end 
$fn$;

CREATE OR REPLACE FUNCTION public.aicrm_collaboration_touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  new.updated_at := now();
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.aicrm_executive_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare
  v_payload jsonb;
begin
  if p_organization_id is null then
    raise exception 'organization_id is required';
  end if;

  if not private.user_can_access_organization(p_organization_id, 'crm.view') then
    raise exception 'permission denied';
  end if;

  with
  account_contact_counts as (
    select
      c.account_id,
      count(*)::integer as contact_count
    from public.aicrm_contacts c
    where c.organization_id = p_organization_id
    group by c.account_id
  ),
  account_open_opportunity_values as (
    select
      o.account_id,
      coalesce(sum(coalesce(o.opportunity_value, 0)), 0)::numeric as open_opportunity_value
    from public.aicrm_opportunities o
    where o.organization_id = p_organization_id
      and coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled', 'closed')
    group by o.account_id
  ),
  account_last_activity as (
    select
      a.id as account_id,
      max(act.activity_date) as last_activity_at
    from public.aicrm_accounts a
    left join public.aicrm_activities act
      on act.organization_id = p_organization_id
     and act.account_id = a.id
    where a.organization_id = p_organization_id
    group by a.id
  ),
  account_research as (
    select
      r.account_id,
      r.confidence,
      r.research_summary,
      r.mock_generated,
      r.last_updated,
      r.priority_score,
      r.score_explanation,
      r.recommended_products,
      r.recommended_campaign,
      r.recommended_campaign_reasoning,
      r.recommended_next_action,
      r.recommended_next_action_reasoning,
      r.recommended_next_action_confidence,
      r.product_fit_scores
    from public.aicrm_ai_research r
    where r.organization_id = p_organization_id
  ),
  account_base as (
    select
      a.id,
      a.company_name,
      a.category,
      a.province,
      a.revenue_tier,
      a.priority_score,
      a.channel_product_fit,
      a.next_action,
      a.status,
      a.do_not_contact,
      a.scoring_review_required,
      a.scoring_review_reason,
      a.website,
      a.owner_id,
      a.estimated_revenue,
      a.city,
      a.last_scored_at,
      coalesce(acc.contact_count, 0) as contact_count,
      coalesce(opp.open_opportunity_value, 0) as open_opportunity_value,
      ar.confidence,
      ar.research_summary,
      ar.mock_generated,
      ar.last_updated,
      ar.score_explanation,
      ar.recommended_products,
      ar.recommended_campaign,
      ar.recommended_campaign_reasoning,
      ar.recommended_next_action,
      ar.recommended_next_action_reasoning,
      ar.recommended_next_action_confidence,
      ar.product_fit_scores,
      act.last_activity_at
    from public.aicrm_accounts a
    left join account_contact_counts acc on acc.account_id = a.id
    left join account_open_opportunity_values opp on opp.account_id = a.id
    left join account_research ar on ar.account_id = a.id
    left join account_last_activity act on act.account_id = a.id
    where a.organization_id = p_organization_id
  ),
  contact_quality as (
    select
      avg(
        (
          (case when coalesce(c.full_name, '') <> '' or (coalesce(c.first_name, '') <> '' and coalesce(c.last_name, '') <> '') then 1 else 0 end)
          + (case when coalesce(c.title, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.role_type, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.account_id::text, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.email, '') <> '' or coalesce(c.phone, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.linkedin_url, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.priority, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.email_status, '') <> '' then 1 else 0 end)
        )::numeric / 8 * 100
      ) as average_contact_completeness,
      count(*) filter (where coalesce(c.full_name, '') = '' and coalesce(c.first_name, '') = '' and coalesce(c.last_name, '') = '') as contacts_missing_name
    from public.aicrm_contacts c
    where c.organization_id = p_organization_id
  ),
  account_quality as (
    select
      avg(
        (
          (case when coalesce(a.company_name, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.category, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.province, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.city, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.website, '') <> '' then 1 else 0 end)
          + (case when a.estimated_revenue is not null or coalesce(a.revenue_tier, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.verification_status, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.channel_product_fit, '') <> '' then 1 else 0 end)
          + (case when a.priority_score is not null then 1 else 0 end)
          + (case when coalesce(a.next_action, '') <> '' then 1 else 0 end)
        )::numeric / 10 * 100
      ) as average_account_completeness,
      count(*) filter (where coalesce(a.website, '') = '') as accounts_missing_website,
      count(*) filter (where a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '') as accounts_missing_revenue,
      count(*) filter (where coalesce(a.channel_product_fit, '') = '') as accounts_missing_product_fit,
      count(*) filter (where coalesce(ac.contact_count, 0) = 0) as accounts_missing_contacts
    from public.aicrm_accounts a
    left join account_contact_counts ac on ac.account_id = a.id
    where a.organization_id = p_organization_id
  ),
  top_targets as (
    select
      a.id as account_id,
      a.company_name,
      a.category,
      a.province,
      a.revenue_tier,
      coalesce(a.priority_score, 0) as priority_score,
      coalesce(ar.confidence, 0) as confidence,
      coalesce(a.channel_product_fit, '') as product_fit,
      coalesce(a.next_action, '') as next_action,
      coalesce(a.open_opportunity_value, 0) as open_opportunity_value
    from account_base a
    left join account_research ar on ar.account_id = a.id
    where coalesce(a.do_not_contact, false) = false
      and coalesce(lower(a.status), '') <> 'archived'
      and coalesce(ar.confidence, 0) >= 70
    order by coalesce(a.priority_score, 0) desc, a.company_name asc
    limit 100
  ),
  top_ai_opportunities as (
    select
      a.id as account_id,
      a.company_name,
      coalesce(a.priority_score, 0) as priority_score,
      coalesce(ar.confidence, 0) as confidence,
      coalesce(
        (
          select elem->>'product'
          from jsonb_array_elements(coalesce(ar.recommended_products, '[]'::jsonb)) elem
          where coalesce(elem->>'product', '') <> ''
          limit 1
        ),
        coalesce(a.channel_product_fit, ''),
        'Recommendation pending'
      ) as recommended_product,
      coalesce(ar.recommended_next_action, coalesce(a.next_action, ''), 'Review account') as recommended_next_action
    from account_base a
    left join account_research ar on ar.account_id = a.id
    where coalesce(a.do_not_contact, false) = false
      and coalesce(lower(a.status), '') <> 'archived'
      and coalesce(ar.confidence, 0) >= 70
    order by coalesce(a.priority_score, 0) desc, a.company_name asc
    limit 25
  ),
  review_queue as (
    select
      a.id as account_id,
      a.company_name,
      a.owner_id,
      coalesce(a.scoring_review_reason, case
        when coalesce(ar.confidence, 0) < 50 then 'Low confidence'
        when coalesce(a.website, '') = '' then 'Missing website'
        when coalesce(a.category, '') = '' then 'Missing category'
        when a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '' then 'Missing revenue'
        when coalesce(a.contact_count, 0) = 0 then 'No contacts'
        when coalesce(a.next_action, '') = '' then 'No next action'
        else 'Review required'
      end) as review_reason,
      array_remove(array[
        case when coalesce(a.website, '') = '' then 'website' end,
        case when coalesce(a.category, '') = '' then 'category' end,
        case when a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '' then 'revenue' end,
        case when coalesce(a.contact_count, 0) = 0 then 'contacts' end,
        case when coalesce(a.next_action, '') = '' then 'next_action' end,
        case when coalesce(ar.confidence, 0) < 50 then 'confidence' end
      ], null)::text[] as missing_fields
    from account_base a
    left join account_research ar on ar.account_id = a.id
    where coalesce(a.scoring_review_required, false) = true
       or coalesce(ar.confidence, 0) < 50
       or coalesce(a.website, '') = ''
       or coalesce(a.category, '') = ''
       or (a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '')
       or coalesce(a.contact_count, 0) = 0
       or coalesce(a.next_action, '') = ''
    order by coalesce(ar.confidence, 0) asc, a.priority_score desc nulls last, a.company_name asc
    limit 50
  ),
  opportunity_base as (
    select
      o.id,
      o.account_id,
      o.title,
      o.stage,
      coalesce(o.opportunity_value, 0) as opportunity_value,
      coalesce(o.probability, 0) as probability,
      o.expected_close_date,
      o.status,
      a.company_name as account_name,
      act.last_activity_at
    from public.aicrm_opportunities o
    join public.aicrm_accounts a
      on a.id = o.account_id
     and a.organization_id = p_organization_id
    left join (
      select opportunity_id, max(activity_date) as last_activity_at
      from public.aicrm_activities
      where organization_id = p_organization_id
      group by opportunity_id
    ) act on act.opportunity_id = o.id
    where o.organization_id = p_organization_id
  ),
  pipeline_stage_stats as (
    select
      coalesce(ps.name, o.stage) as stage,
      coalesce(ps.sort_order, 9999) as sort_order,
      count(*)::integer as opportunity_count,
      coalesce(sum(o.opportunity_value), 0)::numeric as pipeline_value,
      coalesce(sum(o.opportunity_value * coalesce(o.probability, 0) / 100), 0)::numeric as weighted_pipeline_value
    from opportunity_base o
    left join public.aicrm_pipeline_stages ps
      on ps.organization_id = p_organization_id
     and lower(trim(ps.name)) = lower(trim(o.stage))
    where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')
    group by coalesce(ps.name, o.stage), coalesce(ps.sort_order, 9999)
  ),
  stalled_opportunities as (
    select
      o.id as opportunity_id,
      o.title,
      o.account_name,
      o.stage,
      o.opportunity_value,
      o.probability,
      o.expected_close_date,
      o.status,
      o.last_activity_at
    from opportunity_base o
    where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')
      and (o.last_activity_at is null or o.last_activity_at < now() - interval '14 days')
    order by coalesce(o.last_activity_at, timestamptz '1970-01-01') asc, o.expected_close_date asc nulls last, o.opportunity_value desc
    limit 25
  ),
  task_base as (
    select
      t.id,
      t.title,
      t.description,
      t.due_date,
      coalesce(t.priority, 'normal') as priority,
      t.status,
      t.account_id,
      a.company_name as account_name,
      c.id as contact_id,
      coalesce(c.full_name, concat_ws(' ', c.first_name, c.last_name)) as contact_name,
      o.id as opportunity_id,
      o.title as opportunity_title,
      case
        when t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date::date < current_date then 'Overdue'
        when t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date::date = current_date then 'Due Today'
        when t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date::date <= current_date + 7 then 'Due This Week'
        when t.status in ('open', 'in_progress') and (
          lower(coalesce(t.title, '')) like '%follow%'
          or lower(coalesce(t.description, '')) like '%follow%'
        ) then 'Follow-Up Required'
        else 'Due This Week'
      end as bucket
    from public.aicrm_tasks t
    join public.aicrm_accounts a
      on a.id = t.account_id
     and a.organization_id = p_organization_id
    left join public.aicrm_contacts c on c.id = t.contact_id
    left join public.aicrm_opportunities o on o.id = t.opportunity_id
    where t.organization_id = p_organization_id
      and t.status in ('open', 'in_progress')
  ),
  ai_job_base as (
    select
      j.id,
      j.account_id,
      j.job_type,
      j.status,
      j.provider,
      j.mock_mode,
      j.started_at,
      j.completed_at,
      j.created_at,
      j.cost_estimate,
      j.error_message,
      a.company_name as account_name
    from public.aicrm_ai_enrichment_jobs j
    left join public.aicrm_accounts a
      on a.id = j.account_id
     and a.organization_id = p_organization_id
    where j.organization_id = p_organization_id
  ),
  outreach_message_base as (
    select
      m.id,
      m.account_id,
      m.contact_id,
      m.campaign_id,
      m.sequence_step_id,
      m.subject,
      m.status,
      m.approval_status,
      m.eligibility_status,
      m.eligibility_reason,
      m.created_at,
      m.sent_at,
      a.company_name as account_name,
      c.full_name as contact_name,
      campaign.name as campaign_name,
      step.step_number
    from public.aicrm_outreach_messages m
    left join public.aicrm_accounts a
      on a.id = m.account_id
     and a.organization_id = p_organization_id
    left join public.aicrm_contacts c on c.id = m.contact_id
    left join public.aicrm_outreach_campaigns campaign on campaign.id = m.campaign_id
    left join public.aicrm_sequence_steps step on step.id = m.sequence_step_id
    where m.organization_id = p_organization_id
  ),
  last_import as (
    select
      i.created_at,
      i.file_name,
      i.import_status,
      i.accepted_rows,
      i.processed_rows
    from public.aicrm_imports i
    where i.organization_id = p_organization_id
    order by i.created_at desc
    limit 1
  ),
  product_fit as (
    select
      product_name,
      count(*)::integer as match_count,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'account_id', fit.account_id,
            'company_name', fit.company_name,
            'province', fit.province,
            'priority_score', fit.priority_score,
            'product_fit', fit.channel_product_fit
          )
          order by fit.priority_score desc nulls last, fit.company_name asc
        )
        from (
          select
            a.id as account_id,
            a.company_name,
            a.province,
            coalesce(a.priority_score, 0) as priority_score,
            coalesce(a.channel_product_fit, '') as channel_product_fit
          from account_base a
          where lower(coalesce(a.channel_product_fit, '')) like '%' || lower(product_name) || '%'
          order by coalesce(a.priority_score, 0) desc, a.company_name asc
          limit 5
        ) fit
      ), '[]'::jsonb) as top_accounts
    from (values ('Fotile'), ('Dreame'), ('Mobila'), ('Nobilia')) as products(product_name)
    group by product_name
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_accounts', (select count(*) from account_base),
      'total_contacts', (select count(*) from public.aicrm_contacts c where c.organization_id = p_organization_id),
      'total_opportunities', (select count(*) from public.aicrm_opportunities o where o.organization_id = p_organization_id),
      'total_pipeline_value', (select coalesce(sum(o.opportunity_value), 0) from public.aicrm_opportunities o where o.organization_id = p_organization_id and coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')),
      'weighted_pipeline_value', (select coalesce(sum(coalesce(o.opportunity_value, 0) * coalesce(o.probability, 0) / 100), 0) from public.aicrm_opportunities o where o.organization_id = p_organization_id and coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')),
      'open_tasks', (select count(*) from public.aicrm_tasks t where t.organization_id = p_organization_id and t.status in ('open', 'in_progress')),
      'overdue_tasks', (select count(*) from public.aicrm_tasks t where t.organization_id = p_organization_id and t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date < now()),
      'active_campaigns', (select count(*) from public.aicrm_outreach_campaigns c where c.organization_id = p_organization_id and c.status = 'active')
    ),
    'top_targets', coalesce((select jsonb_agg(jsonb_build_object(
      'account_id', t.account_id,
      'company_name', t.company_name,
      'category', t.category,
      'province', t.province,
      'revenue_tier', t.revenue_tier,
      'priority_score', t.priority_score,
      'confidence', t.confidence,
      'product_fit', t.product_fit,
      'next_action', t.next_action,
      'open_opportunity_value', t.open_opportunity_value
    ) order by t.priority_score desc, t.company_name asc) from top_targets t), '[]'::jsonb),
    'top_ai_opportunities', coalesce((select jsonb_agg(jsonb_build_object(
      'account_id', t.account_id,
      'company_name', t.company_name,
      'priority_score', t.priority_score,
      'confidence', t.confidence,
      'recommended_product', t.recommended_product,
      'recommended_next_action', t.recommended_next_action
    ) order by t.priority_score desc, t.company_name asc) from top_ai_opportunities t), '[]'::jsonb),
    'review_queue', coalesce((select jsonb_agg(jsonb_build_object(
      'account_id', r.account_id,
      'company_name', r.company_name,
      'review_reason', r.review_reason,
      'missing_fields', to_jsonb(r.missing_fields),
      'owner_id', r.owner_id
    ) order by r.review_reason asc, r.company_name asc) from review_queue r), '[]'::jsonb),
    'pipeline', jsonb_build_object(
      'opportunities_by_stage', coalesce((select jsonb_agg(jsonb_build_object(
        'stage', s.stage,
        'opportunity_count', s.opportunity_count,
        'pipeline_value', s.pipeline_value,
        'weighted_pipeline_value', s.weighted_pipeline_value
      ) order by s.sort_order asc, s.stage asc) from pipeline_stage_stats s), '[]'::jsonb),
      'weighted_pipeline_value', (select coalesce(sum(s.weighted_pipeline_value), 0) from pipeline_stage_stats s),
      'average_opportunity_size', (select coalesce(round(avg(o.opportunity_value), 0), 0) from opportunity_base o where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')),
      'expected_close_this_month', (select count(*) from opportunity_base o where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled') and o.expected_close_date >= date_trunc('month', now()) and o.expected_close_date < date_trunc('month', now()) + interval '1 month'),
      'stalled_opportunities', coalesce((select jsonb_agg(jsonb_build_object(
        'opportunity_id', s.opportunity_id,
        'title', s.title,
        'account_name', s.account_name,
        'stage', s.stage,
        'opportunity_value', s.opportunity_value,
        'probability', s.probability,
        'expected_close_date', s.expected_close_date,
        'last_activity_at', s.last_activity_at,
        'status', s.status
      ) order by s.last_activity_at asc nulls first, s.opportunity_value desc) from stalled_opportunities s), '[]'::jsonb)
    ),
    'tasks', jsonb_build_object(
      'due_today', (select count(*) from task_base t where t.bucket = 'Due Today'),
      'overdue', (select count(*) from task_base t where t.bucket = 'Overdue'),
      'due_this_week', (select count(*) from task_base t where t.bucket = 'Due This Week'),
      'follow_up_required', (select count(*) from task_base t where t.bucket = 'Follow-Up Required'),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'task_id', t.id,
        'title', t.title,
        'account_id', t.account_id,
        'account_name', t.account_name,
        'contact_id', t.contact_id,
        'contact_name', t.contact_name,
        'opportunity_id', t.opportunity_id,
        'opportunity_title', t.opportunity_title,
        'due_date', t.due_date,
        'priority', t.priority,
        'status', t.status,
        'bucket', t.bucket
      ) order by coalesce(t.due_date, timestamptz 'infinity') asc, t.priority desc, t.title asc) from (select * from task_base order by coalesce(due_date, timestamptz 'infinity') asc, priority desc, title asc limit 25) t), '[]'::jsonb)
    ),
    'ai', jsonb_build_object(
      'total_enriched_accounts', (select count(*) from public.aicrm_ai_research r where r.organization_id = p_organization_id),
      'pending_jobs', (select count(*) from ai_job_base j where j.status = 'queued'),
      'running_jobs', (select count(*) from ai_job_base j where j.status = 'running'),
      'failed_jobs', (select count(*) from ai_job_base j where j.status = 'failed'),
      'mock_jobs', (select count(*) from ai_job_base j where coalesce(j.mock_mode, false) = true),
      'real_jobs', (select count(*) from ai_job_base j where coalesce(j.mock_mode, false) = false),
      'latest_activity', coalesce((select jsonb_agg(jsonb_build_object(
        'job_id', j.id,
        'account_id', j.account_id,
        'account_name', j.account_name,
        'job_type', j.job_type,
        'status', j.status,
        'provider', j.provider,
        'mock_mode', j.mock_mode,
        'created_at', j.created_at,
        'completed_at', j.completed_at,
        'error_message', j.error_message
      ) order by j.created_at desc) from (select * from ai_job_base order by created_at desc limit 8) j), '[]'::jsonb)
    ),
    'outreach', jsonb_build_object(
      'campaign_count', (select count(*) from public.aicrm_outreach_campaigns c where c.organization_id = p_organization_id),
      'active_enrollments', (select count(*) from public.aicrm_sequence_enrollments e where e.organization_id = p_organization_id and e.status = 'active'),
      'draft_messages', (select count(*) from outreach_message_base m where m.status in ('draft', 'pending_approval')),
      'pending_approvals', (select count(*) from outreach_message_base m where m.approval_status = 'pending'),
      'blocked_messages', (select count(*) from outreach_message_base m where coalesce(m.eligibility_status, '') = 'blocked'),
      'casl_review_required', (select count(*) from outreach_message_base m where coalesce(m.eligibility_status, '') = 'review_required'),
      'recent_activity', coalesce((select jsonb_agg(jsonb_build_object(
        'message_id', m.id,
        'account_id', m.account_id,
        'account_name', m.account_name,
        'contact_id', m.contact_id,
        'contact_name', m.contact_name,
        'campaign_id', m.campaign_id,
        'campaign_name', m.campaign_name,
        'sequence_step_number', m.step_number,
        'subject', m.subject,
        'status', m.status,
        'approval_status', m.approval_status,
        'eligibility_status', m.eligibility_status,
        'created_at', m.created_at,
        'sent_at', m.sent_at
      ) order by m.created_at desc) from (select * from outreach_message_base order by created_at desc limit 8) m), '[]'::jsonb)
    ),
    'data_quality', jsonb_build_object(
      'average_account_completeness', coalesce((select round(average_account_completeness::numeric, 1) from account_quality), 0),
      'average_contact_completeness', coalesce((select round(average_contact_completeness::numeric, 1) from contact_quality), 0),
      'accounts_missing_contacts', coalesce((select accounts_missing_contacts from account_quality), 0),
      'accounts_missing_revenue', coalesce((select accounts_missing_revenue from account_quality), 0),
      'accounts_missing_website', coalesce((select accounts_missing_website from account_quality), 0),
      'accounts_missing_product_fit', coalesce((select accounts_missing_product_fit from account_quality), 0)
    ),
    'product_fit', coalesce((select jsonb_agg(jsonb_build_object(
      'product_name', p.product_name,
      'match_count', p.match_count,
      'top_accounts', p.top_accounts
    ) order by p.product_name asc) from product_fit p), '[]'::jsonb),
    'system_health', jsonb_build_object(
      'last_import_at', (select li.created_at from last_import li),
      'last_import_name', (select li.file_name from last_import li),
      'total_imported_records', coalesce((select sum(i.accepted_rows)::integer from public.aicrm_imports i where i.organization_id = p_organization_id), 0),
      'total_audit_events', coalesce((select count(*) from public.aicrm_audit_log l where l.organization_id = p_organization_id), 0),
      'organizations_count', coalesce((select count(*) from public.organizations o), 0),
      'last_enrichment_at', coalesce((select max(coalesce(j.completed_at, j.started_at, j.created_at)) from public.aicrm_ai_enrichment_jobs j where j.organization_id = p_organization_id), null)
    )
  )
  into v_payload;

  return v_payload;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.aicrm_graph_touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  new.updated_at := now();
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.aicrm_market_brief(p_organization_id uuid, p_province text DEFAULT NULL::text, p_country text DEFAULT NULL::text) RETURNS jsonb LANGUAGE sql AS $fn$

  with
  base_watchlists as (
    select count(*)::integer as total_watchlists
    from public.aicrm_market_watchlists
    where organization_id = p_organization_id
      and active = true
  ),
  discovered as (
    select
      count(*) filter (where review_status = 'pending')::integer as awaiting_review,
      count(*) filter (where created_at >= now() - interval '30 days')::integer as new_companies,
      count(*) filter (where confidence >= 70)::integer as growth_opportunities
    from public.aicrm_market_discovery_queue
    where organization_id = p_organization_id
      and (p_province is null or coalesce(province, '') = p_province)
      and (p_country is null or coalesce(country, '') = p_country)
  ),
  refreshes as (
    select count(*) filter (where status = 'pending')::integer as pending_refresh
    from public.aicrm_market_refresh_queue
    where organization_id = p_organization_id
  ),
  events as (
    select count(*) filter (where occurred_at >= now() - interval '30 days')::integer as recent_events
    from public.aicrm_market_events
    where organization_id = p_organization_id
      and (p_province is null or exists (
        select 1
        from public.aicrm_accounts a
        where a.id = aicrm_market_events.account_id
          and a.organization_id = p_organization_id
          and coalesce(a.province, '') = p_province
      ))
  ),
  coverage as (
    select
      case
        when count(*) = 0 then 0
        else round(
          (
            count(*) filter (
              where exists (
                select 1
                from public.aicrm_market_events e
                where e.organization_id = p_organization_id
                  and e.account_id = a.id
              )
              or exists (
                select 1
                from public.aicrm_market_refresh_queue r
                where r.organization_id = p_organization_id
                  and r.account_id = a.id
              )
            )::numeric * 100.0
          ) / count(*)::numeric,
          1
        )
      end as coverage_percentage
    from public.aicrm_accounts a
    where a.organization_id = p_organization_id
      and coalesce(lower(a.status), '') <> 'archived'
  )
  select jsonb_build_object(
    'summary',
    concat(
      coalesce(p_province, p_country, 'Market'), ': ',
      coalesce((select new_companies from discovered), 0), ' new companies, ',
      coalesce((select awaiting_review from discovered), 0), ' awaiting review, ',
      coalesce((select pending_refresh from refreshes), 0), ' accounts queued for refresh.'
    ),
    'new_companies_discovered', coalesce((select new_companies from discovered), 0),
    'companies_awaiting_review', coalesce((select awaiting_review from discovered), 0),
    'accounts_needing_refresh', coalesce((select pending_refresh from refreshes), 0),
    'market_events', coalesce((select recent_events from events), 0),
    'growth_opportunities', coalesce((select growth_opportunities from discovered), 0),
    'coverage_percentage', coalesce((select coverage_percentage from coverage), 0),
    'total_watchlists', coalesce((select total_watchlists from base_watchlists), 0)
);

$fn$;

CREATE OR REPLACE FUNCTION public.aicrm_platform_config_snapshot(p_organization_id uuid) RETURNS jsonb LANGUAGE sql AS $fn$

  with
  settings as (
    select to_jsonb(s) as payload
    from public.aicrm_organization_settings s
    where s.organization_id = p_organization_id
    limit 1
  ),
  business_units as (
    select coalesce(jsonb_agg(to_jsonb(b) order by b.display_order, b.name), '[]'::jsonb) as payload
    from public.aicrm_business_units b
    where b.organization_id = p_organization_id
  ),
  brands as (
    select coalesce(jsonb_agg(to_jsonb(b) order by b.display_order, b.name), '[]'::jsonb) as payload
    from public.aicrm_brands b
    where b.organization_id = p_organization_id
  ),
  products as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'organization_id', p.organization_id,
      'business_unit_id', p.business_unit_id,
      'brand_id', p.brand_id,
      'name', p.name,
      'brand', p.brand,
      'category', p.category,
      'description', p.description,
      'active', p.active,
      'archived_at', p.archived_at,
      'created_at', p.created_at,
      'updated_at', p.updated_at
    ) order by p.name), '[]'::jsonb) as payload
    from public.aicrm_products p
    where p.organization_id = p_organization_id
  ),
  channels as (
    select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order, c.name), '[]'::jsonb) as payload
    from public.aicrm_channels c
    where c.organization_id = p_organization_id
  ),
  sales_motions as (
    select coalesce(jsonb_agg(to_jsonb(s) order by s.display_order, s.name), '[]'::jsonb) as payload
    from public.aicrm_sales_motions s
    where s.organization_id = p_organization_id
  ),
  campaign_categories as (
    select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order, c.name), '[]'::jsonb) as payload
    from public.aicrm_campaign_categories c
    where c.organization_id = p_organization_id
  ),
  campaign_types as (
    select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order, c.name), '[]'::jsonb) as payload
    from public.aicrm_campaign_types c
    where c.organization_id = p_organization_id
  ),
  campaign_sequences as (
    select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at, s.name), '[]'::jsonb) as payload
    from public.aicrm_campaign_sequences s
    where s.organization_id = p_organization_id
  ),
  kpis as (
    select coalesce(jsonb_agg(to_jsonb(k) order by k.display_order, k.name), '[]'::jsonb) as payload
    from public.aicrm_kpis k
    where k.organization_id = p_organization_id
  ),
  ai_profiles as (
    select coalesce(jsonb_agg(to_jsonb(a) order by a.is_default desc, a.name), '[]'::jsonb) as payload
    from public.aicrm_ai_profiles a
    where a.organization_id = p_organization_id
  ),
  pipeline_stages as (
    select coalesce(jsonb_agg(to_jsonb(p) order by p.sort_order, p.name), '[]'::jsonb) as payload
    from public.aicrm_pipeline_stages p
    where p.organization_id = p_organization_id
  )
  select jsonb_build_object(
    'organization_settings', coalesce((select payload from settings), '{}'::jsonb),
    'business_units', coalesce((select payload from business_units), '[]'::jsonb),
    'brands', coalesce((select payload from brands), '[]'::jsonb),
    'products', coalesce((select payload from products), '[]'::jsonb),
    'channels', coalesce((select payload from channels), '[]'::jsonb),
    'sales_motions', coalesce((select payload from sales_motions), '[]'::jsonb),
    'campaign_categories', coalesce((select payload from campaign_categories), '[]'::jsonb),
    'campaign_types', coalesce((select payload from campaign_types), '[]'::jsonb),
    'campaign_sequences', coalesce((select payload from campaign_sequences), '[]'::jsonb),
    'kpis', coalesce((select payload from kpis), '[]'::jsonb),
    'ai_profiles', coalesce((select payload from ai_profiles), '[]'::jsonb),
    'pipeline_stages', coalesce((select payload from pipeline_stages), '[]'::jsonb)
  );

$fn$;

CREATE OR REPLACE FUNCTION public.aicrm_product_fit_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE sql AS $fn$

  with ranked as (
    select
      p.name as product_name,
      f.account_id,
      a.company_name,
      a.province,
      coalesce(a.priority_score, 0) as priority_score,
      coalesce(f.fit_score, 0) as fit_score,
      f.fit_tier,
      coalesce(f.confidence, 0) as confidence,
      coalesce(f.recommended_sales_motion, '') as recommended_sales_motion,
      coalesce(f.recommended_campaign, '') as recommended_campaign,
      coalesce(f.fit_reason, '') as fit_reason,
      coalesce(ar.recommended_next_action, a.next_action, 'Review account') as next_action,
      row_number() over (partition by p.name order by coalesce(f.fit_score, 0) desc, coalesce(a.priority_score, 0) desc, a.company_name asc) as rn
    from public.aicrm_account_product_fit f
    join public.aicrm_products p
      on p.id = f.product_id
     and p.organization_id = p_organization_id
    join public.aicrm_accounts a
      on a.id = f.account_id
     and a.organization_id = p_organization_id
    left join public.aicrm_ai_research ar
      on ar.organization_id = p_organization_id
     and ar.account_id = a.id
    where f.organization_id = p_organization_id
      and p.active = true
  )
  select jsonb_build_object(
    'product_fit', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_name', s.product_name,
        'match_count', s.match_count,
        'top_accounts', s.top_accounts
      ) order by s.product_name asc)
      from (
        select
          product_name,
          count(*)::integer as match_count,
          coalesce((
            select jsonb_agg(jsonb_build_object(
              'account_id', x.account_id,
              'company_name', x.company_name,
              'province', x.province,
              'priority_score', x.priority_score,
              'fit_score', x.fit_score,
              'fit_tier', x.fit_tier,
              'confidence', x.confidence,
              'recommended_sales_motion', x.recommended_sales_motion,
              'recommended_campaign', x.recommended_campaign,
              'fit_reason', x.fit_reason,
              'next_action', x.next_action
            ) order by x.fit_score desc, x.priority_score desc, x.company_name asc)
            from ranked x
            where x.product_name = s.product_name and x.rn <= 10
          ), '[]'::jsonb) as top_accounts
        from ranked s
        group by product_name
      ) s
    ), '[]'::jsonb)
  );

$fn$;

CREATE OR REPLACE FUNCTION public.aicrm_product_fit_matrix(p_organization_id uuid, p_product_id uuid DEFAULT NULL::uuid, p_fit_tier text DEFAULT NULL::text, p_reviewed_status text DEFAULT NULL::text, p_confidence_min numeric DEFAULT NULL::numeric, p_province text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 250) RETURNS TABLE(total_count bigint, fit_id uuid, organization_id uuid, account_id uuid, account_name text, account_priority_score numeric, account_category text, account_segment text, account_type text, province text, product_id uuid, product_name text, product_brand text, product_category text, fit_score numeric, fit_tier text, fit_reason text, recommended_sales_motion text, recommended_campaign text, confidence numeric, source text, reviewed_status text, reviewed_by uuid, reviewed_at timestamp with time zone, last_calculated_at timestamp with time zone, research_summary text, product_fit_scores jsonb, recommended_products jsonb, recommended_next_action text, recommended_next_action_reasoning text, created_at timestamp with time zone, updated_at timestamp with time zone) LANGUAGE sql AS $fn$

  select
    count(*) over() as total_count,
    f.id as fit_id,
    f.organization_id,
    f.account_id,
    a.company_name as account_name,
    coalesce(a.priority_score, 0) as account_priority_score,
    a.category as account_category,
    a.segment as account_segment,
    a.account_type,
    a.province,
    p.id as product_id,
    p.name as product_name,
    p.brand as product_brand,
    p.category as product_category,
    f.fit_score,
    f.fit_tier,
    f.fit_reason,
    f.recommended_sales_motion,
    f.recommended_campaign,
    f.confidence,
    f.source,
    f.reviewed_status,
    f.reviewed_by,
    f.reviewed_at,
    f.last_calculated_at,
    ar.research_summary,
    ar.product_fit_scores,
    to_jsonb(ar.recommended_products) as recommended_products,
    ar.recommended_next_action,
    ar.recommended_next_action_reasoning,
    f.created_at,
    f.updated_at
  from public.aicrm_account_product_fit f
  join public.aicrm_accounts a
    on a.id = f.account_id
   and a.organization_id = p_organization_id
  join public.aicrm_products p
    on p.id = f.product_id
   and p.organization_id = p_organization_id
  left join public.aicrm_ai_research ar
    on ar.organization_id = p_organization_id
   and ar.account_id = a.id
  where f.organization_id = p_organization_id
    and (p_product_id is null or f.product_id = p_product_id)
    and (p_fit_tier is null or f.fit_tier = p_fit_tier)
    and (p_reviewed_status is null or f.reviewed_status = p_reviewed_status)
    and (p_confidence_min is null or f.confidence >= p_confidence_min)
    and (p_province is null or coalesce(a.province, '') = p_province)
    and (p_category is null or coalesce(a.category, '') = p_category)
    and (
      p_search is null
      or p_search = ''
      or a.company_name ilike '%' || p_search || '%'
      or p.name ilike '%' || p_search || '%'
      or coalesce(f.fit_reason, '') ilike '%' || p_search || '%'
    )
  order by coalesce(f.fit_score, 0) desc, coalesce(a.priority_score, 0) desc, a.company_name asc, p.name asc
  limit greatest(1, least(coalesce(p_limit, 250), 500));

$fn$;

CREATE OR REPLACE FUNCTION public.aiq_command_centre_snapshot(p_organization_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $fn$

select jsonb_build_object(
 'generated_at',now(),'organization_id',p_organization_id,
 'products',jsonb_build_object(
   'total',(select count(*) from public.aiq_products where organization_id=p_organization_id),
   'approved',(select count(*) from public.aiq_products where organization_id=p_organization_id and approval_status='approved'),
   'public',(select count(*) from public.aiq_products where organization_id=p_organization_id and public_visible),
   'documents',(select count(*) from public.pim_product_documents d join public.aiq_products p on p.id=d.product_id where p.organization_id=p_organization_id),
   'graph_nodes',(select count(*) from public.aicrm_graph_nodes where organization_id=p_organization_id),
   'graph_edges',(select count(*) from public.aicrm_graph_edges where organization_id=p_organization_id)),
 'sales',jsonb_build_object(
   'deals',(select count(*) from public.crm_deals where organization_id=p_organization_id),
   'open_deals',(select count(*) from public.crm_deals where organization_id=p_organization_id and closed_at is null and coalesce(is_archived,false)=false),
   'pipeline_value',(select coalesce(sum(value_amount),0) from public.crm_deals where organization_id=p_organization_id and closed_at is null and coalesce(is_archived,false)=false),
   'packages',(select count(*) from public.speciq_packages where organization_id=p_organization_id),
   'comparisons',(select count(*) from public.ai_product_comparisons where organization_id=p_organization_id),
   'recordings',(select count(*) from public.sales_recordings where organization_id=p_organization_id)),
 'operations',jsonb_build_object(
   'traffic_events',(select count(*) from public.iq_traffic_events where organization_id=p_organization_id),
   'customer_interactions',(select count(*) from public.iq_customer_interactions where organization_id=p_organization_id)),
 'ai',jsonb_build_object(
   'requests',(select count(*) from public.ai_requests where organization_id=p_organization_id),
   'conversations',(select count(*) from public.ai_conversations where organization_id=p_organization_id),
   'roleplays',(select count(*) from public.ai_roleplay_sessions where organization_id=p_organization_id),
   'coaching_reviews',(select count(*) from public.ai_coaching_reviews where organization_id=p_organization_id))
); 
$fn$;

CREATE OR REPLACE FUNCTION public.aiq_graph_neighbours(p_organization_id uuid, p_entity_id uuid, p_depth integer DEFAULT 1, p_limit integer DEFAULT 50) RETURNS TABLE(root_node_id uuid, node_id uuid, node_type text, entity_id uuid, label text, relationship_path text[], depth integer, metadata jsonb) LANGUAGE sql STABLE AS $fn$

with recursive walk(root_node_id,node_id,node_type,entity_id,label,relationship_path,depth,metadata,visited) as (
  select n.id,n.id,n.node_type,n.entity_id,n.label,array[]::text[],0,n.metadata,array[n.id]::uuid[]
  from public.aicrm_graph_nodes n
  where n.organization_id=p_organization_id and n.entity_id=p_entity_id and n.active
  union all
  select w.root_node_id,nextn.id,nextn.node_type,nextn.entity_id,nextn.label,w.relationship_path||e.relationship_type,w.depth+1,nextn.metadata,w.visited||nextn.id
  from walk w
  join public.aicrm_graph_edges e on e.organization_id=p_organization_id and (e.from_node_id=w.node_id or e.to_node_id=w.node_id)
  join public.aicrm_graph_nodes nextn on nextn.id=case when e.from_node_id=w.node_id then e.to_node_id else e.from_node_id end
  where w.depth<greatest(1,least(p_depth,3)) and nextn.active and not nextn.id=any(w.visited)
)
select root_node_id,node_id,node_type,entity_id,label,relationship_path,depth,metadata from walk
order by depth,label limit greatest(1,least(p_limit,200));

$fn$;

CREATE OR REPLACE FUNCTION public.aiq_record_version() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  version_table text := tg_argv[0];
  fk_column text := tg_argv[1];
begin
  execute format(
    'insert into public.%I (organization_id, %I, version_number, snapshot) values ($1.organization_id, $1.id, $1.version_number, to_jsonb($1))',
    version_table, fk_column
  ) using new;
  return null;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.aiq_sync_knowledge_graph(p_organization_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$

begin
  insert into public.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select p.organization_id,'Product',p.id,'aiq_products',concat_ws(' ',p.brand_name,p.model),p.short_description,
    jsonb_strip_nulls(jsonb_build_object('brand_name',p.brand_name,'manufacturer_name',p.manufacturer_name,'category',p.category,'series',p.series,'product_family',p.product_family,'status',p.status,'market',p.market,'msrp',p.msrp,'replacement_model',p.replacement_model)),coalesce(p.public_visible,true)
  from public.aiq_products p where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into public.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select b.organization_id,'Brand',b.id,'brand_catalog',b.brand_name,b.brand_story,
    jsonb_strip_nulls(jsonb_build_object('brand_tier',b.brand_tier,'parent_company',b.parent_company,'country',b.country,'website',b.website,'headquarters',b.headquarters,'tagline',b.brand_tagline,'categories',b.product_categories)),coalesce(b.is_active,true)
  from public.brand_catalog b where p_organization_id is null or b.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into public.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select p.organization_id,'Document',d.id,'pim_product_documents',d.title,d.description,
    jsonb_strip_nulls(jsonb_build_object('doc_type',d.doc_type,'language',d.language,'locale',d.locale,'version',d.version,'file_url',d.file_url,'verification_status',d.verification_status,'manufacturer_verified',d.manufacturer_verified)),coalesce(d.is_current,true)
  from public.pim_product_documents d join public.aiq_products p on p.id=d.product_id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into public.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select p.organization_id,'Product',a.id,'pim_product_accessories',a.accessory_name,a.accessory_description,
    jsonb_strip_nulls(jsonb_build_object('is_accessory',true,'model',a.accessory_model,'relationship_type',a.relationship_type,'category',a.category,'msrp',a.msrp,'required',a.is_required,'included',a.is_included)),true
  from public.pim_product_accessories a join public.aiq_products p on p.id=a.product_id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into public.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select pn.organization_id,pn.id,bn.id,'BELONGS_TO',100,100,'aiq_sync',jsonb_build_object('semantic_type','made_by_brand')
  from public.aicrm_graph_nodes pn
  join public.aiq_products p on pn.entity_type='aiq_products' and pn.entity_id=p.id
  join public.aicrm_graph_nodes bn on bn.organization_id=pn.organization_id and bn.entity_type='brand_catalog' and bn.entity_id=p.brand_id
  where pn.node_type='Product' and (p_organization_id is null or pn.organization_id=p_organization_id)
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  insert into public.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select pn.organization_id,pn.id,dn.id,'CONNECTED_TO',90,case when d.manufacturer_verified then 100 else 80 end,'aiq_sync',jsonb_build_object('semantic_type','has_document','doc_type',d.doc_type)
  from public.pim_product_documents d
  join public.aiq_products p on p.id=d.product_id
  join public.aicrm_graph_nodes pn on pn.organization_id=p.organization_id and pn.entity_type='aiq_products' and pn.entity_id=p.id
  join public.aicrm_graph_nodes dn on dn.organization_id=p.organization_id and dn.entity_type='pim_product_documents' and dn.entity_id=d.id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  insert into public.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select pn.organization_id,pn.id,an.id,'CONNECTED_TO',case when coalesce(a.is_required,false) then 100 else 80 end,90,'aiq_sync',
    jsonb_build_object('semantic_type',case when coalesce(a.is_required,false) then 'requires_accessory' when coalesce(a.is_included,false) then 'includes_accessory' else 'compatible_accessory' end,'relationship_type',a.relationship_type)
  from public.pim_product_accessories a
  join public.aiq_products p on p.id=a.product_id
  join public.aicrm_graph_nodes pn on pn.organization_id=p.organization_id and pn.entity_type='aiq_products' and pn.entity_id=p.id
  join public.aicrm_graph_nodes an on an.organization_id=p.organization_id and an.entity_type='pim_product_accessories' and an.entity_id=a.id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  insert into public.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select p.organization_id,pn.id,rn.id,'CONNECTED_TO',100,95,'aiq_sync',jsonb_build_object('semantic_type','replaced_by','replacement_model',p.replacement_model)
  from public.aiq_products p
  join public.aiq_products r on r.organization_id=p.organization_id and upper(r.model)=upper(p.replacement_model)
  join public.aicrm_graph_nodes pn on pn.organization_id=p.organization_id and pn.entity_type='aiq_products' and pn.entity_id=p.id
  join public.aicrm_graph_nodes rn on rn.organization_id=r.organization_id and rn.entity_type='aiq_products' and rn.entity_id=r.id
  where nullif(trim(p.replacement_model),'') is not null and (p_organization_id is null or p.organization_id=p_organization_id)
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  return jsonb_build_object('nodes',(select count(*) from public.aicrm_graph_nodes where p_organization_id is null or organization_id=p_organization_id),'edges',(select count(*) from public.aicrm_graph_edges where p_organization_id is null or organization_id=p_organization_id),'synced_at',now());
end;

$fn$;

CREATE OR REPLACE FUNCTION public.aiq_touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.version_number := coalesce(old.version_number, 0) + 1;
  end if;
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.cascade_budget(p_budget_plan_id uuid, p_metric_type text DEFAULT 'revenue'::text, p_period_type text DEFAULT 'annual'::text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  v_plan record;
  v_corporate_target numeric;
  v_loc record;
  v_total_historical numeric;
  v_cascaded integer := 0;
begin
  select * into v_plan from public.budget_plans where id = p_budget_plan_id;
  if not found then return jsonb_build_object('error','plan_not_found'); end if;

  -- Get the corporate-level target for this metric
  select target_value into v_corporate_target from public.budget_nodes
  where budget_plan_id = p_budget_plan_id and location_id is null and user_id is null
    and metric_type = p_metric_type and period_type = p_period_type
  limit 1;

  if v_corporate_target is null or v_corporate_target = 0 then
    v_corporate_target := v_plan.total_revenue_target;
  end if;

  -- Get historical totals for active child locations to compute %
  select coalesce(sum(actual_value), 0) into v_total_historical
  from public.metric_snapshots ms
  join public.org_locations ol on ol.id = ms.location_id
  where ms.organization_id = v_plan.organization_id
    and ms.metric_key = p_metric_type
    and ms.period_type = 'annual'
    and ol.is_active = true;

  -- Cascade to each active location
  for v_loc in
    select id, name from public.org_locations
    where organization_id = v_plan.organization_id and is_active = true
    order by location_type, name
  loop
    declare
      v_loc_historical numeric := 0;
      v_loc_pct numeric := 0;
      v_loc_target numeric := 0;
    begin
      select coalesce(sum(actual_value), 0) into v_loc_historical
      from public.metric_snapshots
      where location_id = v_loc.id and metric_key = p_metric_type and period_type = 'annual';

      if v_total_historical > 0 then
        v_loc_pct := v_loc_historical / v_total_historical * 100;
      else
        -- Equal distribution if no history
        v_loc_pct := 100.0 / greatest((select count(*) from public.org_locations where organization_id = v_plan.organization_id and is_active = true), 1);
      end if;

      v_loc_target := v_corporate_target * v_loc_pct / 100;

      insert into public.budget_nodes (organization_id, budget_plan_id, location_id, period_type, period_key, metric_type, target_value, pct_of_parent)
      values (v_plan.organization_id, p_budget_plan_id, v_loc.id, p_period_type, v_plan.fiscal_year::text, p_metric_type, v_loc_target, v_loc_pct)
      on conflict do nothing;

      v_cascaded := v_cascaded + 1;
    end;
  end loop;

  return jsonb_build_object('ok', true, 'cascaded', v_cascaded, 'corporate_target', v_corporate_target);
end;

$fn$;

CREATE OR REPLACE FUNCTION public.check_token_budget(p_organization_id uuid, p_tokens_needed integer) RETURNS TABLE(has_budget boolean, tokens_remaining bigint, org_tier text) LANGUAGE sql SECURITY DEFINER AS $fn$

  select
    (l.monthly_limit - l.tokens_used_this_month) >= p_tokens_needed,
    (l.monthly_limit - l.tokens_used_this_month),
    o.tier
  from public.ai_token_limits l
  join public.organizations o on o.id = l.organization_id
  where l.organization_id = p_organization_id;

$fn$;

CREATE OR REPLACE FUNCTION public.complete_embedding_worker_run(p_run_id uuid, p_status text, p_rows_embedded integer, p_rows_failed integer, p_model text, p_error_message text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$

  update public.embedding_worker_runs
     set status = p_status, rows_embedded = p_rows_embedded, rows_failed = p_rows_failed,
         model = p_model, error_message = p_error_message, metadata = p_metadata, finished_at = now()
   where id = p_run_id;

$fn$;

CREATE OR REPLACE FUNCTION public.consent_active(p_subject uuid, p_scope text) RETURNS boolean LANGUAGE sql STABLE AS $fn$

  SELECT EXISTS (
    SELECT 1 FROM consent_ledger
    WHERE subject_id = p_subject AND scope = p_scope
      AND revoked_at IS NULL
      AND (expires_at IS NULL OR expires_at > now()));

$fn$;

CREATE OR REPLACE FUNCTION public.current_user_roles() RETURNS text[] LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  select coalesce(
    array_agg(distinct om.role order by om.role),
    array[]::text[]
  )
  from public.organization_members om
  where om.user_id = auth.uid()
    and om.status = 'active';

$fn$;

CREATE OR REPLACE FUNCTION public.decision_calculate_priority(p_financial_impact_cad numeric, p_customer_impact_score numeric, p_urgency_score numeric, p_confidence numeric, p_evidence_quality numeric, p_effort_score numeric) RETURNS numeric LANGUAGE sql IMMUTABLE AS $fn$

  select round(least(100,greatest(0,
    (least(coalesce(p_financial_impact_cad,0),250000)/250000.0*30) +
    (coalesce(p_customer_impact_score,0)*0.20) +
    (coalesce(p_urgency_score,0)*0.20) +
    (coalesce(p_confidence,0.5)*100*0.15) +
    (coalesce(p_evidence_quality,0.5)*100*0.10) +
    ((100-coalesce(p_effort_score,50))*0.05)
  )),2);

$fn$;

CREATE OR REPLACE FUNCTION public.decision_create_case(p_organization_id uuid, p_module text, p_title text, p_summary text, p_recommendation text, p_consequence_if_ignored text DEFAULT NULL::text, p_decision_type text DEFAULT 'operational'::text, p_severity text DEFAULT 'medium'::text, p_financial_impact_cad numeric DEFAULT NULL::numeric, p_customer_impact_score numeric DEFAULT 0, p_urgency_score numeric DEFAULT 50, p_confidence numeric DEFAULT 0.5, p_evidence_quality numeric DEFAULT 0.5, p_effort_score numeric DEFAULT 50, p_source_system text DEFAULT 'manual'::text, p_source_record_id text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS uuid LANGUAGE plpgsql AS $fn$

declare v_id uuid;
begin
  insert into public.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,source_system,source_record_id,metadata,created_by,updated_by)
  values(p_organization_id,p_module,p_title,p_summary,p_recommendation,p_consequence_if_ignored,p_decision_type,p_severity,p_financial_impact_cad,p_customer_impact_score,p_urgency_score,p_confidence,p_evidence_quality,p_effort_score,p_source_system,p_source_record_id,coalesce(p_metadata,'{}'::jsonb),(select auth.uid()),(select auth.uid()))
  returning id into v_id;
  insert into public.decision_actions(organization_id,decision_case_id,action_text,created_by)
  values(p_organization_id,v_id,p_recommendation,(select auth.uid()));
  return v_id;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.decision_generate_operational_forecasts(p_organization_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare
  v_revenue numeric:=0; v_avg_order numeric:=0; v_conv numeric:=0; v_conv_target numeric:=0; v_walkins numeric:=0;
  v_training numeric:=0; v_training_target numeric:=100; v_pipeline numeric:=0; v_weighted numeric:=0; v_stale_value numeric:=0;
  v_case uuid; v_created int:=0; v_prediction int:=0; v_gap numeric; v_impact numeric; v_prob numeric;
  v_critical int:=0;
begin
  if not public.is_org_member(p_organization_id) then raise exception 'Not authorized'; end if;

  select coalesce(max(actual_value) filter(where metric_key='revenue'),0),
         coalesce(max(actual_value) filter(where metric_key='avg_order'),0),
         coalesce(max(actual_value) filter(where metric_key='floor_conversion'),0),
         coalesce(max(target_value) filter(where metric_key='floor_conversion'),0),
         coalesce(max(actual_value) filter(where metric_key='walk_ins'),0),
         coalesce(max(actual_value) filter(where metric_key='training_completion'),0),
         coalesce(max(target_value) filter(where metric_key='training_completion'),100)
  into v_revenue,v_avg_order,v_conv,v_conv_target,v_walkins,v_training,v_training_target
  from public.metric_snapshots m
  where m.organization_id=p_organization_id and m.user_id is null and m.location_id is null
    and m.period_key=(select max(period_key) from public.metric_snapshots where organization_id=p_organization_id);

  select coalesce(sum(opportunity_value) filter(where coalesce(status,'open') not in ('closed','won','lost')),0),
         coalesce(sum(opportunity_value*least(greatest(coalesce(probability,0),0),100)/100) filter(where coalesce(status,'open') not in ('closed','won','lost')),0),
         coalesce(sum(opportunity_value) filter(where updated_at<now()-interval '14 days' and coalesce(status,'open') not in ('closed','won','lost')),0)
  into v_pipeline,v_weighted,v_stale_value from public.aicrm_opportunities where organization_id=p_organization_id;

  if v_pipeline>0 then
    select id into v_case from public.decision_cases where organization_id=p_organization_id and source_system='prediction_engine' and source_record_id='crm_pipeline_30d' limit 1;
    v_impact:=round(v_weighted,2); v_prob:=case when v_pipeline>0 then least(.9,greatest(.35,v_weighted/v_pipeline)) else .35 end;
    if v_case is null then
      insert into public.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,status,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,priority_score,source_system,source_record_id,metadata,created_by)
      values(p_organization_id,'crm','30-day CRM revenue forecast',format('Open pipeline is C$%s with C$%s probability-weighted.',to_char(v_pipeline,'FM999,999,990'),to_char(v_weighted,'FM999,999,990')),'Focus follow-up on stale, high-value opportunities before adding more pipeline.',format('Approximately C$%s of stale pipeline is exposed to further decay.',to_char(v_stale_value*.15,'FM999,999,990')),'forecast','open',case when v_stale_value>v_pipeline*.25 then 'high' else 'medium' end,v_impact,75,80,v_prob,.85,35,public.decision_calculate_priority(v_impact,75,80,v_prob,.85,35),'prediction_engine','crm_pipeline_30d',jsonb_build_object('pipeline',v_pipeline,'weighted_pipeline',v_weighted,'stale_pipeline',v_stale_value),auth.uid()) returning id into v_case;
      v_created:=v_created+1;
    else
      update public.decision_cases set summary=format('Open pipeline is C$%s with C$%s probability-weighted.',to_char(v_pipeline,'FM999,999,990'),to_char(v_weighted,'FM999,999,990')), financial_impact_cad=v_impact, confidence=v_prob, consequence_if_ignored=format('Approximately C$%s of stale pipeline is exposed to further decay.',to_char(v_stale_value*.15,'FM999,999,990')), priority_score=public.decision_calculate_priority(v_impact,75,80,v_prob,.85,35), metadata=jsonb_build_object('pipeline',v_pipeline,'weighted_pipeline',v_weighted,'stale_pipeline',v_stale_value),updated_at=now(),updated_by=auth.uid() where id=v_case;
    end if;
    delete from public.decision_predictions where decision_case_id=v_case and prediction_type='revenue';
    insert into public.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'revenue','30_days',v_pipeline,v_weighted,v_weighted-v_pipeline,'CAD',v_prob,v_weighted*.75,v_weighted*1.2,v_stale_value*.15,v_weighted,jsonb_build_object('method','probability-weighted opportunity value','stale_decay_rate',.15),'ApplianceIQ rules forecast','1.0',now()+interval '7 days');
    v_prediction:=v_prediction+1;
  end if;

  v_gap:=greatest(v_conv_target-v_conv,0);
  if v_gap>0 and v_walkins>0 and v_avg_order>0 then
    v_impact:=round(v_walkins*(v_gap/100)*v_avg_order,2);
    select id into v_case from public.decision_cases where organization_id=p_organization_id and source_system='prediction_engine' and source_record_id='floor_conversion_gap' limit 1;
    if v_case is null then
      insert into public.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,status,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,priority_score,source_system,source_record_id,metadata,created_by)
      values(p_organization_id,'retail_floor','Close the floor conversion gap',format('Conversion is %s%% against a %s%% target across %s walk-ins.',v_conv,v_conv_target,v_walkins),'Review greeting coverage, missed ups, and rep conversion by shift.',format('At the current traffic and average order, the monthly opportunity gap is approximately C$%s.',to_char(v_impact,'FM999,999,990')),'opportunity','open','high',v_impact,90,85,.78,.9,45,public.decision_calculate_priority(v_impact,90,85,.78,.9,45),'prediction_engine','floor_conversion_gap',jsonb_build_object('conversion',v_conv,'target',v_conv_target,'walk_ins',v_walkins,'avg_order',v_avg_order),auth.uid()) returning id into v_case;
      v_created:=v_created+1;
    else update public.decision_cases set financial_impact_cad=v_impact,summary=format('Conversion is %s%% against a %s%% target across %s walk-ins.',v_conv,v_conv_target,v_walkins),consequence_if_ignored=format('At the current traffic and average order, the monthly opportunity gap is approximately C$%s.',to_char(v_impact,'FM999,999,990')),priority_score=public.decision_calculate_priority(v_impact,90,85,.78,.9,45),metadata=jsonb_build_object('conversion',v_conv,'target',v_conv_target,'walk_ins',v_walkins,'avg_order',v_avg_order),updated_at=now(),updated_by=auth.uid() where id=v_case; end if;
    delete from public.decision_predictions where decision_case_id=v_case and prediction_type='conversion_revenue';
    insert into public.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'conversion_revenue','30_days',v_revenue,v_revenue+v_impact,v_impact,'CAD',.78,v_revenue+v_impact*.5,v_revenue+v_impact,v_impact,v_impact,jsonb_build_object('formula','walk-ins × conversion gap × average order','conversion_gap_points',v_gap),'ApplianceIQ opportunity model','1.0',now()+interval '14 days');
    v_prediction:=v_prediction+1;
  end if;

  v_gap:=greatest(v_training_target-v_training,0);
  if v_gap>=10 and v_revenue>0 then
    v_impact:=round(v_revenue*(v_gap/100)*.03,2);
    select id into v_case from public.decision_cases where organization_id=p_organization_id and source_system='prediction_engine' and source_record_id='training_completion_gap' limit 1;
    if v_case is null then
      insert into public.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,status,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,priority_score,source_system,source_record_id,metadata,created_by)
      values(p_organization_id,'academy','Training completion is below target',format('Training completion is %s%%, %s points below target.',v_training,v_gap),'Assign incomplete modules to active reps and measure conversion after completion.','The revenue estimate is deliberately conservative and should be recalibrated after measured outcomes.','opportunity','open','medium',v_impact,65,60,.58,.65,40,public.decision_calculate_priority(v_impact,65,60,.58,.65,40),'prediction_engine','training_completion_gap',jsonb_build_object('completion',v_training,'target',v_training_target,'revenue',v_revenue),auth.uid()) returning id into v_case;
      v_created:=v_created+1;
    else update public.decision_cases set financial_impact_cad=v_impact,summary=format('Training completion is %s%%, %s points below target.',v_training,v_gap),priority_score=public.decision_calculate_priority(v_impact,65,60,.58,.65,40),metadata=jsonb_build_object('completion',v_training,'target',v_training_target,'revenue',v_revenue),updated_at=now(),updated_by=auth.uid() where id=v_case; end if;
    delete from public.decision_predictions where decision_case_id=v_case and prediction_type='training_revenue';
    insert into public.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'training_revenue','60_days',v_revenue,v_revenue+v_impact,v_impact,'CAD',.58,v_revenue,v_revenue+v_impact*1.5,v_impact,v_impact,jsonb_build_object('conservative_lift_rate',.03,'completion_gap_points',v_gap),'ApplianceIQ training impact proxy','1.0',now()+interval '30 days');
    v_prediction:=v_prediction+1;
  end if;

  select count(*) into v_critical from public.field_findings f join public.field_clients c on c.id=f.client_id where c.organization_id=p_organization_id and lower(coalesce(f.severity,''))='critical' and lower(coalesce(f.status,'open')) not in ('resolved','closed');
  if v_critical>0 then
    update public.decision_cases set consequence_if_ignored=format('%s critical field finding(s) remain exposed. No CAD estimate is shown until sales attribution exists.',v_critical),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('critical_findings',v_critical,'financial_estimate_status','insufficient_attribution'),updated_at=now() where organization_id=p_organization_id and source_system='executive_intelligence' and module='field' and status not in ('completed','rejected');
  end if;

  return jsonb_build_object('organization_id',p_organization_id,'cases_created',v_created,'predictions_generated',v_prediction,'inputs',jsonb_build_object('revenue',v_revenue,'avg_order',v_avg_order,'conversion',v_conv,'conversion_target',v_conv_target,'walk_ins',v_walkins,'training_completion',v_training,'open_pipeline',v_pipeline,'weighted_pipeline',v_weighted,'stale_pipeline',v_stale_value,'critical_findings',v_critical));
end 
$fn$;

CREATE OR REPLACE FUNCTION public.decision_get_feed(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE sql AS $fn$

select coalesce(jsonb_agg(to_jsonb(x) order by x.priority_score desc,x.created_at desc),'[]'::jsonb)
from (
 select c.id,c.module,c.title,c.summary,c.recommendation,c.consequence_if_ignored,c.decision_type,c.status,c.severity,c.financial_impact_cad,c.priority_score,c.confidence,c.evidence_quality,c.owner_id,c.due_at,c.created_at,
   (select count(*) from public.decision_evidence e where e.decision_case_id=c.id) as evidence_count,
   (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'text',a.action_text,'status',a.status,'owner_id',a.owner_id,'due_at',a.due_at) order by a.created_at),'[]'::jsonb) from public.decision_actions a where a.decision_case_id=c.id) as actions,
   (select coalesce(jsonb_agg(jsonb_build_object('type',p.prediction_type,'predicted_value',p.predicted_value,'delta',p.predicted_delta,'unit',p.unit,'probability',p.probability,'horizon',p.horizon) order by p.generated_at desc),'[]'::jsonb) from public.decision_predictions p where p.decision_case_id=c.id) as predictions
 from public.decision_cases c
 where c.organization_id=p_organization_id and c.status not in ('completed','dismissed','expired')
 order by c.priority_score desc,c.created_at desc
 limit greatest(1,least(coalesce(p_limit,25),100))
) x;

$fn$;

CREATE OR REPLACE FUNCTION public.decision_get_prediction_dashboard(p_organization_id uuid) RETURNS jsonb LANGUAGE sql AS $fn$

 select case when public.is_org_member(p_organization_id) then jsonb_build_object(
  'summary',jsonb_build_object('active_predictions',count(*) filter(where p.status='active'),'total_predicted_impact_cad',coalesce(sum(p.financial_impact_cad) filter(where p.status='active'),0),'total_cost_of_inaction_cad',coalesce(sum(p.cost_of_inaction_cad) filter(where p.status='active'),0),'measured_predictions',count(*) filter(where p.status='measured')),
  'predictions',coalesce(jsonb_agg(jsonb_build_object('id',p.id,'case_id',c.id,'title',c.title,'module',c.module,'priority_score',c.priority_score,'prediction_type',p.prediction_type,'horizon',p.horizon,'baseline_value',p.baseline_value,'predicted_value',p.predicted_value,'predicted_delta',p.predicted_delta,'unit',p.unit,'probability',p.probability,'lower_bound',p.lower_bound,'upper_bound',p.upper_bound,'financial_impact_cad',p.financial_impact_cad,'cost_of_inaction_cad',p.cost_of_inaction_cad,'assumptions',p.assumptions,'model_name',p.model_name,'model_version',p.model_version,'status',p.status,'actual_value',p.actual_value,'absolute_error',p.absolute_error,'percent_error',p.percent_error,'generated_at',p.generated_at) order by c.priority_score desc),'[]'::jsonb)
 ) else jsonb_build_object('error','Not authorized') end
 from public.decision_predictions p join public.decision_cases c on c.id=p.decision_case_id where p.organization_id=p_organization_id;

$fn$;

CREATE OR REPLACE FUNCTION public.decision_record_prediction_outcome(p_prediction_id uuid, p_actual_value numeric, p_actual_financial_impact_cad numeric DEFAULT NULL::numeric) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare v public.decision_predictions%rowtype; v_abs numeric; v_pct numeric;
begin
 select * into v from public.decision_predictions where id=p_prediction_id;
 if v.id is null or not public.is_org_member(v.organization_id) then raise exception 'Not authorized'; end if;
 v_abs:=abs(coalesce(p_actual_value,0)-coalesce(v.predicted_value,0));
 v_pct:=case when nullif(abs(v.predicted_value),0) is null then null else v_abs/abs(v.predicted_value)*100 end;
 update public.decision_predictions set actual_value=p_actual_value,actual_financial_impact_cad=p_actual_financial_impact_cad,measured_at=now(),absolute_error=v_abs,percent_error=v_pct,status='measured' where id=p_prediction_id;
 insert into public.decision_model_performance(organization_id,module,prediction_type,sample_count,mean_absolute_error,mean_absolute_percentage_error,confidence_adjustment,last_measured_at)
 select v.organization_id,c.module,v.prediction_type,1,v_abs,v_pct,case when coalesce(v_pct,100)<=15 then .03 when v_pct>=50 then -.05 else 0 end,now() from public.decision_cases c where c.id=v.decision_case_id
 on conflict(organization_id,module,prediction_type) do update set sample_count=decision_model_performance.sample_count+1,mean_absolute_error=((coalesce(decision_model_performance.mean_absolute_error,0)*decision_model_performance.sample_count)+excluded.mean_absolute_error)/(decision_model_performance.sample_count+1),mean_absolute_percentage_error=((coalesce(decision_model_performance.mean_absolute_percentage_error,0)*decision_model_performance.sample_count)+coalesce(excluded.mean_absolute_percentage_error,0))/(decision_model_performance.sample_count+1),confidence_adjustment=greatest(-.25,least(.15,decision_model_performance.confidence_adjustment+excluded.confidence_adjustment)),last_measured_at=now(),updated_at=now();
 return jsonb_build_object('prediction_id',p_prediction_id,'absolute_error',v_abs,'percent_error',v_pct,'status','measured');
end 
$fn$;

CREATE OR REPLACE FUNCTION public.decision_sync_executive_insights(p_organization_id uuid) RETURNS integer LANGUAGE plpgsql AS $fn$

declare r record; v_count integer:=0; v_id uuid; v_conf numeric;
begin
 for r in select * from public.executive_intelligence_insights where organization_id=p_organization_id and status in ('open','active')
 loop
   if not exists(select 1 from public.decision_cases where organization_id=p_organization_id and source_system='executive_intelligence' and source_record_id=r.id::text and status not in ('completed','dismissed','expired')) then
     v_conf:=least(0.95,greatest(0.45,coalesce(r.priority_score,50)/100.0));
     v_id:=public.decision_create_case(p_organization_id,coalesce(r.domain,'executive'),r.title,r.summary,coalesce(r.recommended_action,'Review and assign an owner.'),null,case when r.insight_type='risk' then 'risk' else 'strategic' end,coalesce(r.severity,'medium'),null,case when r.severity='critical' then 90 when r.severity='high' then 75 else 50 end,coalesce(r.priority_score,50),v_conf,v_conf,40,'executive_intelligence',r.id::text,jsonb_build_object('insight_type',r.insight_type,'evidence',r.evidence,'source_systems',r.source_systems));
     insert into public.decision_evidence(organization_id,decision_case_id,evidence_type,source_system,source_table,source_record_id,label,description,weight,confidence,evidence)
     values(p_organization_id,v_id,'executive_insight','executive_intelligence','executive_intelligence_insights',r.id::text,r.title,r.summary,1,v_conf,coalesce(r.evidence,'{}'::jsonb));
     v_count:=v_count+1;
   end if;
 end loop;
 return v_count;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.decision_touch_case() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  new.priority_score := public.decision_calculate_priority(new.financial_impact_cad,new.customer_impact_score,new.urgency_score,new.confidence,new.evidence_quality,new.effort_score);
  new.updated_at := now();
  if new.status in ('completed','dismissed','rejected','expired') and new.resolved_at is null then new.resolved_at:=now(); end if;
  return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome_success boolean DEFAULT NULL::boolean, p_outcome_value numeric DEFAULT NULL::numeric, p_outcome_unit text DEFAULT NULL::text, p_outcome_notes text DEFAULT NULL::text) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare v_action public.decision_actions; v_case_status text;
begin
 update public.decision_actions set
   status=p_status,
   owner_id=coalesce(p_owner_id,owner_id), due_at=coalesce(p_due_at,due_at),
   accepted_at=case when p_status='accepted' and accepted_at is null then now() else accepted_at end,
   started_at=case when p_status='in_progress' and started_at is null then now() else started_at end,
   completed_at=case when p_status in ('completed','measured') and completed_at is null then now() else completed_at end,
   outcome_success=coalesce(p_outcome_success,outcome_success), outcome_value=coalesce(p_outcome_value,outcome_value), outcome_unit=coalesce(p_outcome_unit,outcome_unit), outcome_notes=coalesce(p_outcome_notes,outcome_notes), updated_at=now()
 where id=p_action_id returning * into v_action;
 if v_action.id is null then raise exception 'Decision action not found or unavailable'; end if;
 v_case_status:=case p_status when 'accepted' then 'accepted' when 'assigned' then 'accepted' when 'in_progress' then 'in_progress' when 'completed' then 'completed' when 'measured' then 'completed' when 'rejected' then 'rejected' when 'cancelled' then 'dismissed' else null end;
 if v_case_status is not null then update public.decision_cases set status=v_case_status,owner_id=coalesce(p_owner_id,owner_id),due_at=coalesce(p_due_at,due_at),updated_by=(select auth.uid()) where id=v_action.decision_case_id; end if;
 return to_jsonb(v_action);
end 
$fn$;

CREATE OR REPLACE FUNCTION public.deduct_tokens(p_organization_id uuid, p_tokens_used integer) RETURNS TABLE(success boolean, tokens_remaining bigint) LANGUAGE sql SECURITY DEFINER AS $fn$

  update public.ai_token_limits
  set tokens_used_this_month = tokens_used_this_month + p_tokens_used
  where organization_id = p_organization_id
    and tokens_used_this_month + p_tokens_used <= monthly_limit
  returning true as success, (monthly_limit - tokens_used_this_month - p_tokens_used) as tokens_remaining;

$fn$;

CREATE OR REPLACE FUNCTION public.executive_answer_question(p_organization_id uuid, p_question text) RETURNS jsonb LANGUAGE plpgsql AS $fn$

declare
  v_q text := lower(trim(coalesce(p_question,'')));
  v_intent text;
  v_answer jsonb;
  v_evidence jsonb;
  v_confidence numeric;
  v_query_id uuid;
  v_snapshot executive_intelligence_snapshots%rowtype;
begin
  if auth.uid() is not null and not exists (
    select 1 from organization_members m where m.organization_id=p_organization_id and m.user_id=auth.uid() and coalesce(m.status,'active')='active'
  ) then raise exception 'Not authorized for organization'; end if;

  select * into v_snapshot from executive_intelligence_snapshots where organization_id=p_organization_id order by generated_at desc limit 1;
  if v_snapshot.id is null then
    perform executive_refresh_command_centre(p_organization_id);
    select * into v_snapshot from executive_intelligence_snapshots where organization_id=p_organization_id order by generated_at desc limit 1;
  end if;

  if v_q ~ '(risk|problem|wrong|attention|danger)' then
    v_intent:='top_risks';
    select jsonb_build_object('headline','Highest-priority executive risks','items',coalesce(jsonb_agg(jsonb_build_object('title',title,'summary',summary,'severity',severity,'priority_score',priority_score,'recommended_action',recommended_action,'evidence',evidence) order by priority_score desc),'[]'::jsonb))
    into v_answer from (select * from executive_intelligence_insights where organization_id=p_organization_id and insight_type='risk' and status in ('open','acknowledged','in_progress') order by priority_score desc limit 5) x;
  elsif v_q ~ '(opportunit|growth|best|working|strong)' then
    v_intent:='top_opportunities';
    select jsonb_build_object('headline','Highest-value opportunities and strengths','items',coalesce(jsonb_agg(jsonb_build_object('title',title,'summary',summary,'priority_score',priority_score,'recommended_action',recommended_action,'evidence',evidence) order by priority_score desc),'[]'::jsonb))
    into v_answer from (select * from executive_intelligence_insights where organization_id=p_organization_id and insight_type in ('opportunity','performance') and status in ('open','acknowledged','in_progress') order by priority_score desc limit 5) x;
  elsif v_q ~ '(sales|conversion|pipeline|deal|revenue)' then
    v_intent:='sales_performance';
    v_answer:=jsonb_build_object('headline','Sales and pipeline performance','crm',v_snapshot.metrics->'crm','retail_floor',v_snapshot.metrics->'retail_floor');
  elsif v_q ~ '(field|store|display|visit|manufacturer)' then
    v_intent:='field_performance';
    v_answer:=jsonb_build_object('headline','Field and store execution','field',v_snapshot.metrics->'field','related_insights',coalesce((select jsonb_agg(jsonb_build_object('title',title,'summary',summary,'severity',severity,'recommended_action',recommended_action) order by priority_score desc) from executive_intelligence_insights where snapshot_id=v_snapshot.id and domain='field'),'[]'::jsonb));
  elsif v_q ~ '(training|coach|academy|role.?play|skill)' then
    v_intent:='training_performance';
    v_answer:=jsonb_build_object('headline','Training and coaching performance','training',v_snapshot.metrics->'training','learning',v_snapshot.metrics->'learning');
  elsif v_q ~ '(next|action|do first|priority)' then
    v_intent:='priority_actions';
    select jsonb_build_object('headline','Recommended executive action order','items',coalesce(jsonb_agg(jsonb_build_object('title',title,'summary',summary,'domain',domain,'severity',severity,'priority_score',priority_score,'recommended_action',recommended_action) order by priority_score desc),'[]'::jsonb))
    into v_answer from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') order by priority_score desc limit 7) x;
  else
    v_intent:='executive_summary';
    v_answer:=jsonb_build_object('headline','Executive operating summary','overall_health_score',v_snapshot.overall_health_score,'health_status',v_snapshot.health_status,'coverage_status',v_snapshot.coverage_status,'metrics',v_snapshot.metrics,'top_insights',coalesce((select jsonb_agg(jsonb_build_object('title',title,'summary',summary,'type',insight_type,'severity',severity,'recommended_action',recommended_action) order by priority_score desc) from (select * from executive_intelligence_insights where snapshot_id=v_snapshot.id order by priority_score desc limit 5) z),'[]'::jsonb));
  end if;

  v_evidence:=jsonb_build_array(jsonb_build_object('snapshot_id',v_snapshot.id,'generated_at',v_snapshot.generated_at,'coverage_status',v_snapshot.coverage_status,'data_confidence',v_snapshot.data_confidence));
  v_confidence:=v_snapshot.data_confidence;
  insert into executive_intelligence_queries(organization_id,asked_by,question,intent,answer,evidence,confidence)
  values(p_organization_id,auth.uid(),p_question,v_intent,v_answer,v_evidence,v_confidence)
  returning id into v_query_id;
  return jsonb_build_object('query_id',v_query_id,'intent',v_intent,'answer',v_answer,'evidence',v_evidence,'confidence',v_confidence);
end;

$fn$;

CREATE OR REPLACE FUNCTION public.executive_finalize_snapshot_confidence(p_snapshot_id uuid) RETURNS void LANGUAGE plpgsql AS $fn$

declare v executive_intelligence_snapshots%rowtype; v_domains int:=0; v_conf numeric; v_cov text; begin
 select * into v from executive_intelligence_snapshots where id=p_snapshot_id;
 if coalesce((v.metrics#>>'{crm,deals_total}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 if coalesce((v.metrics#>>'{retail_floor,interactions}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 if coalesce((v.metrics#>>'{field,open_actions}')::numeric,0)+coalesce((v.metrics#>>'{field,resolved_actions}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 if (v.metrics#>>'{training,average_knowledge_score}') is not null then v_domains:=v_domains+1; end if;
 if coalesce((v.metrics#>>'{data_volume,outcomes}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 v_conf:=round(v_domains/5.0,2);
 v_cov:=case when v_conf<0.4 then 'insufficient' when v_conf<0.7 then 'partial' when v_conf<0.9 then 'good' else 'strong' end;
 update executive_intelligence_snapshots set data_confidence=v_conf,coverage_status=v_cov,
   health_status=case when v_cov='insufficient' then 'unknown' else health_status end,
   overall_health_score=case when v_cov='insufficient' then 50 else overall_health_score end
 where id=p_snapshot_id;
 update executive_intelligence_insights set summary='Insufficient cross-system operating evidence is available for a reliable health score.', recommended_action='Connect or populate CRM, retail-floor, field, training, and outcome data before interpreting health.'
 where snapshot_id=p_snapshot_id and title='Current operating health score' and v_cov='insufficient';
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.executive_get_command_centre(p_organization_id uuid) RETURNS jsonb LANGUAGE sql AS $fn$

with latest as (
  select * from executive_intelligence_snapshots
  where organization_id=p_organization_id
  order by generated_at desc limit 1
)
select jsonb_build_object(
  'snapshot',coalesce((select to_jsonb(l) from latest l),'{}'::jsonb),
  'top_risks',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type='risk' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'top_opportunities',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type='opportunity' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'priority_actions',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type in ('action','performance') order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'generated_at',now()
);

$fn$;

CREATE OR REPLACE FUNCTION public.executive_refresh_command_centre(p_organization_id uuid) RETURNS uuid LANGUAGE plpgsql AS $fn$

declare
  v_snapshot_id uuid;
  v_user uuid := auth.uid();
  v_metrics jsonb;
  v_health numeric;
  v_status text;
  v_deals_total numeric := 0;
  v_deals_won numeric := 0;
  v_deals_lost numeric := 0;
  v_pipeline_value numeric := 0;
  v_stale_deals numeric := 0;
  v_interactions numeric := 0;
  v_sales numeric := 0;
  v_left_unserved numeric := 0;
  v_field_critical numeric := 0;
  v_field_open_actions numeric := 0;
  v_field_resolved_actions numeric := 0;
  v_avg_store_score numeric;
  v_avg_training_score numeric;
  v_open_recommendations numeric := 0;
  v_low_signals numeric := 0;
  v_strong_signals numeric := 0;
  v_conversion numeric := 0;
  v_served_score numeric := 100;
  v_field_score numeric := 50;
  v_training_score numeric := 50;
  v_resolution_score numeric := 50;
begin
  if v_user is not null and not exists (
    select 1 from organization_members m
    where m.organization_id=p_organization_id and m.user_id=v_user and coalesce(m.status,'active')='active'
  ) then
    raise exception 'Not authorized for organization';
  end if;

  select count(*),
         count(*) filter (where lower(stage) in ('closed won','won','sold','completed','purchased')),
         count(*) filter (where lower(stage) in ('closed lost','lost','cancelled','rejected','expired')),
         coalesce(sum(value_amount) filter (where lower(stage) not in ('closed won','won','sold','completed','purchased','closed lost','lost','cancelled','rejected','expired')),0),
         count(*) filter (where lower(stage) not in ('closed won','won','sold','completed','purchased','closed lost','lost','cancelled','rejected','expired') and coalesce(days_inactive,0)>=30)
  into v_deals_total,v_deals_won,v_deals_lost,v_pipeline_value,v_stale_deals
  from crm_deals where organization_id=p_organization_id;

  select count(*), count(*) filter (where lower(coalesce(outcome,'')) in ('sale','sold','won','purchased','closed_won'))
  into v_interactions,v_sales
  from iq_customer_interactions where organization_id=p_organization_id;

  select count(*) into v_left_unserved
  from iq_customer_waiting_queue where organization_id=p_organization_id and lower(status::text)='left_unserved';

  select count(*) filter (where lower(coalesce(f.severity,''))='critical' and lower(coalesce(f.status,'new')) not in ('resolved','closed'))
  into v_field_critical
  from field_findings f join field_clients c on c.id=f.client_id where c.organization_id=p_organization_id;

  select count(*) filter (where lower(coalesce(a.status,'open')) not in ('resolved','closed','completed','verified')),
         count(*) filter (where lower(coalesce(a.status,'')) in ('resolved','closed','completed','verified'))
  into v_field_open_actions,v_field_resolved_actions
  from field_actions a join field_clients c on c.id=a.client_id where c.organization_id=p_organization_id;

  select avg(case when s.overall_score>10 then s.overall_score else s.overall_score*10 end)
  into v_avg_store_score
  from field_store_scores s join field_clients c on c.id=s.client_id where c.organization_id=p_organization_id;

  select avg(case when t.knowledge_score>10 then t.knowledge_score else t.knowledge_score*10 end)
  into v_avg_training_score
  from field_training_sessions t join field_clients c on c.id=t.client_id where c.organization_id=p_organization_id;

  select count(*) filter (where status in ('generated','presented')) into v_open_recommendations
  from intelligence_recommendations where organization_id=p_organization_id;

  select count(*) filter (where observation_count>=2 and bayesian_score<0.45),
         count(*) filter (where observation_count>=2 and bayesian_score>=0.70)
  into v_low_signals,v_strong_signals
  from intelligence_learning_signals where organization_id=p_organization_id;

  v_conversion := case when v_interactions>0 then round((v_sales/v_interactions)*100,2)
                       when (v_deals_won+v_deals_lost)>0 then round((v_deals_won/(v_deals_won+v_deals_lost))*100,2)
                       else 0 end;
  v_served_score := case when (v_interactions+v_left_unserved)>0 then greatest(0,100-(v_left_unserved/(v_interactions+v_left_unserved))*100) else 100 end;
  v_field_score := coalesce(v_avg_store_score,50);
  v_training_score := coalesce(v_avg_training_score,50);
  v_resolution_score := case when (v_field_open_actions+v_field_resolved_actions)>0 then (v_field_resolved_actions/(v_field_open_actions+v_field_resolved_actions))*100 else 50 end;

  v_health := round(greatest(0,least(100,
      (v_conversion*0.30) +
      (v_served_score*0.15) +
      (v_field_score*0.20) +
      (v_training_score*0.15) +
      (v_resolution_score*0.20) -
      least(15,v_field_critical*3) -
      least(10,v_stale_deals)
  )),2);
  v_status := case when v_health<35 then 'critical' when v_health<50 then 'at_risk' when v_health<65 then 'watch' when v_health<80 then 'healthy' else 'strong' end;

  v_metrics := jsonb_build_object(
    'crm',jsonb_build_object('deals_total',v_deals_total,'deals_won',v_deals_won,'deals_lost',v_deals_lost,'pipeline_value_cad',v_pipeline_value,'stale_deals',v_stale_deals,'closed_conversion_pct',case when (v_deals_won+v_deals_lost)>0 then round((v_deals_won/(v_deals_won+v_deals_lost))*100,2) else null end),
    'retail_floor',jsonb_build_object('interactions',v_interactions,'sales',v_sales,'conversion_pct',v_conversion,'left_unserved',v_left_unserved,'served_score',round(v_served_score,2)),
    'field',jsonb_build_object('critical_open_findings',v_field_critical,'open_actions',v_field_open_actions,'resolved_actions',v_field_resolved_actions,'resolution_pct',round(v_resolution_score,2),'average_store_score',round(v_avg_store_score,2)),
    'training',jsonb_build_object('average_knowledge_score',round(v_avg_training_score,2)),
    'learning',jsonb_build_object('open_recommendations',v_open_recommendations,'low_performing_signals',v_low_signals,'strong_signals',v_strong_signals),
    'data_volume',jsonb_build_object('entities',(select count(*) from intelligence_entities where organization_id=p_organization_id),'events',(select count(*) from intelligence_events where organization_id=p_organization_id),'outcomes',(select count(*) from intelligence_outcomes where organization_id=p_organization_id),'signals',(select count(*) from intelligence_learning_signals where organization_id=p_organization_id))
  );

  insert into executive_intelligence_snapshots(organization_id,snapshot_type,period_start,period_end,overall_health_score,health_status,metrics,evidence_summary,generated_by)
  values(p_organization_id,'current',current_date-30,current_date,v_health,v_status,v_metrics,
         jsonb_build_object('calculation','weighted operational score','weights',jsonb_build_object('conversion',0.30,'served_customers',0.15,'field_execution',0.20,'training',0.15,'action_resolution',0.20),'penalties',jsonb_build_object('critical_findings','3 points each, max 15','stale_deals','1 point each, max 10')),v_user)
  returning id into v_snapshot_id;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'risk','field','critical',100,
         'Critical field findings remain unresolved',
         format('%s critical field finding(s) are still open.',v_field_critical),
         'Assign owners, set deadlines, and verify resolution evidence.',
         jsonb_build_object('critical_open_findings',v_field_critical),array['field_reports','intelligence_core']
  where v_field_critical>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'risk','retail_floor',case when v_left_unserved>=3 then 'high' else 'medium' end,85,
         'Customers left without service',
         format('%s customer(s) were recorded as left unserved.',v_left_unserved),
         'Review staffing, queue response times, and missed-assignment causes.',
         jsonb_build_object('left_unserved',v_left_unserved),array['iq_up_system','crm']
  where v_left_unserved>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'risk','crm',case when v_stale_deals>=10 then 'high' else 'medium' end,80,
         'Pipeline opportunities need attention',
         format('%s open deal(s) have been inactive for at least 30 days.',v_stale_deals),
         'Rank stale deals by value and assign a specific next action and date.',
         jsonb_build_object('stale_deals',v_stale_deals,'pipeline_value_cad',v_pipeline_value),array['crm','intelligence_core']
  where v_stale_deals>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'opportunity','learning','info',70,
         'Proven strategies are emerging',
         format('%s learning signal(s) have a Bayesian score of at least 0.70.',v_strong_signals),
         'Promote the strongest strategies into playbooks and recommended defaults.',
         jsonb_build_object('strong_signals',v_strong_signals),array['intelligence_core','academy','crm','field_reports']
  where v_strong_signals>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'action','learning',case when v_low_signals>=5 then 'high' else 'medium' end,75,
         'Low-performing recommendations require review',
         format('%s learning signal(s) are underperforming after multiple observations.',v_low_signals),
         'Retire, revise, or narrow the context of weak recommendations.',
         jsonb_build_object('low_performing_signals',v_low_signals),array['intelligence_core']
  where v_low_signals>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'performance','operations','info',60,
         'Current operating health score',
         format('The current combined operating health score is %s/100 (%s).',v_health,v_status),
         'Work the highest-priority open insight first, then refresh the snapshot.',
         jsonb_build_object('health_score',v_health,'health_status',v_status),array['intelligence_core','crm','iq_up_system','field_reports','academy'];

  return v_snapshot_id;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.executive_snapshot_confidence_trigger() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  perform executive_finalize_snapshot_confidence(new.id);
  return new;
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.fn_auto_create_brand_course() RETURNS trigger LANGUAGE plpgsql AS $fn$
 DECLARE v_slug TEXT; v_ms SMALLINT; v_cid INTEGER; BEGIN IF NEW.is_active = false THEN RETURN NEW; END IF; IF EXISTS (SELECT 1 FROM iq_courses WHERE brand_id = NEW.id AND pillar = 'brand_iq') THEN RETURN NEW; END IF; v_slug := 'brand-' || lower(regexp_replace(regexp_replace(NEW.brand_name, '[^a-zA-Z0-9 ]', '', 'g'), '\s+', '-', 'g')); SELECT COALESCE(MAX(sort_order), 0) + 1 INTO v_ms FROM iq_courses WHERE pillar = 'brand_iq'; INSERT INTO iq_courses (pillar, course_key, name, subtitle, icon, brand_id, zone_level, category, sort_order) VALUES ('brand_iq', v_slug, NEW.brand_name, COALESCE(NEW.brand_tier,'mid'), '🏷️', NEW.id, 2, COALESCE(NEW.brand_tier,'mid'), v_ms) RETURNING id INTO v_cid; INSERT INTO iq_badges (badge_type, badge_key, name, description, icon, color, pillar, brand_id, course_id, requirements, sort_order) VALUES ('brand_cert', 'brand-cert-' || v_slug, NEW.brand_name || ' Certified', 'Brand quiz 80 percent', '🏅', '#CD7F32', 'brand_iq', NEW.id, v_cid, jsonb_build_object('quiz_pass', 80, 'course_complete', v_slug), (v_cid + 200)::smallint) ON CONFLICT DO NOTHING; RETURN NEW; END; 
$fn$;

CREATE OR REPLACE FUNCTION public.fn_brand_reactivated() RETURNS trigger LANGUAGE plpgsql AS $fn$

BEGIN
  IF OLD.is_active = false AND NEW.is_active = true THEN
    PERFORM fn_auto_create_brand_course();
  END IF;
  RETURN NEW;
END;

$fn$;

CREATE OR REPLACE FUNCTION public.fn_ccr_notification() RETURNS trigger LANGUAGE plpgsql AS $fn$

BEGIN
  INSERT INTO iq_notifications (notification_type, title, body, icon, ccr_id, target_audience)
  VALUES (
    'new_competitive_entry',
    '🔬 New Competitive Intel: ' || COALESCE(NEW.category, 'Cross-Reference'),
    'New competitive knowledge added for ' || COALESCE(NEW.category, 'a product category') || ' (' || COALESCE(NEW.tier, '') || ').',
    '⚔️',
    NEW.id,
    'all_reps'
  );
  RETURN NEW;
END;

$fn$;

CREATE OR REPLACE FUNCTION public.fn_new_deck_notification() RETURNS trigger LANGUAGE plpgsql AS $fn$

DECLARE
  v_course_name TEXT;
BEGIN
  SELECT name INTO v_course_name FROM iq_courses WHERE id = NEW.course_id;
  
  INSERT INTO iq_notifications (notification_type, title, body, icon, course_id, target_audience)
  VALUES (
    'new_deck',
    '📚 New Lesson: ' || NEW.title,
    'A new deck has been added to ' || COALESCE(v_course_name, 'a course') || '.',
    '🃏',
    NEW.course_id,
    'all_reps'
  );
  RETURN NEW;
END;

$fn$;

CREATE OR REPLACE FUNCTION public.fn_pim_notification() RETURNS trigger LANGUAGE plpgsql AS $fn$

BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO iq_notifications (notification_type, title, body, icon, product_id, brand_id, target_audience)
    VALUES (
      'new_product',
      '🆕 New Product: ' || COALESCE(NEW.short_description, NEW.model),
      'A new ' || COALESCE(NEW.category, 'product') || ' has been added to the PIM.',
      '📦',
      NEW.id,
      NEW.brand_id,
      'all_reps'
    );
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.is_discontinued IS DISTINCT FROM NEW.is_discontinued AND NEW.is_discontinued = true THEN
    INSERT INTO iq_notifications (notification_type, title, body, icon, product_id, brand_id, target_audience)
    VALUES (
      'product_discontinued',
      '⚠️ Discontinued: ' || COALESCE(NEW.short_description, NEW.model),
      COALESCE(NEW.short_description, NEW.model) || ' has been marked discontinued.',
      '🚫',
      NEW.id,
      NEW.brand_id,
      'all_reps'
    );
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.is_clearance IS DISTINCT FROM NEW.is_clearance AND NEW.is_clearance = true THEN
    INSERT INTO iq_notifications (notification_type, title, body, icon, product_id, brand_id, target_audience)
    VALUES (
      'product_clearance',
      '🏷️ Clearance: ' || COALESCE(NEW.short_description, NEW.model),
      COALESCE(NEW.short_description, NEW.model) || ' is now on clearance.',
      '💰',
      NEW.id,
      NEW.brand_id,
      'all_reps'
    );
  END IF;

  RETURN NEW;
END;

$fn$;

CREATE OR REPLACE FUNCTION public.fn_sync_pim_to_training() RETURNS trigger LANGUAGE plpgsql AS $fn$

DECLARE
  v_brand_course_id INTEGER;
  v_content JSONB;
  v_title TEXT;
BEGIN
  SELECT id INTO v_brand_course_id FROM iq_courses WHERE pillar = 'brand_iq' AND brand_id = NEW.brand_id LIMIT 1;

  v_title := COALESCE(NEW.brand_name, '') || ' ' || COALESCE(NEW.model, '');

  v_content := jsonb_build_object(
    'model', NEW.model,
    'brand_name', NEW.brand_name,
    'product_line', NEW.product_line,
    'series', NEW.series,
    'category', NEW.category,
    'short_description', NEW.short_description,
    'msrp', NEW.msrp,
    'sale_price', NEW.sale_price,
    'lowest_price', NEW.lowest_price,
    'lowest_price_source', NEW.lowest_price_source,
    'map_price', NEW.map_price,
    'specs_json', NEW.specs_json,
    'available_colors', NEW.available_colors,
    'capacity_cu_ft', NEW.capacity_cu_ft,
    'voltage', NEW.voltage,
    'installation_type', NEW.installation_type,
    'finish', NEW.finish,
    'color', NEW.color,
    'energy_star', NEW.energy_star,
    'width_inches', NEW.width_inches,
    'height_inches', NEW.height_inches,
    'depth_inches', NEW.depth_inches,
    'features_html', NEW.features_html
  );

  INSERT INTO iq_product_cards (product_id, brand_id, course_id, card_type, title, content,
    is_active, is_new_launch, is_discontinued, is_clearance, is_end_of_life, pim_synced_at, updated_at)
  VALUES (NEW.id, NEW.brand_id, v_brand_course_id, 'product_spotlight', v_title, v_content,
    true, CASE WHEN TG_OP = 'INSERT' THEN true ELSE false END,
    COALESCE(NEW.is_discontinued, false), COALESCE(NEW.is_clearance, false),
    COALESCE(NEW.is_end_of_life, false), now(), now())
  ON CONFLICT (product_id) DO UPDATE SET
    brand_id = EXCLUDED.brand_id, course_id = EXCLUDED.course_id,
    title = EXCLUDED.title, content = EXCLUDED.content,
    is_discontinued = EXCLUDED.is_discontinued, is_clearance = EXCLUDED.is_clearance,
    is_end_of_life = EXCLUDED.is_end_of_life, pim_synced_at = now(), updated_at = now();

  RETURN NEW;
END;

$fn$;

CREATE OR REPLACE FUNCTION public.foundation_audit() RETURNS trigger LANGUAGE plpgsql AS $fn$

  DECLARE
    rec  JSONB := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  BEGIN
    INSERT INTO foundation_audit_log(entity_table, entity_id, action, actor, delta)
    VALUES (TG_TABLE_NAME,
            (rec ->> 'id')::uuid,
            TG_OP,
            COALESCE((rec ->> 'updated_by')::uuid, (rec ->> 'created_by')::uuid),
            rec);
    RETURN COALESCE(NEW, OLD);
  END;

$fn$;

CREATE OR REPLACE FUNCTION public.foundation_fact_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$

BEGIN
  IF NEW.status = 'verified' AND (NEW.intelligence_type = 'AI_INFERENCE' OR NEW.source = 'UNKNOWN') THEN
    RAISE EXCEPTION 'Constitution: AI_INFERENCE / UNKNOWN-source facts cannot be verified (fact %)', NEW.id;
  END IF;
  IF NEW.status = 'verified' AND NEW.verified_by IS NULL THEN
    RAISE EXCEPTION 'Constitution: verified facts require verified_by (fact %)', NEW.id;
  END IF;
  RETURN NEW;
END 
$fn$;

CREATE OR REPLACE FUNCTION public.generate_daily_coaching_brief(p_organization_id uuid, p_user_id uuid) RETURNS TABLE(primary_kpi text, previous_score numeric, target_score numeric, insight text) LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  v_yesterday date := current_date - interval '1 day';
  v_lowest_kpi_id uuid;
  v_lowest_score numeric;
  v_target_score numeric;
  v_insight text;
begin
  -- Get yesterday's coaching reviews for this user
  with yesterday_scores as (
    select
      k.id,
      k.kpi_name,
      k.target_score,
      avg(case
        when ar.coaching_data->'kpi_scores' ? k.kpi_name
        then (ar.coaching_data->'kpi_scores'->>k.kpi_name)::numeric
        else null
      end) as avg_score
    from public.ai_coaching_reviews ar
    join public.org_kpis k on k.organization_id = p_organization_id
    where ar.organization_id = p_organization_id
      and ar.user_id = p_user_id
      and date(ar.created_at) = v_yesterday
      and k.active = true
    group by k.id, k.kpi_name, k.target_score
  )
  select
    s.id, s.avg_score
    into v_lowest_kpi_id, v_lowest_score
  from yesterday_scores s
  where s.avg_score is not null
  order by s.avg_score asc
  limit 1;

  if v_lowest_kpi_id is null then
    -- No coaching yesterday, pick the first active KPI
    select id, target_score into v_lowest_kpi_id, v_target_score
    from public.org_kpis
    where organization_id = p_organization_id and active = true
    limit 1;
    v_lowest_score := null;
    v_insight := 'Get started with your first coaching session today!';
  else
    select target_score into v_target_score from public.org_kpis where id = v_lowest_kpi_id;
    v_insight := 'Your ' || (select kpi_name from org_kpis where id = v_lowest_kpi_id) || ' score was ' || v_lowest_score::text || '/10 yesterday. Focus on improving this today.';
  end if;

  -- Upsert into daily_coaching_focus
  insert into public.daily_coaching_focus (
    organization_id, user_id, focus_date, primary_kpi_id, primary_kpi_name, previous_score, target_score, insight
  )
  select p_organization_id, p_user_id, current_date, v_lowest_kpi_id, (select kpi_name from org_kpis where id = v_lowest_kpi_id), v_lowest_score, v_target_score, v_insight
  on conflict (organization_id, user_id, focus_date) do update set
    primary_kpi_id = v_lowest_kpi_id,
    primary_kpi_name = (select kpi_name from org_kpis where id = v_lowest_kpi_id),
    previous_score = v_lowest_score,
    insight = v_insight;

  return query
  select
    (select kpi_name from org_kpis where id = v_lowest_kpi_id) as primary_kpi,
    v_lowest_score,
    v_target_score,
    v_insight;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.generate_speciq_quote_number() RETURNS trigger LANGUAGE plpgsql AS $fn$

BEGIN
  IF NEW.quote_number IS NULL THEN
    NEW.quote_number := 'IQ-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('speciq_quote_seq')::text, 6, '0');
  END IF;
  RETURN NEW;
END;

$fn$;

CREATE OR REPLACE FUNCTION public.get_org_member_profiles(p_org_id uuid) RETURNS TABLE(user_id uuid, display_name text, email text) LANGUAGE sql SECURITY DEFINER AS $fn$

  select u.id as user_id,
    coalesce(u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)) as display_name,
    u.email
  from auth.users u
  join public.organization_members om on om.user_id = u.id
  where om.organization_id = p_org_id and om.status = 'active';

$fn$;

CREATE OR REPLACE FUNCTION public.handle_aicrm_organization_insert() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$

begin
  perform public.provision_aicrm_defaults_for_organization(new.id);
  perform public.provision_aicrm_market_defaults_for_organization(new.id);
  perform public.provision_aicrm_territory_defaults_for_organization(new.id);
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.has_any_role(role_names text[]) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  select coalesce(
    exists (
      select 1
      from unnest(coalesce(role_names, array[]::text[])) as r(role_name)
      where r.role_name = any(public.current_user_roles())
    ),
    false
  );

$fn$;

CREATE OR REPLACE FUNCTION public.has_permission(permission_name text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE AS $fn$

begin
  if permission_name is null or auth.uid() is null then
    return false;
  end if;

  if public.is_super_admin() then
    return true;
  end if;

  if exists (
    select 1
    from public.organization_members om
    where om.user_id = auth.uid()
      and om.status = 'active'
      and om.role = 'owner'
  ) then
    return true;
  end if;

  return permission_name in (
    'organization.view',
    'crm.view',
    'ats.view',
    'reporting.view',
    'billing.read',
    'ai.command.use',
    'ai.audit.view',
    'files.view',
    'communications.view',
    'notifications.view'
  );
end;

$fn$;

CREATE OR REPLACE FUNCTION public.has_role(role_name text) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  select coalesce(role_name = any(public.current_user_roles()), false);

$fn$;

CREATE OR REPLACE FUNCTION public.init_dashboard_metrics(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$

  insert into public.dashboard_metric_settings (organization_id, metric_key, metric_name, metric_category, visible, position)
  values
    (p_organization_id, 'sales_volume_prime', 'Sales Volume (Prime)', 'sales', false, 1),
    (p_organization_id, 'volume_warranty', 'Volume Warranty', 'sales', false, 2),
    (p_organization_id, 'attach_rate', 'Attach Rate', 'sales', false, 3),
    (p_organization_id, 'opportunities_count', 'Opportunities', 'pipeline', false, 4),
    (p_organization_id, 'avg_item_value', 'Average Item Value', 'sales', false, 5),
    (p_organization_id, 'ipo_status', 'IPO Status', 'admin', false, 6),
    (p_organization_id, 'avg_sale_value', 'Average Sale Value', 'sales', false, 7),
    (p_organization_id, 'brand_quote_percentage', 'Brand % of Quote', 'brand', false, 8),
    (p_organization_id, 'brand_clothes_percentage', 'Brand % of Clothes', 'brand', false, 9),
    (p_organization_id, 'kpi_latest_score', 'Latest KPI Score', 'kpi', true, 10),
    (p_organization_id, 'kpi_30day_avg', '30-Day KPI Average', 'kpi', true, 11),
    (p_organization_id, 'recording_count', 'Recordings This Month', 'activity', true, 12),
    (p_organization_id, 'coaching_count', 'Coaching Sessions', 'activity', true, 13),
    (p_organization_id, 'kpi_trend', 'KPI Trend Chart', 'kpi', true, 14),
    (p_organization_id, 'pipeline_cards', 'Pipeline Kanban', 'pipeline', true, 15)
  on conflict (organization_id, metric_key) do nothing;

$fn$;

CREATE OR REPLACE FUNCTION public.init_default_kpis(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$

  insert into public.org_kpis (organization_id, kpi_name, description, weight, target_score)
  values
    (p_organization_id, 'Discovery', 'Asking the right questions to understand customer needs', 1.0, 8.0),
    (p_organization_id, 'Objection Handling', 'Responding effectively to customer concerns', 1.0, 8.0),
    (p_organization_id, 'Product Knowledge', 'Explaining features and benefits clearly', 1.0, 8.0),
    (p_organization_id, 'Closing', 'Moving toward the sale', 1.0, 8.0),
    (p_organization_id, 'Follow-up', 'Maintaining momentum and commitment', 1.0, 8.0)
  on conflict (organization_id, kpi_name) do nothing;

$fn$;

CREATE OR REPLACE FUNCTION public.init_default_metrics(p_org_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

begin
  insert into public.metric_definitions (organization_id, metric_key, metric_label, metric_category, unit, sort_order) values
    (p_org_id, 'revenue',            'Revenue',              'sales',    'currency', 1),
    (p_org_id, 'units_sold',         'Units Sold',           'sales',    'count',    2),
    (p_org_id, 'avg_order',          'Average Order Value',  'sales',    'currency', 3),
    (p_org_id, 'ipo',                'Items Per Order',      'sales',    'count',    4),
    (p_org_id, 'item_value',         'Average Item Value',   'sales',    'currency', 5),
    (p_org_id, 'warranty_revenue',   'Warranty Revenue',     'warranty', 'currency', 10),
    (p_org_id, 'warranty_attach',    'Warranty Attach Rate', 'warranty', 'percent',  11),
    (p_org_id, 'warranty_opps',      'Warranty Opportunities','warranty','count',    12),
    (p_org_id, 'delivery_revenue',   'Delivery Revenue',     'sales',    'currency', 15),
    (p_org_id, 'install_revenue',    'Install Revenue',      'sales',    'currency', 16),
    (p_org_id, 'coaching_avg',       'Avg Coaching Score',   'coaching', 'score',    20),
    (p_org_id, 'training_completion','Training Completion',  'training', 'percent',  25),
    (p_org_id, 'floor_conversion',   'Floor Conversion Rate','floor',    'percent',  30),
    (p_org_id, 'walk_ins',           'Walk-Ins',             'floor',    'count',    31),
    (p_org_id, 'greeting_time',      'Avg Greeting Time',    'floor',    'count',    32)
  on conflict (organization_id, metric_key) do nothing;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.init_default_personas(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$

  insert into public.ai_personas (organization_id, persona_name, persona_role, avatar_emoji, tone, specialization, personality_traits, prompt_prefix)
  values
    (p_organization_id, 'TJ', 'Sales Coach', '🏆', 'motivational, direct, action-oriented', 'Sales coaching and technique', 'energetic, supportive, no-nonsense', 'You are TJ, a sales coach with 20 years of retail experience. Your goal is to coach the rep on their sales technique, objection handling, and closing ability. Be encouraging but direct. Use sports/athletic metaphors.'),
    (p_organization_id, 'Natalie', 'Product Expert', '📚', 'technical, patient, thorough', 'Product knowledge and specs', 'knowledgeable, educational, detail-oriented', 'You are Natalie, a product specialist who knows every appliance inside and out. Explain features, benefits, and trade-offs clearly. Make complex specs easy to understand. Never oversell, always honest about limitations.'),
    (p_organization_id, 'Leah', 'Design Consultant', '🎨', 'creative, warm, collaborative', 'Kitchen design and lifestyle fit', 'creative, empathetic, visionary', 'You are Leah, a design consultant who helps customers visualize how appliances fit into their lifestyle and kitchen aesthetic. Ask about style preferences, existing decor, and workflow before recommending. Think holistically.'),
    (p_organization_id, 'Marcus', 'Objection Handler', '🛡️', 'confident, solution-focused, problem-solving', 'Handling customer concerns', 'logical, confident, diplomatic', 'You are Marcus, an objection-handling specialist. When customers push back on price, warranty, or delivery, you stay calm and reframe concerns as opportunities. Address root fear, then offer solutions.'),
    (p_organization_id, 'Sophie', 'Follow-up Expert', '📞', 'persistent, friendly, detail-oriented', 'Follow-up and closing sequences', 'organized, warm, reliable', 'You are Sophie, a follow-up coordinator who excels at keeping deals warm. You track follow-up tasks, suggest next best actions, and know the timing of when to call vs email. You''re the rep''s accountability partner.')
  on conflict (organization_id, persona_name) do nothing;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_ensure_speciq_package_recommendation(p_package_id uuid) RETURNS uuid LANGUAGE plpgsql AS $fn$

declare p public.speciq_packages%rowtype; v_entity uuid; v_rec uuid; v_products jsonb;
begin
  select * into p from public.speciq_packages where id=p_package_id;
  if p.id is null then return null; end if;
  select id into v_entity from public.intelligence_entities
    where organization_id=p.organization_id and source_system='speciq_package' and source_record_id=p.id::text;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('package_product_id',pp.id,'aiq_product_id',pp.aiq_product_id,'brand',pp.brand,
    'model_number',pp.model_number,'category',pp.category,'quantity',pp.quantity,'price',coalesce(pp.negotiated_price,pp.promo_price,pp.msrp),
    'selection_reason',pp.selection_reason)) order by pp.sort_order),'[]'::jsonb)
    into v_products from public.speciq_package_products pp where pp.package_id=p.id;
  v_rec := public.intelligence_record_recommendation(
    p.organization_id,'package_recommendation','project',p.project_id::text,'present_package:'||p.id::text,
    coalesce(nullif(p.project_type,''),'appliance_package'),v_entity,null,
    jsonb_strip_nulls(jsonb_build_object('package_id',p.id,'package_name',p.package_name,'quote_number',p.quote_number,
      'total_final',p.total_final,'total_savings',p.total_savings,'product_count',jsonb_array_length(v_products),'products',v_products,
      'basis','SpecIQ package composition and pricing')),
    '[]'::jsonb,'speciq_package',p.id::text
  );
  return v_rec;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_entity_context(p_entity_id uuid) RETURNS jsonb LANGUAGE sql AS $fn$

  select jsonb_build_object(
    'entity', to_jsonb(e),
    'timeline', coalesce((select jsonb_agg(to_jsonb(t) order by t.occurred_at desc) from (select * from public.intelligence_timelines where entity_id=e.id order by occurred_at desc limit 50) t), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(ev) order by ev.occurred_at desc) from (select * from public.intelligence_events where entity_id=e.id order by occurred_at desc limit 50) ev), '[]'::jsonb),
    'cached_context', coalesce((select jsonb_agg(to_jsonb(c) order by c.updated_at desc) from public.intelligence_context_cache c where c.entity_id=e.id and (c.expires_at is null or c.expires_at > now())), '[]'::jsonb)
  )
  from public.intelligence_entities e
  where e.id=p_entity_id;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_entity_timeline(p_entity_id uuid, p_limit integer DEFAULT 100) RETURNS SETOF intelligence_timelines LANGUAGE sql AS $fn$

  select t.*
  from public.intelligence_timelines t
  where t.entity_id = p_entity_id
  order by t.occurred_at desc
  limit greatest(1, least(coalesce(p_limit,100),500));

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_event_to_timeline() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  insert into public.intelligence_timelines(
    organization_id, entity_id, event_id, timeline_type, title, summary, metadata, occurred_at
  ) values (
    new.organization_id,
    new.entity_id,
    new.id,
    coalesce(new.payload->>'timeline_type','activity'),
    coalesce(new.payload->>'title', initcap(replace(new.event_type,'_',' '))),
    new.payload->>'summary',
    jsonb_build_object('source_system',new.source_system,'source_record_id',new.source_record_id,'actor_id',new.actor_id),
    new.occurred_at
  )
  on conflict(event_id) do nothing;
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_field_org(p_client_id uuid) RETURNS uuid LANGUAGE sql STABLE AS $fn$

  select organization_id from public.field_clients where id=p_client_id limit 1;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_outcome_after_change() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare rec public.intelligence_recommendations%rowtype;
begin
  select * into rec from public.intelligence_recommendations where id = coalesce(new.recommendation_id, old.recommendation_id);
  perform public.intelligence_refresh_learning_signal(coalesce(new.recommendation_id, old.recommendation_id));
  insert into public.intelligence_events(organization_id, entity_id, event_type, source_system, source_record_id, actor_id, payload, occurred_at)
  values (
    rec.organization_id,
    coalesce(new.entity_id, rec.entity_id),
    case when tg_op='DELETE' then 'RecommendationOutcomeRemoved' else 'RecommendationOutcomeRecorded' end,
    'intelligence_learning',
    coalesce(new.id, old.id)::text,
    coalesce(new.recorded_by, old.recorded_by),
    jsonb_build_object('recommendation_id',rec.id,'outcome_type',coalesce(new.outcome_type,old.outcome_type),'success',coalesce(new.success,old.success),'weight',coalesce(new.weight,old.weight)),
    coalesce(new.occurred_at, old.occurred_at, now())
  );
  return coalesce(new,old);
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_publish_event(p_organization_id uuid, p_entity_id uuid, p_event_type text, p_source_system text, p_source_record_id text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_correlation_id uuid DEFAULT NULL::uuid, p_causation_id uuid DEFAULT NULL::uuid, p_occurred_at timestamp with time zone DEFAULT now()) RETURNS intelligence_events LANGUAGE plpgsql AS $fn$

declare v_event public.intelligence_events;
begin
  insert into public.intelligence_events(
    organization_id, entity_id, event_type, source_system, source_record_id, actor_id,
    correlation_id, causation_id, payload, occurred_at
  ) values (
    p_organization_id, p_entity_id, lower(p_event_type), p_source_system, p_source_record_id,
    auth.uid(), p_correlation_id, p_causation_id, coalesce(p_payload,'{}'::jsonb), p_occurred_at
  ) returning * into v_event;
  return v_event;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_rank_actions(p_organization_id uuid, p_context_key text, p_subject_type text, p_subject_key text, p_limit integer DEFAULT 10) RETURNS TABLE(recommended_action text, bayesian_score numeric, success_rate numeric, observation_count bigint, average_outcome_value numeric) LANGUAGE sql AS $fn$

  select s.recommended_action,s.bayesian_score,s.success_rate,s.observation_count,s.average_outcome_value
  from public.intelligence_learning_signals s
  where s.organization_id=p_organization_id and s.context_key=coalesce(nullif(p_context_key,''),'general')
    and s.subject_type=p_subject_type and s.subject_key=p_subject_key
  order by s.bayesian_score desc,s.observation_count desc,s.updated_at desc
  limit greatest(1,least(coalesce(p_limit,10),100));

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_recommendation_after_insert() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  insert into public.intelligence_events(organization_id, entity_id, event_type, source_system, source_record_id, actor_id, payload, occurred_at)
  values (new.organization_id,new.entity_id,'RecommendationGenerated','intelligence_learning',new.id::text,new.actor_id,
    jsonb_build_object('recommendation_type',new.recommendation_type,'context_key',new.context_key,'subject_type',new.subject_type,'subject_key',new.subject_key,'recommended_action',new.recommended_action,'confidence',new.confidence),new.created_at);
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_record_outcome(p_recommendation_id uuid, p_outcome_type text, p_success boolean DEFAULT NULL::boolean, p_outcome_value numeric DEFAULT NULL::numeric, p_outcome_label text DEFAULT NULL::text, p_weight numeric DEFAULT 1, p_metadata jsonb DEFAULT '{}'::jsonb, p_source_system text DEFAULT 'intelligence_core'::text, p_source_record_id text DEFAULT NULL::text, p_occurred_at timestamp with time zone DEFAULT now()) RETURNS uuid LANGUAGE plpgsql AS $fn$

declare v_id uuid; v_org uuid; v_entity uuid;
begin
  select organization_id,entity_id into v_org,v_entity from public.intelligence_recommendations where id=p_recommendation_id;
  if v_org is null then raise exception 'Recommendation not found'; end if;
  insert into public.intelligence_outcomes(organization_id,recommendation_id,entity_id,outcome_type,outcome_value,outcome_label,success,weight,metadata,source_system,source_record_id,occurred_at,recorded_by)
  values(v_org,p_recommendation_id,v_entity,p_outcome_type,p_outcome_value,p_outcome_label,p_success,coalesce(p_weight,1),coalesce(p_metadata,'{}'::jsonb),p_source_system,p_source_record_id,coalesce(p_occurred_at,now()),(select auth.uid()))
  on conflict (organization_id,source_system,source_record_id) where source_record_id is not null
  do update set outcome_type=excluded.outcome_type,outcome_value=excluded.outcome_value,outcome_label=excluded.outcome_label,success=excluded.success,weight=excluded.weight,metadata=excluded.metadata,occurred_at=excluded.occurred_at
  returning id into v_id;
  return v_id;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_record_recommendation(p_organization_id uuid, p_recommendation_type text, p_subject_type text, p_subject_key text, p_recommended_action text, p_context_key text DEFAULT 'general'::text, p_entity_id uuid DEFAULT NULL::uuid, p_confidence numeric DEFAULT NULL::numeric, p_rationale jsonb DEFAULT '{}'::jsonb, p_alternatives jsonb DEFAULT '[]'::jsonb, p_source_system text DEFAULT 'intelligence_core'::text, p_source_record_id text DEFAULT NULL::text) RETURNS uuid LANGUAGE plpgsql AS $fn$

declare v_id uuid;
begin
  insert into public.intelligence_recommendations(
    organization_id,entity_id,recommendation_type,context_key,subject_type,subject_key,recommended_action,
    confidence,rationale,alternatives,actor_id,source_system,source_record_id,presented_at
  ) values (
    p_organization_id,p_entity_id,p_recommendation_type,coalesce(nullif(p_context_key,''),'general'),p_subject_type,p_subject_key,p_recommended_action,
    p_confidence,coalesce(p_rationale,'{}'::jsonb),coalesce(p_alternatives,'[]'::jsonb),(select auth.uid()),p_source_system,p_source_record_id,now()
  )
  on conflict (organization_id,source_system,source_record_id) where source_record_id is not null
  do update set updated_at=now(), confidence=excluded.confidence, rationale=excluded.rationale, alternatives=excluded.alternatives
  returning id into v_id;
  return v_id;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_refresh_learning_signal(p_recommendation_id uuid) RETURNS void LANGUAGE plpgsql AS $fn$

declare r public.intelligence_recommendations%rowtype;
begin
  select * into r from public.intelligence_recommendations where id = p_recommendation_id;
  if not found then return; end if;

  insert into public.intelligence_learning_signals as s (
    organization_id, context_key, subject_type, subject_key, recommended_action,
    observation_count, success_count, failure_count, neutral_count,
    weighted_success, weighted_total, success_rate, bayesian_score,
    average_outcome_value, last_outcome_at, updated_at
  )
  select
    r.organization_id, r.context_key, r.subject_type, r.subject_key, r.recommended_action,
    count(o.id),
    count(*) filter (where o.success is true),
    count(*) filter (where o.success is false),
    count(*) filter (where o.success is null),
    coalesce(sum(case when o.success is true then greatest(o.weight,0) else 0 end),0),
    coalesce(sum(case when o.success is not null then greatest(o.weight,0) else 0 end),0),
    case when count(*) filter (where o.success is not null) = 0 then 0
      else count(*) filter (where o.success is true)::numeric / count(*) filter (where o.success is not null) end,
    (1 + coalesce(sum(case when o.success is true then greatest(o.weight,0) else 0 end),0)) /
    (2 + coalesce(sum(case when o.success is not null then greatest(o.weight,0) else 0 end),0)),
    avg(o.outcome_value), max(o.occurred_at), now()
  from public.intelligence_recommendations rr
  join public.intelligence_outcomes o on o.recommendation_id = rr.id
  where rr.organization_id = r.organization_id
    and rr.context_key = r.context_key
    and rr.subject_type = r.subject_type
    and rr.subject_key = r.subject_key
    and rr.recommended_action = r.recommended_action
  group by r.organization_id, r.context_key, r.subject_type, r.subject_key, r.recommended_action
  on conflict (organization_id, context_key, subject_type, subject_key, recommended_action)
  do update set
    observation_count = excluded.observation_count,
    success_count = excluded.success_count,
    failure_count = excluded.failure_count,
    neutral_count = excluded.neutral_count,
    weighted_success = excluded.weighted_success,
    weighted_total = excluded.weighted_total,
    success_rate = excluded.success_rate,
    bayesian_score = excluded.bayesian_score,
    average_outcome_value = excluded.average_outcome_value,
    last_outcome_at = excluded.last_outcome_at,
    updated_at = now();
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_register_entity(p_organization_id uuid, p_entity_type text, p_canonical_name text, p_source_system text, p_source_record_id text, p_slug text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS intelligence_entities LANGUAGE plpgsql AS $fn$

declare v_entity public.intelligence_entities;
begin
  insert into public.intelligence_entities(
    organization_id, entity_type, canonical_name, source_system, source_record_id, slug, metadata, created_by, updated_by
  ) values (
    p_organization_id, lower(p_entity_type), p_canonical_name, p_source_system, p_source_record_id, p_slug, coalesce(p_metadata,'{}'::jsonb), auth.uid(), auth.uid()
  )
  on conflict (organization_id, source_system, source_record_id)
  do update set
    canonical_name = excluded.canonical_name,
    entity_type = excluded.entity_type,
    slug = coalesce(excluded.slug, public.intelligence_entities.slug),
    metadata = public.intelligence_entities.metadata || excluded.metadata,
    updated_by = auth.uid()
  returning * into v_entity;
  return v_entity;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_replay_events(p_organization_id uuid, p_after timestamp with time zone DEFAULT NULL::timestamp with time zone, p_event_type text DEFAULT NULL::text, p_limit integer DEFAULT 500) RETURNS SETOF intelligence_events LANGUAGE sql AS $fn$

  select e.*
  from public.intelligence_events e
  where e.organization_id=p_organization_id
    and (p_after is null or e.occurred_at > p_after)
    and (p_event_type is null or e.event_type=p_event_type)
  order by e.occurred_at asc
  limit greatest(1, least(coalesce(p_limit,500),5000));

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_resolve_user_org(p_user_id uuid) RETURNS uuid LANGUAGE sql STABLE AS $fn$

  select case when count(*)=1 then (array_agg(organization_id))[1] else null end
  from public.organization_members
  where user_id=p_user_id and coalesce(status,'active')='active';

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_search_entities(p_organization_id uuid, p_query text, p_entity_type text DEFAULT NULL::text, p_limit integer DEFAULT 25) RETURNS SETOF intelligence_entities LANGUAGE sql AS $fn$

  select e.*
  from public.intelligence_entities e
  where e.organization_id=p_organization_id
    and (p_entity_type is null or e.entity_type=p_entity_type)
    and (
      e.canonical_name ilike '%' || p_query || '%'
      or coalesce(e.slug,'') ilike '%' || p_query || '%'
      or coalesce(e.source_record_id,'') ilike '%' || p_query || '%'
      or e.metadata::text ilike '%' || p_query || '%'
    )
  order by case when lower(e.canonical_name)=lower(p_query) then 0 when lower(e.canonical_name) like lower(p_query)||'%' then 1 else 2 end, e.updated_at desc
  limit greatest(1, least(coalesce(p_limit,25),100));

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  new.updated_at = now();
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_speciq_entity(p_organization_id uuid, p_entity_type text, p_name text, p_source_system text, p_source_record_id text, p_status text DEFAULT 'active'::text, p_metadata jsonb DEFAULT '{}'::jsonb, p_created_by uuid DEFAULT NULL::uuid, p_updated_by uuid DEFAULT NULL::uuid, p_created_at timestamp with time zone DEFAULT now(), p_updated_at timestamp with time zone DEFAULT now()) RETURNS uuid LANGUAGE plpgsql AS $fn$

declare v_id uuid; v_slug text;
begin
  v_slug := trim(both '-' from regexp_replace(lower(coalesce(nullif(p_name,''),p_entity_type)),'[^a-z0-9]+','-','g')) || '-' || left(p_source_record_id,8);
  insert into public.intelligence_entities(
    organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,
    created_by,updated_by,created_at,updated_at
  ) values (
    p_organization_id,p_entity_type,coalesce(nullif(p_name,''),initcap(p_entity_type)),v_slug,p_source_system,p_source_record_id,
    case when p_status in ('active','inactive','archived','merged','deleted') then p_status else 'active' end,
    coalesce(p_metadata,'{}'::jsonb),p_created_by,p_updated_by,coalesce(p_created_at,now()),coalesce(p_updated_at,now())
  )
  on conflict (organization_id,source_system,source_record_id)
  do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,
    metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at
  returning id into v_id;
  return v_id;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_academy_progress() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_org uuid; v_rec uuid; v_title text;
begin
  if tg_op='DELETE' then return old; end if;
  v_org:=public.intelligence_resolve_user_org(new.user_id);
  if v_org is null then return new; end if;
  select title into v_title from public.academy_chapters where id=new.chapter_id;
  v_rec:=public.intelligence_record_recommendation(v_org,'training_module','employee',new.user_id::text,coalesce(v_title,'chapter '||new.chapter_id::text),'academy_chapter:'||new.chapter_id::text,null,null,jsonb_build_object('chapter_id',new.chapter_id),'[]'::jsonb,'academy_progress',new.id::text);
  if new.completed_at is not null then
    perform public.intelligence_record_outcome(v_rec,'module_completed',true,1,'Training module completed',1,jsonb_build_object('chapter_id',new.chapter_id),'academy_progress_outcome',new.id::text,new.completed_at);
    update public.intelligence_recommendations set status='accepted',resolved_at=new.completed_at where id=v_rec;
  end if;
  return new;
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_academy_quiz_score() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_org uuid; v_rec uuid; v_ratio numeric;
begin
  v_org:=public.intelligence_resolve_user_org(new.user_id);
  if v_org is null then return new; end if;
  v_ratio:=case when new.total>0 then new.score::numeric/new.total else 0 end;
  v_rec:=public.intelligence_record_recommendation(v_org,'knowledge_assessment','employee',new.user_id::text,'Complete quiz '||new.vol,'academy_quiz:'||new.vol,null,null,jsonb_build_object('volume',new.vol),'[]'::jsonb,'academy_quiz_score',new.user_id::text||':'||new.vol);
  perform public.intelligence_record_outcome(v_rec,'quiz_score',v_ratio>=0.8,v_ratio,'Quiz completed',1,jsonb_build_object('score',new.score,'total',new.total),'academy_quiz_outcome',new.user_id::text||':'||new.vol,coalesce(new.updated_at,now()));
  update public.intelligence_recommendations set status=case when v_ratio>=0.8 then 'accepted' else 'rejected' end,resolved_at=coalesce(new.updated_at,now()) where id=v_rec;
  return new;
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_ai_coaching_review() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity uuid;
begin
  if tg_op='DELETE' then return old; end if;
  insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_at,updated_at)
  values(new.organization_id,'other',concat('Coaching review: ',new.review_kind),'coaching-review-'||new.id::text,'ai_coaching_review',new.id::text,'active',
    jsonb_strip_nulls(jsonb_build_object('activity_id',new.activity_id,'recording_id',new.recording_id,'review_kind',new.review_kind,'overall_score',new.overall_score,'kpi_scores',new.kpi_scores,'analysis',new.analysis,'model',new.model)),new.created_at,new.created_at)
  on conflict(organization_id,source_system,source_record_id) do update set metadata=excluded.metadata,updated_at=excluded.updated_at returning id into v_entity;
  insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,payload,occurred_at)
  values(new.organization_id,v_entity,'CoachingReviewCompleted','ai_coaching_review',new.id::text,jsonb_build_object('score',new.overall_score,'review_kind',new.review_kind,'kpi_scores',new.kpi_scores),new.created_at);
  return new;
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_ai_roleplay() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity uuid; v_rec uuid; v_success boolean; v_score numeric;
begin
  if tg_op='DELETE' then return old; end if;
  insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
  values(new.organization_id,'conversation',concat('Role-play: ',new.scenario_type),'roleplay-'||new.id::text,'academy_roleplay',new.id::text,case when lower(new.status)='completed' then 'active' else 'inactive' end,
    jsonb_strip_nulls(jsonb_build_object('user_id',new.user_id,'scenario_type',new.scenario_type,'status',new.status,'turns',new.total_turns,'score',new.session_score,'kpi_scores',new.kpi_scores,'feedback',new.feedback)),new.user_id,new.user_id,new.created_at,coalesce(new.completed_at,new.created_at))
  on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at returning id into v_entity;

  v_rec:=public.intelligence_record_recommendation(new.organization_id,'training_practice','employee',new.user_id::text,new.scenario_type,'sales_coach:'||new.scenario_type,v_entity,null,jsonb_build_object('source','roleplay','scenario',new.scenario_type),'[]'::jsonb,'academy_roleplay',new.id::text);

  if lower(new.status)='completed' and new.session_score is not null then
    v_score:=case when new.session_score>10 then new.session_score/10.0 else new.session_score end;
    v_success:=v_score>=7;
    perform public.intelligence_record_outcome(v_rec,'roleplay_score',v_success,v_score,'Role-play completed',greatest(0.25,least(2,v_score/5)),jsonb_build_object('kpi_scores',new.kpi_scores,'feedback',new.feedback),'academy_roleplay_outcome',new.id::text,coalesce(new.completed_at,now()));
    update public.intelligence_recommendations set status=case when v_success then 'accepted' else 'rejected' end,resolved_at=coalesce(new.completed_at,now()) where id=v_rec;
  end if;
  return new;
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_aiq_product() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity_id uuid; v_slug text; v_status text;
begin
 if tg_op='DELETE' then
  select id into v_entity_id from public.intelligence_entities where organization_id=old.organization_id and source_system='product_iq_product' and source_record_id=old.id::text;
  if v_entity_id is not null then
   insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
   values(old.organization_id,v_entity_id,'ProductDeleted','product_iq_product',old.id::text,auth.uid(),jsonb_build_object('model',old.model,'brand_name',old.brand_name),now());
   update public.intelligence_entities set status='deleted',updated_by=auth.uid(),updated_at=now() where id=v_entity_id;
  end if;
  return old;
 end if;
 v_slug:=trim(both '-' from regexp_replace(lower(concat_ws('-',new.brand_name,new.model)),'[^a-z0-9]+','-','g'))||'-'||left(new.id::text,8);
 v_status:=case when coalesce(new.is_discontinued,false) or coalesce(new.is_end_of_life,false) then 'inactive' when lower(coalesce(new.status,'active')) in ('inactive','archived','deleted') then lower(new.status) else 'active' end;
 insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'product',trim(concat_ws(' ',new.brand_name,new.model)),v_slug,'product_iq_product',new.id::text,v_status,
 jsonb_strip_nulls(jsonb_build_object('aiq_product_id',new.id,'brand_id',new.brand_id,'manufacturer_id',new.manufacturer_id,'manufacturer_name',new.manufacturer_name,'brand_name',new.brand_name,'model',new.model,'category',new.category,'series',new.series,'product_line',new.product_line,'product_family',new.product_family,'market',new.market,'msrp',new.msrp,'price_currency',new.price_currency,'upc',new.upc,'ean',new.ean,'gtin',new.gtin,'approval_status',new.approval_status,'public_visible',new.public_visible,'source_type',new.source_type,'source_reference',new.source_reference,'source_confidence',new.source_confidence,'source_review_status',new.source_review_status,'version_number',new.version_number,'is_discontinued',new.is_discontinued,'is_clearance',new.is_clearance,'is_end_of_life',new.is_end_of_life,'replacement_model',new.replacement_model)),coalesce(new.created_by,auth.uid()),coalesce(new.updated_by,auth.uid()),coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at returning id into v_entity_id;
 insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'ProductCreated' else 'ProductUpdated' end,'product_iq_product',new.id::text,coalesce(new.updated_by,new.created_by,auth.uid()),jsonb_strip_nulls(jsonb_build_object('model',new.model,'brand_name',new.brand_name,'category',new.category,'approval_status',new.approval_status,'public_visible',new.public_visible,'version_number',new.version_number,'source_confidence',new.source_confidence,'operation',lower(tg_op))),case when tg_op='INSERT' then coalesce(new.created_at,now()) else coalesce(new.updated_at,now()) end);
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_brand_catalog() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity_id uuid; v_slug text;
begin
 if tg_op='DELETE' then
  select id into v_entity_id from public.intelligence_entities where organization_id=old.organization_id and source_system='product_iq_brand' and source_record_id=old.id::text;
  if v_entity_id is not null then
   insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
   values(old.organization_id,v_entity_id,'BrandDeleted','product_iq_brand',old.id::text,auth.uid(),jsonb_build_object('brand_name',old.brand_name),now());
   update public.intelligence_entities set status='deleted',updated_by=auth.uid(),updated_at=now() where id=v_entity_id;
  end if;
  return old;
 end if;
 v_slug:=trim(both '-' from regexp_replace(lower(coalesce(new.slug,new.brand_name,'brand')),'[^a-z0-9]+','-','g'))||'-'||left(new.id::text,8);
 insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'brand',new.brand_name,v_slug,'product_iq_brand',new.id::text,case when coalesce(new.is_active,true) then 'active' else 'inactive' end,
 jsonb_strip_nulls(jsonb_build_object('brand_catalog_id',new.id,'brand_tier',new.brand_tier,'manufacturer_id',new.manufacturer_id,'parent_company',new.parent_company,'country',new.country,'website',new.website,'canada_website',new.canada_website,'us_website',new.us_website,'logo_url',new.logo_url,'public_visible',new.public_visible,'product_categories',new.product_categories,'academy_status',new.academy_status)),auth.uid(),auth.uid(),coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at returning id into v_entity_id;
 insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'BrandCreated' else 'BrandUpdated' end,'product_iq_brand',new.id::text,auth.uid(),jsonb_strip_nulls(jsonb_build_object('brand_name',new.brand_name,'manufacturer_id',new.manufacturer_id,'active',new.is_active,'operation',lower(tg_op))),case when tg_op='INSERT' then coalesce(new.created_at,now()) else coalesce(new.updated_at,now()) end);
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_crm_contact() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity_id uuid; v_name text; v_status text;
begin
 if tg_op='DELETE' then
  update public.intelligence_entities set status='deleted',updated_at=now(),updated_by=auth.uid()
  where organization_id=old.organization_id and source_system='crm_contact' and source_record_id=old.id::text;
  return old;
 end if;
 v_name:=coalesce(nullif(new.preferred_name,''),nullif(trim(concat_ws(' ',new.first_name,new.last_name)),''),new.email,'Unnamed contact');
 v_status:=case when lower(coalesce(new.relationship_status,'')) in ('inactive','archived') then lower(new.relationship_status) else 'active' end;
 insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'customer',v_name,trim(both '-' from regexp_replace(lower(v_name),'[^a-z0-9]+','-','g'))||'-'||left(new.id::text,8),'crm_contact',new.id::text,v_status,
 jsonb_strip_nulls(jsonb_build_object('contact_id',new.id,'company_id',new.company_id,'email',new.email,'phone',coalesce(new.mobile_phone,new.phone),'preferred_contact_method',new.preferred_contact_method,'preferred_language',new.preferred_language,'decision_making_role',new.decision_making_role,'purchasing_authority',new.purchasing_authority,'temperature',new.temperature,'lead_source',new.lead_source,'is_iq_lead',new.is_iq_lead,'last_communication_at',new.last_communication_at,'customer_last_response',new.customer_last_response,'next_followup_date',new.next_followup_date,'followup_status',new.followup_status)),
 new.assigned_salesperson_id,new.assigned_salesperson_id,new.created_at,new.updated_at)
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at,updated_by=excluded.updated_by returning id into v_entity_id;
 insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'CustomerRegistered' else 'CustomerUpdated' end,'crm_contact',new.id::text,new.assigned_salesperson_id,jsonb_build_object('title',case when tg_op='INSERT' then 'CRM customer registered' else 'CRM customer updated' end,'contact_id',new.id,'temperature',new.temperature,'followup_status',new.followup_status),case when tg_op='INSERT' then new.created_at else new.updated_at end);
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_crm_deal() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity_id uuid; v_rec_id uuid; v_stage text; v_success boolean; v_terminal boolean; v_action text; v_context text; pkg record;
begin
 if tg_op='DELETE' then
  update public.intelligence_entities set status='deleted',updated_at=now(),updated_by=auth.uid() where organization_id=old.organization_id and source_system='crm_deal' and source_record_id=old.id::text;
  return old;
 end if;
 v_stage:=lower(trim(coalesce(new.stage,'')));
 v_success:=case when v_stage in ('closed won','won','sold','completed','purchased') then true when v_stage in ('closed lost','lost','cancelled','canceled','rejected','expired') then false else null end;
 v_terminal:=v_success is not null;
 v_action:=coalesce(nullif(new.next_action,''),case when v_terminal then 'review outcome' else 'advance deal from '||coalesce(new.stage,'current stage') end);
 v_context:='crm_deal:'||coalesce(new.record_type,'retail')||':'||coalesce(array_to_string(new.product_categories,','),'general');
 insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'opportunity',new.title,trim(both '-' from regexp_replace(lower(new.title),'[^a-z0-9]+','-','g'))||'-'||left(new.id::text,8),'crm_deal',new.id::text,case when coalesce(new.is_archived,false) then 'archived' else 'active' end,
 jsonb_strip_nulls(jsonb_build_object('deal_id',new.id,'company_id',new.company_id,'contact_id',new.contact_id,'stage',new.stage,'value_amount',new.value_amount,'value_currency',new.value_currency,'margin_amount',new.margin_amount,'margin_pct',new.margin_pct,'expected_close_date',new.expected_close_date,'closed_at',new.closed_at,'product_categories',new.product_categories,'next_action',new.next_action,'next_action_date',new.next_action_date,'priority',new.priority,'lost_reason',new.lost_reason,'lost_competitor',new.lost_competitor,'lost_objection',new.lost_objection,'order_number',new.order_number,'purchase_date',new.purchase_date,'delivery_date',new.delivery_date,'won_products',new.won_products,'source',new.source,'traffic_source',new.traffic_source,'temperature',new.temperature)),
 new.owner_user_id,new.owner_user_id,new.created_at,new.updated_at)
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at,updated_by=excluded.updated_by returning id into v_entity_id;
 v_rec_id:=public.intelligence_record_recommendation(new.organization_id,'deal_next_action','deal',new.id::text,v_action,v_context,v_entity_id,case when new.temperature::text='hot' then .85 when new.temperature::text='warm' then .7 else .55 end,jsonb_strip_nulls(jsonb_build_object('stage',new.stage,'priority',new.priority,'expected_close_date',new.expected_close_date,'value',new.value_amount,'currency',new.value_currency)),'[]'::jsonb,'crm_deal',new.id::text);
 update public.intelligence_recommendations set status=case when v_terminal then case when v_success then 'accepted' else 'rejected' end else 'presented' end,resolved_at=case when v_terminal then coalesce(new.closed_at,now()) else null end,updated_at=now() where id=v_rec_id;
 if v_terminal then
  perform public.intelligence_record_outcome(v_rec_id,case when v_success then 'deal_won' else 'deal_lost' end,v_success,new.value_amount,case when v_success then 'Closed Won' else coalesce(new.lost_reason,'Closed Lost') end,5,jsonb_strip_nulls(jsonb_build_object('stage',new.stage,'margin_amount',new.margin_amount,'margin_pct',new.margin_pct,'lost_competitor',new.lost_competitor,'lost_objection',new.lost_objection)),'crm_deal',new.id::text||':terminal',coalesce(new.closed_at,new.updated_at,now()));
  for pkg in select p.id,r.id recommendation_id from public.speciq_packages p join public.intelligence_recommendations r on r.organization_id=p.organization_id and r.source_system='speciq_package' and r.source_record_id=p.id::text where p.organization_id=new.organization_id and p.deal_id=new.id loop
   perform public.intelligence_record_outcome(pkg.recommendation_id,case when v_success then 'package_sale_won' else 'package_sale_lost' end,v_success,new.value_amount,case when v_success then 'CRM deal won' else coalesce(new.lost_reason,'CRM deal lost') end,6,jsonb_build_object('crm_deal_id',new.id,'crm_stage',new.stage),'crm_deal',new.id::text||':speciq:'||pkg.id::text,coalesce(new.closed_at,new.updated_at,now()));
  end loop;
 end if;
 insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'DealRegistered' when old.stage is distinct from new.stage then 'DealStageChanged' else 'DealUpdated' end,'crm_deal',new.id::text,new.owner_user_id,jsonb_strip_nulls(jsonb_build_object('title','CRM deal '||case when tg_op='INSERT' then 'registered' when old.stage is distinct from new.stage then 'stage changed' else 'updated' end,'from_stage',case when tg_op='UPDATE' then old.stage end,'to_stage',new.stage,'value',new.value_amount,'currency',new.value_currency)),new.updated_at);
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_crm_delivery() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_rec uuid; v_success boolean;
begin
 select id into v_rec from public.intelligence_recommendations where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 if v_rec is null then return new; end if;
 if new.delivered_at is not null then perform public.intelligence_record_outcome(v_rec,'delivery_completed',true,null,'Delivered',2,jsonb_build_object('delivery_workflow_id',new.id),'crm_delivery',new.id::text||':delivered',new.delivered_at); end if;
 if new.installed_at is not null then perform public.intelligence_record_outcome(v_rec,'installation_completed',true,null,'Installed',2,jsonb_build_object('delivery_workflow_id',new.id),'crm_delivery',new.id::text||':installed',new.installed_at); end if;
 if new.satisfaction_score is not null then
  v_success:=new.satisfaction_score>=4;
  perform public.intelligence_record_outcome(v_rec,'customer_satisfaction',v_success,new.satisfaction_score,new.satisfaction_notes,3,jsonb_build_object('score',new.satisfaction_score),'crm_delivery',new.id::text||':satisfaction',new.updated_at);
 end if;
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_crm_postmortem() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_rec uuid; v_entity uuid;
begin
 select id into v_entity from public.intelligence_entities where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 select id into v_rec from public.intelligence_recommendations where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity,'DealPostmortemRecorded','crm_postmortem',new.id::text,new.salesperson_id,jsonb_strip_nulls(jsonb_build_object('title','CRM deal postmortem recorded','review_type',new.review_type,'strengths',new.strengths,'improvements',new.improvements,'objections',new.objections,'closing_method',new.closing_method,'controllability',new.controllability,'recoverable',new.is_recoverable,'warranty_sold',new.warranty_sold,'accessories_included',new.accessories_included,'competitor_considered',new.competitor_considered)),coalesce(new.completed_at,new.updated_at,new.created_at));
 if v_rec is not null and new.completed_at is not null then perform public.intelligence_record_outcome(v_rec,'postmortem_completed',null,null,new.review_type,.5,jsonb_strip_nulls(jsonb_build_object('customer_satisfaction',new.customer_satisfaction,'warranty_sold',new.warranty_sold,'accessories_included',new.accessories_included,'closing_method',new.closing_method)),'crm_postmortem',new.id::text,new.completed_at); end if;
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_crm_task() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_rec uuid; v_entity uuid; v_success boolean;
begin
 if new.ai_recommended is distinct from true then return new; end if;
 select id into v_entity from public.intelligence_entities where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 v_rec:=public.intelligence_record_recommendation(new.organization_id,'crm_task','deal',coalesce(new.deal_id::text,new.contact_id::text,new.company_id::text),new.title,'crm_task:'||coalesce(new.task_type,'general'),v_entity,case when new.ai_priority_score between 0 and 1 then new.ai_priority_score else null end,jsonb_strip_nulls(jsonb_build_object('description',new.description,'due_at',new.due_at,'priority',new.priority,'task_category',new.task_category)),'[]'::jsonb,'crm_task',new.id::text);
 if new.completed_at is not null then
  v_success:=case when lower(coalesce(new.resolution_note,'')) like '%unsuccess%' or lower(coalesce(new.resolution_note,'')) like '%failed%' then false else true end;
  perform public.intelligence_record_outcome(v_rec,'task_completed',v_success,null,new.resolution_note,1,jsonb_build_object('deal_id',new.deal_id,'completed_at',new.completed_at),'crm_task',new.id::text||':completed',new.completed_at);
 end if;
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_daily_coaching_focus() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_rec uuid;
begin
  if tg_op='DELETE' then return old; end if;
  v_rec:=public.intelligence_record_recommendation(new.organization_id,'coaching_focus','employee',new.user_id::text,coalesce(new.primary_kpi_name,'general coaching'),'coach_focus:'||coalesce(lower(regexp_replace(new.primary_kpi_name,'[^a-zA-Z0-9]+','_','g')),'general'),null,null,
    jsonb_strip_nulls(jsonb_build_object('previous_score',new.previous_score,'target_score',new.target_score,'insight',new.insight,'focus_date',new.focus_date)),'[]'::jsonb,'daily_coaching_focus',new.id::text);
  return new;
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_field_action() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare
  v_org uuid;
  v_rec uuid;
  v_success boolean;
  v_done boolean;
begin
  v_org := public.intelligence_field_org(new.client_id);
  if v_org is null then return new; end if;

  select id into v_rec
  from public.intelligence_recommendations
  where organization_id=v_org
    and source_system='field_reports_finding'
    and source_record_id=new.finding_id::text
  limit 1;

  if v_rec is null then
    v_rec := public.intelligence_record_recommendation(
      v_org,'field_corrective_action','field_finding',new.finding_id::text,new.title,
      'field_action:'||coalesce(new.action_type,'general'),null,null,
      jsonb_build_object('priority',new.priority,'description',new.description),
      '[]'::jsonb,'field_reports_action',new.id::text
    );
  end if;

  v_done := lower(coalesce(new.status,'')) in ('resolved','closed','completed','verified','service_deployed','replacement_installed');
  v_success := v_done and coalesce(new.verified_at,new.resolved_at,new.closed_at) is not null;

  if v_done then
    perform public.intelligence_record_outcome(
      v_rec,'field_action_resolution',v_success,null,new.status,
      case lower(coalesce(new.priority,'')) when 'critical' then 2 when 'high' then 1.5 else 1 end,
      jsonb_build_object('action_id',new.id,'status',new.status,'resolution_notes',new.resolution_notes,'verified_at',new.verified_at,'due_date',new.due_date,'escalation_level',new.escalation_level),
      'field_reports_action',new.id::text,
      coalesce(new.verified_at,new.resolved_at,new.closed_at,new.updated_at,now())
    );

    if v_success then
      update public.intelligence_recommendations
      set status='accepted',
          resolved_at=coalesce(new.verified_at,new.resolved_at,new.closed_at,new.updated_at,now()),
          updated_at=now()
      where id=v_rec;
    end if;
  end if;

  insert into public.intelligence_events(
    organization_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at
  ) values (
    v_org,
    case when v_done then 'FieldActionResolved' else 'FieldActionUpdated' end,
    'field_reports_action',new.id::text,
    coalesce(new.verified_by_user_id,new.assigned_to_user_id),
    jsonb_strip_nulls(jsonb_build_object(
      'title',new.title,'status',new.status,'priority',new.priority,
      'action_type',new.action_type,'finding_id',new.finding_id,
      'store_id',new.store_id,'resolution_notes',new.resolution_notes
    )),
    coalesce(new.updated_at,new.created_at,now())
  );
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_field_competitive() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_org uuid; v_client uuid;
begin
 select client_id into v_client from public.field_visits where id=new.visit_id; v_org:=public.intelligence_field_org(v_client); if v_org is null then return new; end if;
 insert into public.intelligence_events(organization_id,event_type,source_system,source_record_id,payload,occurred_at)
 values(v_org,'CompetitiveIntelRecorded','field_competitive_intel',new.id::text,
   jsonb_strip_nulls(jsonb_build_object('title','Competitive activity: '||new.competitor_brand,'visit_id',new.visit_id,'store_id',new.store_id,'competitor_brand',new.competitor_brand,'floor_presence_pct',new.floor_presence_pct,'share_of_display',new.share_of_display,'promotions_active',new.promotions_active,'pricing_notes',new.pricing_notes,'new_models_spotted',new.new_models_spotted,'staff_preference_notes',new.staff_preference_notes,'customer_questions',new.customer_questions,'common_objections',new.common_objections,'rep_comments',new.rep_comments)),coalesce(new.created_at,now()));
 return new;
end;
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_field_finding() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_org uuid; v_entity uuid; v_visit_entity uuid;
begin
  v_org:=public.intelligence_field_org(new.client_id); if v_org is null then return new; end if;
  select id into v_visit_entity from public.intelligence_entities where organization_id=v_org and source_system='field_reports_visit' and source_record_id=new.visit_id::text limit 1;
  insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_at,updated_at)
  values(v_org,'other',coalesce(new.issue_category,'Field finding')||coalesce(' - '||new.model_number,''),'field-finding-'||new.id::text,'field_reports_finding',new.id::text,
    case when lower(coalesce(new.status,'')) in ('resolved','closed') then 'inactive' else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('visit_id',new.visit_id,'store_id',new.store_id,'brand_name',new.brand_name,'product_category',new.product_category,'model_number',new.model_number,'condition',new.condition,'issue_category',new.issue_category,'severity',new.severity,'recommended_action',new.recommended_action,'rep_comments',new.rep_comments,'ai_summary',new.ai_summary,'is_repeat',new.is_repeat,'status',new.status,'source',new.source)),coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
  on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at returning id into v_entity;
  insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,payload,occurred_at)
  values(v_org,coalesce(v_visit_entity,v_entity),case when tg_op='INSERT' then 'FieldFindingRecorded' else 'FieldFindingUpdated' end,'field_reports_finding',new.id::text,
    jsonb_strip_nulls(jsonb_build_object('title',initcap(coalesce(new.severity,'field'))||' finding','summary',coalesce(new.ai_summary,new.rep_comments),'finding_entity_id',v_entity,'severity',new.severity,'issue_category',new.issue_category,'brand_name',new.brand_name,'model_number',new.model_number,'recommended_action',new.recommended_action,'is_repeat',new.is_repeat)),coalesce(new.updated_at,new.created_at,now()));
  if nullif(new.recommended_action,'') is not null then
    perform public.intelligence_record_recommendation(v_org,'field_corrective_action','field_finding',new.id::text,new.recommended_action,'field_issue:'||coalesce(new.issue_category,'general'),v_entity,
      case lower(coalesce(new.severity,'')) when 'critical' then 0.95 when 'high' then 0.85 when 'medium' then 0.7 else 0.55 end,
      jsonb_build_object('severity',new.severity,'brand_name',new.brand_name,'model_number',new.model_number,'is_repeat',new.is_repeat),'[]'::jsonb,'field_reports_finding',new.id::text);
  end if;
  return new;
end;
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_field_store_score() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_org uuid; v_rec uuid; v_score numeric;
begin
 v_org:=public.intelligence_field_org(new.client_id); if v_org is null or new.overall_score is null then return new; end if;
 v_rec:=public.intelligence_record_recommendation(v_org,'store_condition_improvement','store',new.store_id::text,'improve and maintain store execution score','field_store_score',null,null,jsonb_build_object('visit_id',new.visit_id),'[]'::jsonb,'field_store_score',new.id::text);
 v_score:=case when new.overall_score>10 then new.overall_score/100.0 else new.overall_score/10.0 end;
 perform public.intelligence_record_outcome(v_rec,'store_execution_score',v_score>=0.7,v_score,'store score',1,jsonb_build_object('overall_score',new.overall_score,'score_date',new.score_date),'field_store_score',new.id::text,coalesce(new.created_at,now()));
 return new;
end;
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_field_training() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_org uuid; v_rec uuid; v_score numeric; v_success boolean;
begin
 v_org:=public.intelligence_field_org(new.client_id); if v_org is null then return new; end if;
 v_rec:=public.intelligence_record_recommendation(v_org,'field_staff_training','store',new.store_id::text,'deliver training: '||new.training_topic,'field_training:'||coalesce(new.product_category,coalesce(new.brand_name,'general')),null,null,
   jsonb_build_object('brand_name',new.brand_name,'models_covered',new.models_covered,'employees_trained',new.employees_trained,'areas_of_weakness',new.areas_of_weakness),'[]'::jsonb,'field_training_session',new.id::text);
 if new.knowledge_score is not null then
   v_score:=case when new.knowledge_score>10 then new.knowledge_score/100.0 else new.knowledge_score/10.0 end;
   v_success:=v_score>=0.7;
   perform public.intelligence_record_outcome(v_rec,'training_knowledge_score',v_success,v_score,'field training result',1,
     jsonb_build_object('knowledge_score',new.knowledge_score,'employees_trained',new.employees_trained,'duration_minutes',new.duration_minutes,'follow_up_required',new.follow_up_required),'field_training_score',new.id::text,coalesce(new.created_at,now()));
 end if;
 insert into public.intelligence_events(organization_id,event_type,source_system,source_record_id,payload,occurred_at)
 values(v_org,'FieldTrainingCompleted','field_training_session',new.id::text,jsonb_strip_nulls(jsonb_build_object('title',new.training_topic,'brand_name',new.brand_name,'product_category',new.product_category,'employees_trained',new.employees_trained,'knowledge_score',new.knowledge_score,'follow_up_required',new.follow_up_required)),coalesce(new.created_at,now()));
 return new;
end;
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_field_visit() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_org uuid; v_entity uuid; v_store text; v_client text; v_score numeric; v_success boolean;
begin
  v_org:=public.intelligence_field_org(new.client_id);
  if v_org is null then return new; end if;
  select store_name into v_store from public.field_stores where id=new.store_id;
  select client_name into v_client from public.field_clients where id=new.client_id;
  insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
  values(v_org,'field_report',coalesce(v_store,'Store')||' visit '||new.visit_date::text,'field-visit-'||new.id::text,'field_reports_visit',new.id::text,
    case when lower(coalesce(new.status,''))='completed' then 'active' else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('client_id',new.client_id,'client_name',v_client,'store_id',new.store_id,'store_name',v_store,'rep_user_id',new.rep_user_id,'visit_date',new.visit_date,'visit_type',new.visit_type,'visit_purpose',new.visit_purpose,'status',new.status,'duration_minutes',new.duration_minutes,'findings_count',new.findings_count,'critical_count',new.critical_count,'training_completed',new.training_completed,'people_trained',new.people_trained,'store_score',new.store_score,'brand_score',new.brand_score,'previous_score',new.previous_score,'checklist_score',new.checklist_score,'rep_summary',new.rep_summary,'ai_summary',new.ai_summary)),
    new.rep_user_id,new.rep_user_id,coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
  on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at
  returning id into v_entity;
  insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
  values(v_org,v_entity,case when tg_op='INSERT' then 'FieldVisitCreated' else 'FieldVisitUpdated' end,'field_reports_visit',new.id::text,new.rep_user_id,
    jsonb_strip_nulls(jsonb_build_object('title','Field visit '||coalesce(v_store,''),'summary',new.ai_summary,'status',new.status,'store_score',new.store_score,'critical_count',new.critical_count)),coalesce(new.updated_at,new.created_at,now()));
  if lower(coalesce(new.status,''))='completed' and new.store_score is not null then
    v_score:=case when new.store_score>10 then new.store_score/100.0 else new.store_score/10.0 end;
    v_success:=v_score>=0.7;
    perform public.intelligence_record_recommendation(v_org,'field_visit_execution','store',new.store_id::text,'complete field visit and improve store condition','field_visit:'||coalesce(new.visit_type,'general'),v_entity,null,jsonb_build_object('visit_purpose',new.visit_purpose),'[]'::jsonb,'field_reports_visit',new.id::text);
    perform public.intelligence_record_outcome((select id from public.intelligence_recommendations where organization_id=v_org and source_system='field_reports_visit' and source_record_id=new.id::text limit 1),'store_score',v_success,v_score,'completed visit score',1,jsonb_build_object('store_score',new.store_score,'previous_score',new.previous_score),'field_reports_visit_score',new.id::text,coalesce(new.departure_time,new.updated_at,now()));
  end if;
  return new;
end;
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_iq_customer_interaction() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity_id uuid; v_assignment_rec uuid; v_success boolean; v_weight numeric; v_outcome text;
begin
 if tg_op='DELETE' then update public.intelligence_entities set status='deleted',updated_at=now() where organization_id=old.organization_id and source_system='iq_up_interaction' and source_record_id=old.id::text; return old; end if;
 insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'conversation','Customer interaction '||new.id::text,'interaction-'||new.id::text,'iq_up_interaction',new.id::text,case when new.ended_at is null then 'active' else 'archived' end,
 jsonb_strip_nulls(jsonb_build_object('store_id',new.store_id,'shift_id',new.shift_id,'queue_entry_id',new.queue_entry_id,'customer_waiting_id',new.customer_waiting_id,'source',new.interaction_source,'type',new.interaction_type,'salesperson_user_id',new.salesperson_user_id,'started_at',new.started_at,'accepted_at',new.accepted_at,'ended_at',new.ended_at,'outcome',new.outcome,'contact_id',new.contact_id,'account_id',new.account_id,'opportunity_id',new.opportunity_id,'follow_up_date',new.follow_up_date,'no_follow_up',new.no_follow_up,'reason_not_purchased',new.reason_not_purchased)),coalesce(new.created_by,auth.uid()),coalesce(new.updated_by,auth.uid()),new.created_at,new.updated_at)
 on conflict(organization_id,source_system,source_record_id) do update set slug=excluded.slug,status=excluded.status,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at returning id into v_entity_id;
 if new.customer_waiting_id is not null then select id into v_assignment_rec from public.intelligence_recommendations where organization_id=new.organization_id and source_system='iq_up_assignment' and source_record_id='waiting:'||new.customer_waiting_id::text; end if;
 v_outcome:=lower(coalesce(new.outcome,''));
 if v_assignment_rec is not null and v_outcome<>'' then
  v_success:=v_outcome in ('sale','sold','closed_won','won','purchase','purchased');
  v_weight:=case when v_success then 3.0 when v_outcome in ('no_sale','lost','closed_lost') then 2.0 else 0.75 end;
  perform public.intelligence_record_outcome(v_assignment_rec,case when v_success then 'interaction_sale' else 'interaction_'||v_outcome end,case when v_success then true when v_outcome in ('no_sale','lost','closed_lost') then false else null end,null,v_outcome,v_weight,jsonb_strip_nulls(jsonb_build_object('interaction_id',new.id,'salesperson_user_id',new.salesperson_user_id,'reason_not_purchased',new.reason_not_purchased,'follow_up_date',new.follow_up_date,'no_follow_up',new.no_follow_up)),'iq_up_interaction','interaction:'||new.id::text,coalesce(new.ended_at,new.updated_at,new.created_at));
  update public.intelligence_recommendations set status=case when v_success then 'accepted' when v_outcome in ('no_sale','lost','closed_lost') then 'rejected' else status end,resolved_at=case when v_outcome in ('sale','sold','closed_won','won','purchase','purchased','no_sale','lost','closed_lost') then coalesce(resolved_at,new.ended_at,new.updated_at,now()) else resolved_at end where id=v_assignment_rec;
 end if;
 insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'CustomerInteractionCreated' else 'CustomerInteractionUpdated' end,'iq_up_interaction',new.id::text,coalesce(new.updated_by,new.created_by,auth.uid()),jsonb_build_object('outcome',new.outcome,'salesperson_user_id',new.salesperson_user_id,'follow_up_date',new.follow_up_date,'no_follow_up',new.no_follow_up),coalesce(new.ended_at,new.updated_at,new.created_at));
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_iq_lead_assignment() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity uuid; v_rec uuid;
begin
 if tg_op='DELETE' then return old; end if;
 select id into v_entity from public.intelligence_entities where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 v_rec:=public.intelligence_record_recommendation(new.organization_id,'lead_assignment','lead',coalesce(new.deal_id::text,new.contact_id::text,new.id::text),'assign_lead:'||coalesce(new.assigned_to::text,'unassigned'),coalesce('location:'||new.location_id::text,'crm'),v_entity,null,jsonb_strip_nulls(jsonb_build_object('assignment_reason',new.assignment_reason,'routing_method',new.routing_method,'response_time_seconds',new.response_time_seconds,'reassignment_count',new.reassignment_count)),'[]'::jsonb,'crm_iq_lead_assignment',new.id::text);
 if new.accepted is not null then
  perform public.intelligence_record_outcome(v_rec,case when new.accepted then 'lead_assignment_accepted' else 'lead_assignment_declined' end,new.accepted,null,case when new.accepted then 'accepted' else 'declined' end,1.0,jsonb_strip_nulls(jsonb_build_object('response_time_seconds',new.response_time_seconds,'decline_reason',new.decline_reason,'reassignment_count',new.reassignment_count)),'crm_iq_lead_assignment','assignment:'||new.id::text,coalesce(new.accepted_at,new.declined_at,new.created_at));
  update public.intelligence_recommendations set status=case when new.accepted then 'accepted' else 'rejected' end,resolved_at=coalesce(resolved_at,new.accepted_at,new.declined_at,now()) where id=v_rec;
 end if;
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_iq_product_interest() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_waiting_entity uuid; v_action text;
begin
 if tg_op='DELETE' then return old; end if;
 select id into v_waiting_entity from public.intelligence_entities where organization_id=new.organization_id and source_system='iq_up_waiting_customer' and source_record_id=new.customer_waiting_id::text;
 v_action:='show_product:'||coalesce(nullif(new.brand,''),'unknown')||':'||coalesce(nullif(new.product_name,''),coalesce(nullif(new.category,''),'unspecified'));
 perform public.intelligence_record_recommendation(new.organization_id,'floor_product_interest','waiting_customer',new.customer_waiting_id::text,v_action,coalesce('store:'||new.store_id::text,'iq_up'),v_waiting_entity,null,jsonb_strip_nulls(jsonb_build_object('category',new.category,'brand',new.brand,'product_name',new.product_name,'price',new.price,'stock_status',new.stock_status,'delivery_date',new.delivery_date,'notes',new.notes)),'[]'::jsonb,'iq_up_product_interest',new.id::text);
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_iq_waiting_customer() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity_id uuid; v_name text; v_status text; v_rec_id uuid;
begin
 if tg_op='DELETE' then
  update public.intelligence_entities set status='deleted',updated_at=now(),updated_by=auth.uid()
  where organization_id=old.organization_id and source_system='iq_up_waiting_customer' and source_record_id=old.id::text;
  return old;
 end if;
 v_name:=coalesce(nullif(new.customer_display_name,''),'Waiting customer '||new.id::text);
 v_status:=case when new.status::text in ('left_unserved','cancelled','completed') then 'archived' else 'active' end;
 insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'customer',v_name,'waiting-customer-'||new.id::text,'iq_up_waiting_customer',new.id::text,v_status,
 jsonb_strip_nulls(jsonb_build_object('store_id',new.store_id,'shift_id',new.shift_id,'assigned_user_id',new.assigned_user_id,'group_size',new.customer_group_size,'description',new.customer_description,'category',new.customer_category,'requested_source',new.requested_source,'requested_employee_user_id',new.requested_employee_user_id,'priority',new.priority,'status',new.status::text,'arrival_time',new.arrival_time,'attempts',new.attempts,'max_attempts',new.max_attempts,'returning_customer',new.is_returning_customer,'purchase_timeframe',new.purchase_timeframe,'lead_source',new.lead_source,'customer_needs',new.customer_needs,'crm_contact_id',new.crm_contact_id,'crm_deal_id',new.crm_deal_id)),coalesce(new.created_by,auth.uid()),coalesce(new.updated_by,auth.uid()),new.created_at,new.updated_at)
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at returning id into v_entity_id;
 if new.assigned_user_id is not null then
  v_rec_id:=public.intelligence_record_recommendation(new.organization_id,'salesperson_assignment','waiting_customer',new.id::text,'assign_salesperson:'||new.assigned_user_id::text,coalesce('store:'||new.store_id::text,'iq_up'),v_entity_id,null,jsonb_strip_nulls(jsonb_build_object('priority',new.priority,'requested_employee_user_id',new.requested_employee_user_id,'purchase_timeframe',new.purchase_timeframe,'lead_source',new.lead_source)),'[]'::jsonb,'iq_up_assignment','waiting:'||new.id::text);
 end if;
 if new.status::text='left_unserved' then
  select id into v_rec_id from public.intelligence_recommendations where organization_id=new.organization_id and source_system='iq_up_assignment' and source_record_id='waiting:'||new.id::text;
  if v_rec_id is not null then
   perform public.intelligence_record_outcome(v_rec_id,'customer_left_unserved',false,null,'left_unserved',1.5,jsonb_build_object('attempts',new.attempts,'max_attempts',new.max_attempts),'iq_up_waiting_customer','left_unserved:'||new.id::text,new.updated_at);
   update public.intelligence_recommendations set status='rejected',resolved_at=coalesce(resolved_at,new.updated_at) where id=v_rec_id;
  end if;
 end if;
 insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'WaitingCustomerCreated' else 'WaitingCustomerUpdated' end,'iq_up_waiting_customer',new.id::text,coalesce(new.updated_by,new.created_by,auth.uid()),jsonb_build_object('status',new.status::text,'assigned_user_id',new.assigned_user_id,'attempts',new.attempts,'priority',new.priority),case when tg_op='INSERT' then new.created_at else new.updated_at end);
 return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_speciq_package() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity uuid; v_event text; v_rec uuid; v_success boolean; v_outcome_type text;
begin
  if tg_op='DELETE' then
    select id into v_entity from public.intelligence_entities
      where organization_id=old.organization_id and source_system='speciq_package' and source_record_id=old.id::text;
    if v_entity is not null then
      update public.intelligence_entities set status='deleted',updated_at=now(),updated_by=(select auth.uid()) where id=v_entity;
      insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
      values(old.organization_id,v_entity,'SpecIQPackageDeleted','speciq_package',old.id::text,(select auth.uid()),
        jsonb_build_object('title','SpecIQ package deleted','package_name',old.package_name,'timeline_type','package'),now());
    end if;
    return old;
  end if;

  v_entity := public.intelligence_speciq_entity(
    new.organization_id,'package',new.package_name,'speciq_package',new.id::text,
    case when lower(coalesce(new.status,'active')) in ('archived','deleted','inactive') then lower(new.status) else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('project_id',new.project_id,'status',new.status,'version',new.version,'quote_number',new.quote_number,
      'quote_version',new.quote_version,'total_msrp',new.total_msrp,'total_promo',new.total_promo,'total_negotiated',new.total_negotiated,
      'total_services',new.total_services,'total_tax',new.total_tax,'total_final',new.total_final,'total_savings',new.total_savings,
      'contact_id',new.contact_id,'deal_id',new.deal_id,'project_type',new.project_type,'unit_type',new.unit_type,'unit_count',new.unit_count,
      'phase',new.phase,'approval_status',new.approval_status,'sent_at',new.sent_at,'quote_expires_at',new.quote_expires_at)),
    new.created_by,coalesce(new.updated_by,(select auth.uid()),new.created_by),new.created_at,new.updated_at
  );
  v_event := case when tg_op='INSERT' then 'SpecIQPackageCreated' else 'SpecIQPackageUpdated' end;
  insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
  values(new.organization_id,v_entity,v_event,'speciq_package',new.id::text,coalesce(new.updated_by,new.created_by,(select auth.uid())),
    jsonb_build_object('title',case when tg_op='INSERT' then 'SpecIQ package created' else 'SpecIQ package updated' end,
      'summary',new.package_name,'timeline_type','package','status',new.status,'total_final',new.total_final),
    case when tg_op='INSERT' then new.created_at else new.updated_at end);

  if new.sent_at is not null or lower(coalesce(new.status,'')) in ('sent','accepted','won','sold','closed_won','rejected','lost','closed_lost','cancelled') then
    v_rec := public.intelligence_ensure_speciq_package_recommendation(new.id);
  end if;

  if tg_op='UPDATE' and old.status is distinct from new.status and v_rec is not null then
    if lower(new.status) in ('accepted','won','sold','closed_won','completed','purchased') then
      v_success:=true; v_outcome_type:='package_accepted';
    elsif lower(new.status) in ('rejected','lost','closed_lost','cancelled','expired') then
      v_success:=false; v_outcome_type:='package_not_accepted';
    else
      v_success:=null; v_outcome_type:='package_status_'||lower(new.status);
    end if;
    perform public.intelligence_record_outcome(v_rec,v_outcome_type,v_success,new.total_final,new.status,1,
      jsonb_build_object('package_id',new.id,'old_status',old.status,'new_status',new.status,'total_final',new.total_final),
      'speciq_package_status',new.id::text||':'||lower(new.status),new.updated_at);
  end if;
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_speciq_package_event() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare p public.speciq_packages%rowtype; v_rec uuid; v_success boolean; v_weight numeric; v_type text;
begin
  select * into p from public.speciq_packages where id=new.package_id;
  if p.id is null then return new; end if;
  v_rec := public.intelligence_ensure_speciq_package_recommendation(new.package_id);
  v_type := lower(new.event_type);
  v_success := case when v_type in ('accepted','purchased','sale_completed','won','converted') then true
                    when v_type in ('rejected','lost','cancelled','expired') then false else null end;
  v_weight := case
    when v_type in ('accepted','purchased','sale_completed','won','converted') then 5
    when v_type in ('rejected','lost','cancelled') then 5
    when v_type in ('downloaded','pricing_viewed','product_clicked') then 1.5
    when v_type in ('link_opened','page_viewed') then 1
    when v_type in ('sent','email_delivered') then 0.25
    else 0.5 end;
  perform public.intelligence_record_outcome(
    v_rec,'engagement_'||v_type,v_success,
    case when v_success=true then p.total_final else null end,new.event_type,v_weight,
    coalesce(new.event_data,'{}'::jsonb)||jsonb_build_object('package_id',new.package_id,'speciq_event_id',new.id),
    'speciq_package_event',new.id::text,new.created_at
  );
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_speciq_package_product() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_rec uuid; p public.speciq_packages%rowtype; v_product_entity uuid; v_action text;
begin
  if tg_op='DELETE' then
    perform public.intelligence_ensure_speciq_package_recommendation(old.package_id);
    return old;
  end if;
  select * into p from public.speciq_packages where id=new.package_id;
  if p.id is null then return new; end if;
  if new.aiq_product_id is not null then
    select id into v_product_entity from public.intelligence_entities
      where organization_id=new.organization_id and source_system='product_iq_product' and source_record_id=new.aiq_product_id::text;
  end if;
  v_action := 'include_product:'||coalesce(new.aiq_product_id::text,new.model_number,new.id::text);
  v_rec := public.intelligence_record_recommendation(
    new.organization_id,'product_selection','package',new.package_id::text,v_action,
    coalesce(nullif(new.category,''),'appliance'),v_product_entity,null,
    jsonb_strip_nulls(jsonb_build_object('package_product_id',new.id,'package_id',new.package_id,'aiq_product_id',new.aiq_product_id,
      'brand',new.brand,'model_number',new.model_number,'category',new.category,'subcategory',new.subcategory,'finish',new.finish,
      'quantity',new.quantity,'selected_price',coalesce(new.negotiated_price,new.promo_price,new.msrp),
      'source_comparison_id',new.source_comparison_id,'selection_reason',new.selection_reason,'basis',
      case when new.source_comparison_id is not null then 'comparison_selection' when new.selection_reason is not null then 'documented_selection' else 'package_selection' end)),
    '[]'::jsonb,'speciq_package_product',new.id::text
  );
  perform public.intelligence_ensure_speciq_package_recommendation(new.package_id);
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_sync_speciq_project() RETURNS trigger LANGUAGE plpgsql AS $fn$

declare v_entity uuid; v_event text;
begin
  if tg_op='DELETE' then
    select id into v_entity from public.intelligence_entities
    where organization_id=old.organization_id and source_system='speciq_project' and source_record_id=old.id::text;
    if v_entity is not null then
      update public.intelligence_entities set status='deleted',updated_at=now(),updated_by=(select auth.uid()) where id=v_entity;
      insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
      values(old.organization_id,v_entity,'SpecIQProjectDeleted','speciq_project',old.id::text,(select auth.uid()),
        jsonb_build_object('title','SpecIQ project deleted','project_name',old.project_name,'timeline_type','project'),now());
    end if;
    return old;
  end if;

  v_entity := public.intelligence_speciq_entity(
    new.organization_id,'project',new.project_name,'speciq_project',new.id::text,
    case when lower(coalesce(new.status,'active')) in ('inactive','archived','deleted') then lower(new.status) else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('customer_name',new.customer_name,'customer_email',new.customer_email,'customer_phone',new.customer_phone,
      'property_address',new.property_address,'room_name',new.room_name,'builder_name',new.builder_name,'designer_name',new.designer_name,
      'expected_purchase_date',new.expected_purchase_date,'delivery_date',new.delivery_date,'status',new.status,'contact_id',new.contact_id,'deal_id',new.deal_id)),
    new.created_by,coalesce((select auth.uid()),new.created_by),new.created_at,new.updated_at
  );
  v_event := case when tg_op='INSERT' then 'SpecIQProjectCreated' else 'SpecIQProjectUpdated' end;
  insert into public.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
  values(new.organization_id,v_entity,v_event,'speciq_project',new.id::text,coalesce((select auth.uid()),new.created_by),
    jsonb_build_object('title',case when tg_op='INSERT' then 'SpecIQ project created' else 'SpecIQ project updated' end,
      'summary',new.project_name,'timeline_type','project','status',new.status),
    case when tg_op='INSERT' then new.created_at else new.updated_at end);
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.intelligence_upsert_context(p_organization_id uuid, p_entity_id uuid, p_context_key text, p_context_data jsonb, p_source_fingerprint text DEFAULT NULL::text, p_confidence_score numeric DEFAULT NULL::numeric, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS intelligence_context_cache LANGUAGE plpgsql AS $fn$

declare v_context public.intelligence_context_cache;
begin
  insert into public.intelligence_context_cache(
    organization_id, entity_id, context_key, context_data, source_fingerprint, confidence_score, expires_at
  ) values (
    p_organization_id, p_entity_id, p_context_key, coalesce(p_context_data,'{}'::jsonb), p_source_fingerprint, p_confidence_score, p_expires_at
  )
  on conflict (organization_id, entity_id, context_key)
  do update set
    context_version = public.intelligence_context_cache.context_version + 1,
    context_data = excluded.context_data,
    source_fingerprint = excluded.source_fingerprint,
    confidence_score = excluded.confidence_score,
    expires_at = excluded.expires_at,
    generated_at = now()
  returning * into v_context;
  return v_context;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  SELECT COALESCE((SELECT is_admin FROM mfr_user_roles WHERE user_id = auth.uid()), FALSE);

$fn$;

CREATE OR REPLACE FUNCTION public.is_field_client_member(p_client_id uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER STABLE AS $fn$

BEGIN
  -- Check org membership
  IF EXISTS (
    SELECT 1 FROM field_clients fc
    JOIN organization_members om ON om.organization_id = fc.organization_id
    WHERE fc.id = p_client_id AND om.user_id = auth.uid() AND om.status = 'active'
  ) THEN RETURN true; END IF;
  
  -- Check manufacturer user (direct table access, bypasses RLS since SECURITY DEFINER)
  IF EXISTS (
    SELECT 1 FROM field_manufacturer_users fmu
    WHERE fmu.client_id = p_client_id AND fmu.user_id = auth.uid() AND fmu.status = 'active'
  ) THEN RETURN true; END IF;
  
  RETURN false;
END;

$fn$;

CREATE OR REPLACE FUNCTION public.is_field_rep() RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  SELECT EXISTS (
    SELECT 1 FROM organization_members om
    WHERE om.user_id = auth.uid() AND om.status = 'active'
  );

$fn$;

CREATE OR REPLACE FUNCTION public.is_org_admin(p_org uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  SELECT EXISTS (
    SELECT 1 FROM public.organization_members m
    WHERE m.organization_id = p_org
      AND m.user_id = auth.uid()
      AND m.status = 'active'
      AND m.role IN ('admin','owner')
  );

$fn$;

CREATE OR REPLACE FUNCTION public.is_org_member(p_org uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  select exists (select 1 from public.organization_members m
    where m.organization_id = p_org and m.user_id = auth.uid() and m.status = 'active');

$fn$;

CREATE OR REPLACE FUNCTION public.is_super_admin() RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  select false;

$fn$;

CREATE OR REPLACE FUNCTION public.join_demo_org() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare v_user uuid := auth.uid(); v_demo uuid := '00000000-0000-0000-0000-000000000002';
begin
  if v_user is null then raise exception 'Authentication required.'; end if;
  insert into public.profiles (user_id, email)
  select v_user, (select email from auth.users where id = v_user)
  on conflict (user_id) do nothing;
  insert into public.organization_members (organization_id, user_id, role, status)
  values (v_demo, v_user, 'member', 'active')
  on conflict (organization_id, user_id) do update set status = 'active';
  return jsonb_build_object('joined', true, 'organization_id', v_demo);
end 
$fn$;

CREATE OR REPLACE FUNCTION public.list_available_assistants(p_organization_id uuid) RETURNS SETOF ai_assistants LANGUAGE sql STABLE AS $fn$

  select * from public.ai_assistants
   where status = 'active'
     and (organization_id is null or organization_id = p_organization_id)
   order by category, label;

$fn$;

CREATE OR REPLACE FUNCTION public.list_pending_embeddings(p_batch_size integer DEFAULT 50) RETURNS TABLE(table_name text, row_id uuid, source_text text, source_hash text) LANGUAGE sql SECURITY DEFINER AS $fn$

  (select 'ai_knowledge_chunks'::text, c.id,
          coalesce(c.title,'') || E'\n' || c.content,
          md5(coalesce(c.title,'') || c.content)
     from public.ai_knowledge_chunks c
    where c.status = 'active'
      and (c.embedding is null or c.source_hash is distinct from md5(coalesce(c.title,'') || c.content))
    limit p_batch_size)
  union all
  (select 'products'::text, p.id,
          p.brand || ' ' || p.model || ' ' || p.name || ' ' || coalesce(p.category,'') || E'\n' || coalesce(p.description,''),
          md5(p.brand || p.model || p.name || coalesce(p.category,'') || coalesce(p.description,''))
     from public.products p
    where p.embedding is null
       or p.source_hash is distinct from md5(p.brand || p.model || p.name || coalesce(p.category,'') || coalesce(p.description,''))
    limit p_batch_size)
  limit p_batch_size;

$fn$;

CREATE OR REPLACE FUNCTION public.log_coaching_kpi() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$

begin
  if new.review_kind = 'coaching' then
    insert into kpi_events (organization_id, event_type, ref_table, ref_id, metadata)
    values (new.organization_id, 'coaching_generated', 'ai_coaching_reviews', new.id,
            jsonb_build_object('overall_score', new.overall_score));
  end if;
  return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.log_recording_kpi() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$

begin
  if tg_op = 'INSERT' then
    insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id, metadata)
    values (new.organization_id, new.user_id, 'recording_uploaded', 'sales_recordings', new.id,
            jsonb_build_object('source', new.recording_source, 'duration_seconds', new.duration_seconds));
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'transcribed' then
      insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id)
      values (new.organization_id, new.user_id, 'recording_transcribed', 'sales_recordings', new.id);
    elsif new.status = 'complete' then
      insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id)
      values (new.organization_id, new.user_id, 'recording_analyzed', 'sales_recordings', new.id);
    end if;
  end if;
  return new;
end 
$fn$;

CREATE OR REPLACE FUNCTION public.manages_vendor(v uuid) RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  SELECT EXISTS(SELECT 1 FROM mfr_members WHERE user_id = auth.uid() AND vendor_id = v);

$fn$;

CREATE OR REPLACE FUNCTION public.match_products(p_organization_id uuid, p_query_embedding vector, p_limit integer DEFAULT 10) RETURNS TABLE(product_id uuid, brand text, model text, name text, category text, msrp numeric, similarity double precision) LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  select p.id, p.brand, p.model, p.name, p.category, p.msrp,
         1 - (p.embedding operator(public.<=>) p_query_embedding) as similarity
    from public.products p
   where p.organization_id = p_organization_id
     and p.embedding is not null
     and (
       (select auth.role()) = 'service_role'
       or public.is_org_member(p_organization_id)
     )
   order by p.embedding operator(public.<=>) p_query_embedding
   limit p_limit;

$fn$;

CREATE OR REPLACE FUNCTION public.mfr_portal_snapshot(p_vendor_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $fn$

with vendor as (select * from public.mfr_vendors where id=p_vendor_id),
brand_ids as (select distinct coalesce(s.brand_id,v.brand_id) brand_id from vendor v left join public.product_iq_brand_scopes s on s.vendor_id=v.id and s.status='active' where coalesce(s.brand_id,v.brand_id) is not null),
products as (select p.* from public.aiq_products p where p.brand_id in (select brand_id from brand_ids))
select jsonb_build_object(
 'generated_at',now(),'vendor',(select to_jsonb(v) from vendor v),
 'members',(select count(*) from public.mfr_members where vendor_id=p_vendor_id and coalesce(status,'active')='active'),
 'brand_scopes',(select count(*) from public.product_iq_brand_scopes where vendor_id=p_vendor_id and status='active'),
 'products',jsonb_build_object('total',(select count(*) from products),'approved',(select count(*) from products where approval_status='approved'),'pending_review',(select count(*) from products where source_review_status in ('pending','needs_review') or approval_status<>'approved'),'public',(select count(*) from products where public_visible)),
 'assets',jsonb_build_object('documents',(select count(*) from public.pim_product_documents d where d.product_id in (select id from products)),'verified_documents',(select count(*) from public.pim_product_documents d where d.product_id in (select id from products) and d.manufacturer_verified),'images',(select count(*) from public.pim_product_images i where i.product_id in (select id from products)),'videos',(select count(*) from public.pim_product_videos v where v.product_id in (select id from products)))
); 
$fn$;

CREATE OR REPLACE FUNCTION public.my_org_ids() RETURNS SETOF uuid LANGUAGE sql SECURITY DEFINER STABLE AS $fn$

  SELECT organization_id FROM public.organization_members
  WHERE user_id = auth.uid() AND status = 'active';

$fn$;

CREATE OR REPLACE FUNCTION public.normalize_aicrm_import_signature(p_company text, p_province text, p_city text) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$

  select regexp_replace(lower(trim(coalesce(p_company, '')) || '|' || lower(trim(coalesce(p_province, ''))) || '|' || lower(trim(coalesce(p_city, '')))), '\\s+', ' ', 'g');

$fn$;

CREATE OR REPLACE FUNCTION public.piq_confirm_invited_email(p_code text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $fn$

DECLARE inv record;
BEGIN
  SELECT * INTO inv FROM mfr_invites WHERE upper(code) = upper(trim(p_code));
  IF NOT FOUND THEN RETURN false; END IF;
  IF inv.status <> 'pending' THEN RETURN false; END IF;
  IF inv.expires_at IS NOT NULL AND inv.expires_at < now() THEN RETURN false; END IF;

  UPDATE auth.users
     SET email_confirmed_at = now(), updated_at = now()
   WHERE lower(email) = lower(inv.email)
     AND email_confirmed_at IS NULL;
  RETURN true;
END 
$fn$;

CREATE OR REPLACE FUNCTION public.piq_create_invite(p_email text, p_persona text, p_vendor_id uuid DEFAULT NULL::uuid, p_role text DEFAULT 'product_editor'::text, p_group_id uuid DEFAULT NULL::uuid, p_retailer_brand_ids uuid[] DEFAULT '{}'::uuid[], p_retailer_account_type text DEFAULT 'independent'::text, p_retailer_company text DEFAULT NULL::text, p_retailer_exclusive_codes text[] DEFAULT '{}'::text[]) RETURNS TABLE(id uuid, code text, email text, persona text, scope_name text, scope_type text) LANGUAGE plpgsql SECURITY DEFINER AS $fn$

DECLARE v_code text; v_name text; v_scope text; v_id uuid; v_slug text;
BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can create invites'; END IF;
  IF p_persona NOT IN ('manufacturer','retailer') THEN
    RAISE EXCEPTION 'persona must be manufacturer or retailer'; END IF;

  IF p_persona = 'retailer' THEN
    IF COALESCE(array_length(p_retailer_brand_ids,1),0) = 0 THEN
      RAISE EXCEPTION 'Select at least one brand this retailer carries';
    END IF;
    v_scope := 'retailer';
    v_name  := COALESCE(p_retailer_company,'Retailer')||' — '||array_length(p_retailer_brand_ids,1)||' brands';
  ELSIF p_group_id IS NOT NULL THEN
    v_scope := 'group';
    SELECT g.name INTO v_name FROM mfr_vendor_groups g WHERE g.id=p_group_id;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Ownership group not found'; END IF;
  ELSIF p_vendor_id IS NOT NULL THEN
    v_scope := 'brand';
    SELECT v.name, v.slug INTO v_name, v_slug FROM mfr_vendors v WHERE v.id=p_vendor_id;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Brand not found'; END IF;
  ELSE
    RAISE EXCEPTION 'A manufacturer invite requires a brand or an ownership group';
  END IF;

  LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM mfr_invites i WHERE i.code=v_code);
  END LOOP;

  INSERT INTO mfr_invites (email, vendor_id, group_id, scope_type, vendor_name, vendor_slug,
      invite_role, persona, code, status, invited_by, created_at, expires_at,
      retailer_brand_ids, retailer_account_type, retailer_company, retailer_exclusive_codes)
  VALUES (lower(trim(p_email)), p_vendor_id, p_group_id, v_scope, v_name, v_slug,
      p_role, p_persona, v_code, 'pending', auth.uid(), now(), now()+interval '30 days',
      COALESCE(p_retailer_brand_ids,'{}'), p_retailer_account_type, p_retailer_company,
      COALESCE(p_retailer_exclusive_codes,'{}'))
  RETURNING mfr_invites.id INTO v_id;

  RETURN QUERY SELECT v_id, v_code, lower(trim(p_email)), p_persona, v_name, v_scope;
END 
$fn$;

CREATE OR REPLACE FUNCTION public.piq_mark_read(p_ids uuid[]) RETURNS void LANGUAGE sql SECURITY DEFINER AS $fn$

  INSERT INTO piq_notification_reads (notification_id, user_id)
  SELECT unnest(p_ids), auth.uid()
  ON CONFLICT DO NOTHING;

$fn$;

CREATE OR REPLACE FUNCTION public.piq_notify_new_asset() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $fn$

DECLARE
  r jsonb := to_jsonb(NEW);
  v_brand text; v_kind text; v_title text; v_body text;
  v_prod uuid; v_when timestamptz; v_until timestamptz;
BEGIN
  -- Never announce embargoed material
  IF COALESCE((r->>'embargoed')::boolean,false) THEN RETURN NEW; END IF;
  -- On UPDATE, only fire when embargo is being lifted
  IF TG_OP='UPDATE' AND COALESCE((to_jsonb(OLD)->>'embargoed')::boolean,false) = false THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM piq_notifications n
             WHERE n.asset_table=TG_TABLE_NAME AND n.asset_id=(r->>'id')::uuid) THEN
    RETURN NEW;
  END IF;

  v_prod := NULLIF(r->>'product_id','')::uuid;
  IF v_prod IS NOT NULL THEN
    SELECT p.brand_name INTO v_brand FROM aiq_products p WHERE p.id = v_prod;
  END IF;

  IF TG_TABLE_NAME = 'pim_product_documents' THEN
    v_kind := CASE WHEN r->>'doc_type' IN ('spec_sheet','sell_sheet','comparison_chart')
                   THEN 'price_sheet' ELSE 'new_document' END;
    v_title := COALESCE(r->>'title','New document');
    v_body  := 'New '||replace(COALESCE(r->>'doc_type','document'),'_',' ')||' available'||COALESCE(' for '||v_brand,'');
  ELSIF TG_TABLE_NAME = 'pim_marketing_assets' THEN
    v_kind := 'new_marketing'; v_title := COALESCE(r->>'title','New marketing asset');
    v_body  := 'New '||replace(COALESCE(r->>'asset_type','asset'),'_',' ')||' available';
  ELSIF TG_TABLE_NAME = 'pim_product_videos' THEN
    v_kind := 'video'; v_title := COALESCE(r->>'title','New video');
    v_body  := 'New '||replace(COALESCE(r->>'video_type','video'),'_',' ')||' available';
  ELSIF TG_TABLE_NAME = 'pim_product_rebates' THEN
    v_kind := 'rebate'; v_title := COALESCE(r->>'rebate_name','New promotion');
    v_body  := 'Promotion running'||COALESCE(' for '||v_brand,'');
  ELSIF TG_TABLE_NAME = 'pim_product_images' THEN
    IF COALESCE((r->>'is_primary')::boolean,false) = false THEN RETURN NEW; END IF;
    v_kind := 'image'; v_title := COALESCE(v_brand,'Product')||' imagery updated';
    v_body  := 'New primary product image available';
  ELSE RETURN NEW; END IF;

  v_when  := COALESCE(NULLIF(r->>'available_from','')::timestamptz, now());
  v_until := NULLIF(r->>'available_until','')::timestamptz;

  INSERT INTO piq_notifications (kind,title,body,brand_name,product_id,asset_table,asset_id,
                                 link_url,audience_tiers,exclusive_codes,publish_at,expires_at,created_by)
  VALUES (v_kind, v_title, v_body, v_brand, v_prod, TG_TABLE_NAME, (r->>'id')::uuid,
          COALESCE(r->>'file_url', r->>'rebate_form_url', r->>'embed_url'),
          COALESCE((SELECT array_agg(x) FROM jsonb_array_elements_text(r->'audience_tiers') x), ARRAY['all']),
          COALESCE((SELECT array_agg(x) FROM jsonb_array_elements_text(r->'exclusive_codes') x), '{}'),
          v_when, v_until, auth.uid());
  RETURN NEW;
END 
$fn$;

CREATE OR REPLACE FUNCTION public.piq_preview_invite(p_code text) RETURNS TABLE(email text, persona text, vendor_name text, invite_role text, scope_type text, brand_count integer, valid boolean) LANGUAGE sql SECURITY DEFINER AS $fn$

  SELECT i.email, i.persona, i.vendor_name, i.invite_role, i.scope_type,
    CASE WHEN i.scope_type='group'
         THEN (SELECT count(*)::int FROM mfr_vendors v WHERE v.group_id=i.group_id)
         WHEN i.scope_type='brand' THEN 1 ELSE 0 END,
    (i.status='pending' AND (i.expires_at IS NULL OR i.expires_at > now()))
  FROM mfr_invites i WHERE upper(i.code) = upper(trim(p_code));

$fn$;

CREATE OR REPLACE FUNCTION public.piq_redeem_invite(p_code text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $fn$

DECLARE inv record; v_uid uuid := auth.uid(); v_email text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'You must be signed in to accept an invite'; END IF;
  SELECT lower(email) INTO v_email FROM auth.users WHERE id=v_uid;
  SELECT * INTO inv FROM mfr_invites WHERE upper(code)=upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invite code not found'; END IF;
  IF inv.status <> 'pending' THEN RAISE EXCEPTION 'This invite has already been used'; END IF;
  IF inv.expires_at IS NOT NULL AND inv.expires_at < now() THEN
    RAISE EXCEPTION 'This invite has expired'; END IF;
  IF lower(inv.email) <> v_email THEN
    RAISE EXCEPTION 'This invite was issued to %, but you are signed in as %', inv.email, v_email; END IF;

  IF inv.persona = 'manufacturer' THEN
    IF inv.scope_type='group' THEN
      INSERT INTO mfr_members (user_id,vendor_id,role,member_role,status,approved_by,approved_at,activated_at,invited_by,invitation_id)
      SELECT v_uid, v.id, inv.invite_role, inv.invite_role,'active',COALESCE(inv.invited_by,v_uid),now(),now(),inv.invited_by,inv.id
      FROM mfr_vendors v WHERE v.group_id=inv.group_id ON CONFLICT DO NOTHING;
    ELSE
      INSERT INTO mfr_members (user_id,vendor_id,role,member_role,status,approved_by,approved_at,activated_at,invited_by,invitation_id)
      VALUES (v_uid, inv.vendor_id, inv.invite_role, inv.invite_role,'active',COALESCE(inv.invited_by,v_uid),now(),now(),inv.invited_by,inv.id)
      ON CONFLICT DO NOTHING;
    END IF;
    INSERT INTO mfr_user_roles (user_id,is_admin,is_manufacturer,is_retailer)
    VALUES (v_uid,false,true,false) ON CONFLICT (user_id) DO UPDATE SET is_manufacturer=true;
  ELSE
    INSERT INTO piq_retailer_profiles (user_id, company_name, account_type, exclusive_codes, updated_at)
    VALUES (v_uid, inv.retailer_company, COALESCE(inv.retailer_account_type,'independent'),
            COALESCE(inv.retailer_exclusive_codes,'{}'), now())
    ON CONFLICT (user_id) DO UPDATE
      SET company_name=EXCLUDED.company_name, account_type=EXCLUDED.account_type,
          exclusive_codes=EXCLUDED.exclusive_codes, updated_at=now();

    INSERT INTO piq_retailer_brands (user_id, brand_id, granted_by)
    SELECT v_uid, unnest(COALESCE(inv.retailer_brand_ids,'{}')), inv.invited_by
    ON CONFLICT DO NOTHING;

    INSERT INTO mfr_user_roles (user_id,is_admin,is_manufacturer,is_retailer)
    VALUES (v_uid,false,false,true) ON CONFLICT (user_id) DO UPDATE SET is_retailer=true;
  END IF;

  UPDATE mfr_invites SET status='accepted', accepted_at=now(), accepted_by=v_uid WHERE id=inv.id;
  RETURN COALESCE(inv.vendor_name,'Retailer access');
END 
$fn$;

CREATE OR REPLACE FUNCTION public.piq_revoke_invite(p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can revoke invites';
  END IF;
  UPDATE mfr_invites SET status='revoked' WHERE id=p_id AND status='pending';
END 
$fn$;

CREATE OR REPLACE FUNCTION public.piq_save_retailer(p_user_id uuid, p_company text, p_account_type text, p_brand_ids uuid[], p_buying_group text DEFAULT NULL::text, p_exclusive_codes text[] DEFAULT '{}'::text[], p_region text DEFAULT NULL::text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can configure retailers';
  END IF;
  IF p_account_type NOT IN ('national','independent','buying_group','builder','designer') THEN
    RAISE EXCEPTION 'Invalid account type: %', p_account_type;
  END IF;

  INSERT INTO piq_retailer_profiles (user_id, company_name, account_type, buying_group, exclusive_codes, region, updated_at)
  VALUES (p_user_id, p_company, p_account_type, p_buying_group, COALESCE(p_exclusive_codes,'{}'), p_region, now())
  ON CONFLICT (user_id) DO UPDATE
    SET company_name=EXCLUDED.company_name, account_type=EXCLUDED.account_type,
        buying_group=EXCLUDED.buying_group, exclusive_codes=EXCLUDED.exclusive_codes,
        region=EXCLUDED.region, updated_at=now();

  INSERT INTO mfr_user_roles (user_id, is_admin, is_manufacturer, is_retailer)
  VALUES (p_user_id,false,false,true)
  ON CONFLICT (user_id) DO UPDATE SET is_retailer = true;

  DELETE FROM piq_retailer_brands WHERE user_id = p_user_id
    AND (p_brand_ids IS NULL OR NOT (brand_id = ANY(p_brand_ids)));

  IF p_brand_ids IS NOT NULL AND array_length(p_brand_ids,1) > 0 THEN
    INSERT INTO piq_retailer_brands (user_id, brand_id, granted_by)
    SELECT p_user_id, unnest(p_brand_ids), auth.uid()
    ON CONFLICT DO NOTHING;
  END IF;
END 
$fn$;

CREATE OR REPLACE FUNCTION public.piq_set_brand_access(p_user_id uuid, p_vendor_id uuid, p_role text DEFAULT 'product_editor'::text, p_grant boolean DEFAULT true) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can change brand access';
  END IF;
  IF p_grant THEN
    INSERT INTO mfr_members (user_id, vendor_id, role, member_role, status,
                             approved_by, approved_at, activated_at)
    VALUES (p_user_id, p_vendor_id, p_role, p_role, 'active', auth.uid(), now(), now())
    ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM mfr_members WHERE user_id=p_user_id AND vendor_id=p_vendor_id;
  END IF;
END 
$fn$;

CREATE OR REPLACE FUNCTION public.product_iq_guard_product_governance() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  -- Allow anon/unauthenticated (PIM scraper) to bypass governance
  if nullif(current_setting('request.jwt.claim.sub', true), '') is null then
    return new;
  end if;

  if tg_op = 'INSERT' and not (select private.product_iq_can_publish_product()) then
    if new.approval_status <> 'draft' or new.public_visible is distinct from false then
      raise exception 'Product IQ: non-platform users may only create unpublished drafts';
    end if;
  end if;
  if tg_op = 'UPDATE' and not (select private.product_iq_can_publish_product()) then
    if new.approval_status is distinct from old.approval_status
       or new.public_visible is distinct from old.public_visible then
      raise exception 'Product IQ: approval and publication fields require a platform reviewer';
    end if;
  end if;
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.provision_aicrm_defaults_for_organization(p_organization_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  v_business_unit_id uuid;
  v_brand_fotile uuid;
  v_brand_dreame uuid;
  v_brand_mobila uuid;
  v_brand_nobilia uuid;
  v_channel_id uuid;
  v_motion_id uuid;
  v_category_id uuid;
  v_campaign_type_id uuid;
  v_default_profile_id uuid;
begin
  if p_organization_id is null then
    return;
  end if;

  insert into public.aicrm_organization_settings (
    organization_id,
    organization_profile,
    industry,
    country,
    currency,
    timezone,
    language,
    ai_enabled,
    default_territory,
    branding
  )
  values (
    p_organization_id,
    jsonb_build_object(
      'template', 'ApplianceIQ',
      'name', 'Default'
    ),
    'Channel Development',
    'CA',
    'CAD',
    'America/Toronto',
    'en',
    true,
    'North America',
    jsonb_build_object(
      'theme', 'elev8-dark',
      'accent', 'gold',
      'template', 'applianceiq-default'
    )
  )
  on conflict (organization_id) do update
    set organization_profile = excluded.organization_profile,
        industry = excluded.industry,
        country = excluded.country,
        currency = excluded.currency,
        timezone = excluded.timezone,
        language = excluded.language,
        ai_enabled = excluded.ai_enabled,
        default_territory = excluded.default_territory,
        branding = excluded.branding,
        updated_at = now();

  insert into public.aicrm_business_units (
    organization_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, 'ApplianceIQ', 'Default appliance and channel intelligence business unit.', true, 1)
  on conflict (organization_id, lower(trim(name))) do update
    set description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_business_unit_id
  from public.aicrm_business_units
  where organization_id = p_organization_id
    and lower(trim(name)) = lower(trim('ApplianceIQ'))
  limit 1;

  update public.aicrm_organization_settings
     set default_business_unit_id = v_business_unit_id,
         updated_at = now()
   where organization_id = p_organization_id;

  insert into public.aicrm_brands (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Fotile', 'Default Fotile brand configuration.', true, 1),
    (p_organization_id, v_business_unit_id, 'Dreame', 'Default Dreame brand configuration.', true, 2),
    (p_organization_id, v_business_unit_id, 'Mobila', 'Default Mobila brand configuration.', true, 3),
    (p_organization_id, v_business_unit_id, 'Nobilia', 'Default Nobilia brand configuration.', true, 4)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_brand_fotile
  from public.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Fotile'))
  limit 1;

  select id into v_brand_dreame
  from public.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Dreame'))
  limit 1;

  select id into v_brand_mobila
  from public.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Mobila'))
  limit 1;

  select id into v_brand_nobilia
  from public.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Nobilia'))
  limit 1;

  insert into public.aicrm_products (
    organization_id,
    business_unit_id,
    brand_id,
    name,
    brand,
    category,
    description,
    active,
    archived_at
  )
  values
    (p_organization_id, v_business_unit_id, v_brand_fotile, 'Fotile', 'Fotile', 'Kitchen Appliances', 'Premium kitchen ventilation and cooking appliances.', true, null),
    (p_organization_id, v_business_unit_id, v_brand_dreame, 'Dreame', 'Dreame', 'Smart Home Appliances', 'Smart cleaning, cordless vacuums, and robotics.', true, null),
    (p_organization_id, v_business_unit_id, v_brand_mobila, 'Mobila', 'Mobila', 'Cabinetry', 'Kitchen and bath cabinetry program for channel partners.', true, null),
    (p_organization_id, v_business_unit_id, v_brand_nobilia, 'Nobilia', 'Nobilia', 'Cabinetry', 'Premium German kitchen and storage cabinetry.', true, null)
  on conflict (organization_id, name) do update
    set business_unit_id = excluded.business_unit_id,
        brand_id = excluded.brand_id,
        brand = excluded.brand,
        category = excluded.category,
        description = excluded.description,
        active = true,
        archived_at = null,
        updated_at = now();

  insert into public.aicrm_channels (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Appliance Dealer', 'Default channel segmentation for appliance dealer partners.', true, 1),
    (p_organization_id, v_business_unit_id, 'Kitchen & Bath', 'Default channel segmentation for kitchen and bath showrooms.', true, 2),
    (p_organization_id, v_business_unit_id, 'Cabinet Dealer', 'Default channel segmentation for cabinet dealer partners.', true, 3),
    (p_organization_id, v_business_unit_id, 'Builder - Single Family', 'Default builder channel segmentation for single-family programs.', true, 4),
    (p_organization_id, v_business_unit_id, 'Builder - Multi Family', 'Default builder channel segmentation for multi-family programs.', true, 5),
    (p_organization_id, v_business_unit_id, 'Architect', 'Default architect channel segmentation.', true, 6),
    (p_organization_id, v_business_unit_id, 'Interior Designer', 'Default interior designer channel segmentation.', true, 7),
    (p_organization_id, v_business_unit_id, 'Developer', 'Default property developer channel segmentation.', true, 8),
    (p_organization_id, v_business_unit_id, 'Distributor', 'Default distributor channel segmentation.', true, 9),
    (p_organization_id, v_business_unit_id, 'National Retailer', 'Default national retailer channel segmentation.', true, 10),
    (p_organization_id, v_business_unit_id, 'Buying Group', 'Default buying group channel segmentation.', true, 11)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  insert into public.aicrm_sales_motions (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Builder Program', 'Default builder-focused sales motion.', true, 1),
    (p_organization_id, v_business_unit_id, 'Dealer Program', 'Default dealer-focused sales motion.', true, 2),
    (p_organization_id, v_business_unit_id, 'Specification Program', 'Default specification-led sales motion.', true, 3),
    (p_organization_id, v_business_unit_id, 'Commercial Program', 'Default commercial sales motion.', true, 4),
    (p_organization_id, v_business_unit_id, 'National Accounts', 'Default national accounts sales motion.', true, 5),
    (p_organization_id, v_business_unit_id, 'Government', 'Default public sector and government sales motion.', true, 6)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  insert into public.aicrm_campaign_categories (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Channel Development', 'Default category for channel development campaigns.', true, 1),
    (p_organization_id, v_business_unit_id, 'Account Development', 'Default category for account development campaigns.', true, 2),
    (p_organization_id, v_business_unit_id, 'Activation', 'Default category for activation campaigns.', true, 3),
    (p_organization_id, v_business_unit_id, 'Retention', 'Default category for retention campaigns.', true, 4)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_category_id
  from public.aicrm_campaign_categories
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Channel Development'))
  limit 1;

  select id into v_channel_id
  from public.aicrm_channels
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Appliance Dealer'))
  limit 1;

  select id into v_motion_id
  from public.aicrm_sales_motions
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Dealer Program'))
  limit 1;

  insert into public.aicrm_campaign_types (
    organization_id,
    business_unit_id,
    campaign_category_id,
    channel_id,
    sales_motion_id,
    name,
    description,
    active,
    display_order,
    default_sequence
  )
  values
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Appliance Dealer', 'Default appliance dealer campaign type.', true, 1, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Kitchen & Bath', 'Default kitchen and bath campaign type.', true, 2, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Cabinet Dealer', 'Default cabinet dealer campaign type.', true, 3, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Builder - Single Family', 'Default single family builder campaign type.', true, 4, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Builder - Multi Family', 'Default multi family builder campaign type.', true, 5, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Architect', 'Default architect campaign type.', true, 6, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Interior Designer', 'Default interior designer campaign type.', true, 7, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Developer', 'Default developer campaign type.', true, 8, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Distributor', 'Default distributor campaign type.', true, 9, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'National Retailer', 'Default national retailer campaign type.', true, 10, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Buying Group', 'Default buying group campaign type.', true, 11, '[]'::jsonb)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        campaign_category_id = excluded.campaign_category_id,
        channel_id = excluded.channel_id,
        sales_motion_id = excluded.sales_motion_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_campaign_type_id
  from public.aicrm_campaign_types
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Appliance Dealer'))
  limit 1;

  insert into public.aicrm_campaign_sequences (
    organization_id,
    campaign_type_id,
    name,
    description,
    active,
    is_default,
    steps
  )
  values
    (
      p_organization_id,
      v_campaign_type_id,
      'Default Outreach Sequence',
      'Default sequence shell for the configured campaign type.',
      true,
      true,
      jsonb_build_array(
        jsonb_build_object('step_number', 1, 'delay_days', 0, 'channel', 'email', 'subject_template', 'Intro to {{company_name}}', 'body_template', 'Hi {{contact_first_name}},', 'purpose', 'intro', 'requires_manual_approval', true),
        jsonb_build_object('step_number', 2, 'delay_days', 3, 'channel', 'task', 'subject_template', null, 'body_template', 'Follow up with {{company_name}}', 'purpose', 'follow_up', 'requires_manual_approval', true)
      )
    )
  on conflict (organization_id, campaign_type_id, lower(trim(name))) do update
    set description = excluded.description,
        active = true,
        is_default = true,
        steps = excluded.steps,
        updated_at = now();

  insert into public.aicrm_kpis (
    organization_id,
    business_unit_id,
    name,
    kpi_key,
    kpi_category,
    kpi_type,
    description,
    target_value,
    formula,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Total Accounts', 'total_accounts', 'operational', 'numeric', 'Total number of accounts in the organization.', null, '{}'::jsonb, true, 1),
    (p_organization_id, v_business_unit_id, 'Total Contacts', 'total_contacts', 'operational', 'numeric', 'Total number of contacts in the organization.', null, '{}'::jsonb, true, 2),
    (p_organization_id, v_business_unit_id, 'Total Opportunities', 'total_opportunities', 'sales', 'numeric', 'Total number of opportunities in the organization.', null, '{}'::jsonb, true, 3),
    (p_organization_id, v_business_unit_id, 'Total Pipeline Value', 'total_pipeline_value', 'sales', 'currency', 'Gross pipeline value.', null, '{}'::jsonb, true, 4),
    (p_organization_id, v_business_unit_id, 'Weighted Pipeline Value', 'weighted_pipeline_value', 'sales', 'currency', 'Probability weighted pipeline value.', null, '{}'::jsonb, true, 5),
    (p_organization_id, v_business_unit_id, 'Open Tasks', 'open_tasks', 'operational', 'numeric', 'Open task count.', null, '{}'::jsonb, true, 6),
    (p_organization_id, v_business_unit_id, 'Overdue Tasks', 'overdue_tasks', 'operational', 'numeric', 'Overdue task count.', null, '{}'::jsonb, true, 7),
    (p_organization_id, v_business_unit_id, 'Average Account Completeness', 'average_account_completeness', 'coaching', 'percentage', 'Average account completeness across the organization.', 100, '{}'::jsonb, true, 8),
    (p_organization_id, v_business_unit_id, 'Average Contact Completeness', 'average_contact_completeness', 'coaching', 'percentage', 'Average contact completeness across the organization.', 100, '{}'::jsonb, true, 9),
    (p_organization_id, v_business_unit_id, 'Accounts Missing Revenue', 'accounts_missing_revenue', 'operational', 'numeric', 'Accounts with missing revenue context.', null, '{}'::jsonb, true, 10),
    (p_organization_id, v_business_unit_id, 'Accounts Missing Website', 'accounts_missing_website', 'operational', 'numeric', 'Accounts with missing website context.', null, '{}'::jsonb, true, 11),
    (p_organization_id, v_business_unit_id, 'Accounts Missing Product Fit', 'accounts_missing_product_fit', 'operational', 'numeric', 'Accounts missing product fit context.', null, '{}'::jsonb, true, 12),
    (p_organization_id, v_business_unit_id, 'Total Audit Events', 'total_audit_events', 'ai', 'numeric', 'Total audit log events.', null, '{}'::jsonb, true, 13)
  on conflict (organization_id, lower(trim(kpi_key))) do update
    set business_unit_id = excluded.business_unit_id,
        name = excluded.name,
        kpi_category = excluded.kpi_category,
        kpi_type = excluded.kpi_type,
        description = excluded.description,
        target_value = excluded.target_value,
        formula = excluded.formula,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  insert into public.aicrm_ai_profiles (
    organization_id,
    business_unit_id,
    brand_id,
    name,
    industry,
    preferred_channels,
    preferred_products,
    preferred_brands,
    buyer_types,
    sales_language,
    outreach_style,
    prompt_profile,
    active,
    is_default
  )
  values
    (
      p_organization_id,
      v_business_unit_id,
      null,
      'Default ApplianceIQ',
      'Channel Development',
      to_jsonb(array['Appliance Dealer', 'Kitchen & Bath', 'Cabinet Dealer', 'Builder - Single Family', 'Builder - Multi Family', 'Architect', 'Interior Designer', 'Developer', 'Distributor', 'National Retailer', 'Buying Group']),
      to_jsonb(array['Fotile', 'Dreame', 'Mobila', 'Nobilia']),
      to_jsonb(array['Fotile', 'Dreame', 'Mobila', 'Nobilia']),
      to_jsonb(array['Retailer', 'Builder', 'Designer', 'Architect', 'Developer', 'Distributor']),
      'Direct, concise, channel-aware',
      'Executive and action-oriented',
      jsonb_build_object(
        'system_prompt', 'Use organization configuration, product fit, and platform KPIs when generating recommendations.',
        'prompt_version', 'platform-config-default'
      ),
      true,
      true
    )
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        brand_id = excluded.brand_id,
        industry = excluded.industry,
        preferred_channels = excluded.preferred_channels,
        preferred_products = excluded.preferred_products,
        preferred_brands = excluded.preferred_brands,
        buyer_types = excluded.buyer_types,
        sales_language = excluded.sales_language,
        outreach_style = excluded.outreach_style,
        prompt_profile = excluded.prompt_profile,
        active = true,
        is_default = true,
        updated_at = now();

  update public.aicrm_products
     set business_unit_id = v_business_unit_id,
         updated_at = now()
   where organization_id = p_organization_id
     and lower(trim(name)) in (lower(trim('Fotile')), lower(trim('Dreame')), lower(trim('Mobila')), lower(trim('Nobilia')));
end;

$fn$;

CREATE OR REPLACE FUNCTION public.provision_aicrm_market_defaults_for_organization(p_organization_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  v_watchlist_name text;
  v_provider text;
begin
  if p_organization_id is null then
    return;
  end if;

  for v_watchlist_name in
    select *
    from unnest(array[
      'Builders',
      'Designers',
      'Appliance Dealers',
      'Buying Groups',
      'Kitchen & Bath',
      'Retailers',
      'Architects'
    ])
  loop
    insert into public.aicrm_market_watchlists (
      organization_id,
      name,
      industry,
      channel,
      keywords,
      products_followed,
      active
    )
    values (
      p_organization_id,
      v_watchlist_name,
      case
        when v_watchlist_name = 'Builders' then 'Building / Development'
        when v_watchlist_name = 'Designers' then 'Design'
        when v_watchlist_name = 'Appliance Dealers' then 'Retail'
        when v_watchlist_name = 'Buying Groups' then 'Retail'
        when v_watchlist_name = 'Kitchen & Bath' then 'Kitchen & Bath'
        when v_watchlist_name = 'Retailers' then 'Retail'
        else 'Architecture'
      end,
      v_watchlist_name,
      to_jsonb(array[lower(v_watchlist_name)]),
      '[]'::jsonb,
      true
    )
    on conflict (organization_id, lower(trim(name))) do update
      set industry = excluded.industry,
          channel = excluded.channel,
          keywords = excluded.keywords,
          active = true,
          updated_at = now();
  end loop;

  for v_provider in
    select *
    from unnest(array[
      'google_places',
      'linkedin',
      'apollo',
      'zoominfo',
      'crunchbase',
      'companies_house',
      'canadian_corporations',
      'news_api'
    ])
  loop
    insert into public.aicrm_market_connectors (
      organization_id,
      provider,
      display_name,
      active,
      status,
      config
    )
    values (
      p_organization_id,
      v_provider,
      initcap(replace(v_provider, '_', ' ')),
      false,
      'disabled',
      '{}'::jsonb
    )
    on conflict (organization_id, lower(trim(provider))) do update
      set display_name = excluded.display_name,
          updated_at = now();
  end loop;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.provision_aicrm_product_catalog_for_organization(p_organization_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

begin
  if p_organization_id is null then
    return;
  end if;

  insert into public.aicrm_products (
    organization_id,
    name,
    brand,
    category,
    description,
    active
  )
  values
    (p_organization_id, 'Fotile', 'Fotile', 'Kitchen Appliances', 'Premium kitchen ventilation and cooking appliances.', true),
    (p_organization_id, 'Dreame', 'Dreame', 'Smart Home Appliances', 'Smart cleaning, cordless vacuums, and robotics.', true),
    (p_organization_id, 'Mobila', 'Mobila', 'Cabinetry', 'Kitchen and bath cabinetry program for channel partners.', true),
    (p_organization_id, 'Nobilia', 'Nobilia', 'Cabinetry', 'Premium German kitchen and storage cabinetry.', true)
  on conflict (organization_id, name) do update
    set brand = excluded.brand,
        category = excluded.category,
        description = excluded.description,
        active = true,
        updated_at = now();
end;

$fn$;

CREATE OR REPLACE FUNCTION public.provision_aicrm_territory_defaults_for_organization(p_organization_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $fn$

declare
  v_country_id uuid;
  v_province_id uuid;
  v_province text;
begin
  if p_organization_id is null then
    return;
  end if;

  insert into public.aicrm_territories (
    organization_id,
    parent_id,
    territory_type,
    name,
    code,
    country,
    active,
    display_order,
    metadata
  )
  values (
    p_organization_id,
    null,
    'country',
    'Canada',
    'CA',
    'CA',
    true,
    0,
    '{"source":"phase_17_default"}'::jsonb
  )
  on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type)
  do update set updated_at = now()
  returning id into v_country_id;

  for v_province in
    select * from unnest(array[
      'Ontario',
      'Alberta',
      'British Columbia',
      'Manitoba',
      'Saskatchewan',
      'Quebec',
      'Nova Scotia',
      'New Brunswick',
      'Prince Edward Island',
      'Newfoundland and Labrador'
    ])
  loop
    insert into public.aicrm_territories (
      organization_id,
      parent_id,
      territory_type,
      name,
      code,
      country,
      province,
      active,
      display_order,
      metadata
    )
    values (
      p_organization_id,
      v_country_id,
      'province',
      v_province,
      left(regexp_replace(v_province, '[^A-Za-z0-9]', '', 'g'), 3),
      'CA',
      v_province,
      true,
      0,
      '{"source":"phase_17_default"}'::jsonb
    )
    on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type)
    do update set country = excluded.country, province = excluded.province, updated_at = now()
    returning id into v_province_id;

    if v_province = 'Ontario' then
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Toronto', 'CA', 'Ontario', 'Toronto', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Ottawa', 'CA', 'Ontario', 'Ottawa', true, 1, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'sales_territory', 'Southwestern Ontario', 'CA', 'Ontario', 'Southwestern Ontario', true, 2, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'Alberta' then
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Calgary', 'CA', 'Alberta', 'Calgary', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Edmonton', 'CA', 'Alberta', 'Edmonton', true, 1, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'British Columbia' then
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Vancouver', 'CA', 'British Columbia', 'Vancouver', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Victoria', 'CA', 'British Columbia', 'Victoria', true, 1, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'Quebec' then
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Montreal', 'CA', 'Quebec', 'Montreal', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'Nova Scotia' then
      insert into public.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Halifax', 'CA', 'Nova Scotia', 'Halifax', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    end if;
  end loop;

  insert into public.aicrm_territories (
    organization_id,
    parent_id,
    territory_type,
    name,
    country,
    active,
    display_order,
    metadata
  )
  values (
    p_organization_id,
    v_country_id,
    'sales_territory',
    coalesce((select default_territory from public.aicrm_organization_settings where organization_id = p_organization_id), 'National'),
    'CA',
    true,
    100,
    '{"source":"phase_17_default"}'::jsonb
  )
  on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type)
  do update set updated_at = now();
end;

$fn$;

CREATE OR REPLACE FUNCTION public.resolve_user_emails(p_emails text[]) RETURNS TABLE(email text, user_id uuid) LANGUAGE sql SECURITY DEFINER AS $fn$

  SELECT lower(u.email)::text, u.id
  FROM auth.users u
  WHERE lower(u.email) = ANY(SELECT lower(e) FROM unnest(p_emails) e);

$fn$;

CREATE OR REPLACE FUNCTION public.set_created_by_and_updated_by() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  new.updated_by := auth.uid();
  return new;
end;

$fn$;

CREATE OR REPLACE FUNCTION public.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) RETURNS uuid LANGUAGE plpgsql AS $fn$

declare v_product public.aiq_products%rowtype; v_package public.speciq_packages%rowtype; v_comparison public.ai_product_comparisons%rowtype; v_id uuid;
begin
  select * into v_package from public.speciq_packages where id=p_package_id;
  if not found then raise exception 'Package not found'; end if;
  select * into v_comparison from public.ai_product_comparisons where id=p_comparison_id and organization_id=v_package.organization_id;
  if not found or v_comparison.winner_product_id is null then raise exception 'Comparison winner not available'; end if;
  select * into v_product from public.aiq_products where id=v_comparison.winner_product_id and organization_id=v_package.organization_id;
  if not found then raise exception 'Winner product not found'; end if;
  insert into public.speciq_package_products(package_id,organization_id,product_name,brand,model_number,category,finish,width_inches,height_inches,depth_inches,weight_lbs,installation_type,msrp,promo_price,aiq_product_id,brand_id,series,product_line,short_description,spec_snapshot,source_comparison_id,selection_reason)
  values(v_package.id,v_package.organization_id,concat_ws(' ',v_product.brand_name,v_product.model),v_product.brand_name,v_product.model,v_product.category,v_product.finish,v_product.width_inches,v_product.height_inches,v_product.depth_inches,v_product.weight_lbs,v_product.installation_type,v_product.msrp,coalesce(v_product.sale_price,v_product.lowest_price),v_product.id,v_product.brand_id,v_product.series,v_product.product_line,v_product.short_description,coalesce(v_product.specs_json,'{}'::jsonb),v_comparison.id,coalesce(v_comparison.comparison_snapshot->>'winner_reason','Selected as comparison winner')) returning id into v_id;
  insert into public.speciq_package_events(package_id,event_type,event_data)
  values(v_package.id,'comparison_winner_added',jsonb_build_object('comparison_id',v_comparison.id,'product_id',v_product.id,'package_product_id',v_id));
  return v_id;
end; 
$fn$;

CREATE OR REPLACE FUNCTION public.start_embedding_worker_run(p_batch_requested integer, p_triggered_by text) RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $fn$

  insert into public.embedding_worker_runs (batch_requested, triggered_by)
  values (p_batch_requested, p_triggered_by) returning id;

$fn$;

CREATE OR REPLACE FUNCTION public.touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $fn$

begin new.updated_at = now(); return new; end 
$fn$;

CREATE OR REPLACE FUNCTION public.write_embedding(p_table_name text, p_row_id uuid, p_embedding vector, p_model text, p_source_hash text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $fn$

begin
  if p_table_name = 'ai_knowledge_chunks' then
    update public.ai_knowledge_chunks
       set embedding = p_embedding, embedding_model = p_model, source_hash = p_source_hash
     where id = p_row_id;
  elsif p_table_name = 'products' then
    update public.products
       set embedding = p_embedding, embedding_model = p_model, source_hash = p_source_hash
     where id = p_row_id;
  else
    return false;
  end if;
  return found;
end 
$fn$;

-- =========================
-- TRIGGERS
-- =========================

CREATE TRIGGER intelligence_sync_academy_progress_trg AFTER INSERT OR UPDATE ON public.academy_progress FOR EACH ROW EXECUTE FUNCTION intelligence_sync_academy_progress();

CREATE TRIGGER intelligence_sync_academy_quiz_score_trg AFTER INSERT OR UPDATE ON public.academy_quiz_scores FOR EACH ROW EXECUTE FUNCTION intelligence_sync_academy_quiz_score();

CREATE TRIGGER activities_touch BEFORE UPDATE ON public.activities FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER ai_coaching_reviews_kpi AFTER INSERT ON public.ai_coaching_reviews FOR EACH ROW EXECUTE FUNCTION log_coaching_kpi();

CREATE TRIGGER intelligence_sync_ai_coaching_review_trg AFTER INSERT OR UPDATE ON public.ai_coaching_reviews FOR EACH ROW EXECUTE FUNCTION intelligence_sync_ai_coaching_review();

CREATE TRIGGER intelligence_sync_ai_roleplay_trg AFTER INSERT OR UPDATE ON public.ai_roleplay_sessions FOR EACH ROW EXECUTE FUNCTION intelligence_sync_ai_roleplay();

CREATE TRIGGER trg_aicrm_account_custom_field_values_updated_at BEFORE UPDATE ON public.aicrm_account_custom_field_values FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_account_custom_field_values_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_account_custom_field_values FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_account_custom_fields_updated_at BEFORE UPDATE ON public.aicrm_account_custom_fields FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_account_custom_fields_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_account_custom_fields FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_account_execution_briefs_updated_at BEFORE UPDATE ON public.aicrm_account_execution_briefs FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_account_product_fit_updated_at BEFORE UPDATE ON public.aicrm_account_product_fit FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_accounts_updated_at BEFORE UPDATE ON public.aicrm_accounts FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_accounts_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_accounts FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_market_accounts_change AFTER INSERT OR UPDATE ON public.aicrm_accounts FOR EACH ROW EXECUTE FUNCTION private.aicrm_handle_market_account_change();

CREATE TRIGGER trg_aicrm_activities_timeline AFTER INSERT OR DELETE OR UPDATE ON public.aicrm_activities FOR EACH ROW EXECUTE FUNCTION private.aicrm_record_opportunity_timeline_event();

CREATE TRIGGER trg_aicrm_activities_updated_at BEFORE UPDATE ON public.aicrm_activities FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_ai_enrichment_jobs_updated_at BEFORE UPDATE ON public.aicrm_ai_enrichment_jobs FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_ai_enrichment_jobs_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_ai_enrichment_jobs FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_ai_profiles_updated_at BEFORE UPDATE ON public.aicrm_ai_profiles FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_ai_research_updated_at BEFORE UPDATE ON public.aicrm_ai_research FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_ai_research_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_ai_research FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_brands_updated_at BEFORE UPDATE ON public.aicrm_brands FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_business_units_updated_at BEFORE UPDATE ON public.aicrm_business_units FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_buying_committee_updated_at BEFORE UPDATE ON public.aicrm_buying_committee FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_campaign_categories_updated_at BEFORE UPDATE ON public.aicrm_campaign_categories FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_campaign_sequences_updated_at BEFORE UPDATE ON public.aicrm_campaign_sequences FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_campaign_types_updated_at BEFORE UPDATE ON public.aicrm_campaign_types FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_channels_updated_at BEFORE UPDATE ON public.aicrm_channels FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_consent_records_updated_at BEFORE UPDATE ON public.aicrm_consent_records FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_consent_records_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_consent_records FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_contacts_updated_at BEFORE UPDATE ON public.aicrm_contacts FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_contacts_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_contacts FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_market_contacts_change AFTER INSERT OR UPDATE ON public.aicrm_contacts FOR EACH ROW EXECUTE FUNCTION private.aicrm_handle_market_contact_change();

CREATE TRIGGER trg_aicrm_daily_execution_queue_updated_at BEFORE UPDATE ON public.aicrm_daily_execution_queue FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_employment_history_sync_person AFTER INSERT OR DELETE OR UPDATE ON public.aicrm_employment_history FOR EACH ROW EXECUTE FUNCTION private.aicrm_sync_person_current_employment();

CREATE TRIGGER trg_aicrm_employment_history_updated_at BEFORE UPDATE ON public.aicrm_employment_history FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_enrichment_runs_updated_at BEFORE UPDATE ON public.aicrm_enrichment_runs FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_enrichment_runs_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_enrichment_runs FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_execution_history_updated_at BEFORE UPDATE ON public.aicrm_execution_history FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_forecasts_updated_at BEFORE UPDATE ON public.aicrm_forecasts FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER aicrm_graph_edges_touch_updated_at BEFORE UPDATE ON public.aicrm_graph_edges FOR EACH ROW EXECUTE FUNCTION aicrm_graph_touch_updated_at();

CREATE TRIGGER aicrm_graph_nodes_touch_updated_at BEFORE UPDATE ON public.aicrm_graph_nodes FOR EACH ROW EXECUTE FUNCTION aicrm_graph_touch_updated_at();

CREATE TRIGGER trg_aicrm_import_mappings_updated_at BEFORE UPDATE ON public.aicrm_import_mappings FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_import_mappings_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_import_mappings FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_import_rows_updated_at BEFORE UPDATE ON public.aicrm_import_rows FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_import_rows_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_import_rows FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_imports_updated_at BEFORE UPDATE ON public.aicrm_imports FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_imports_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_imports FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_kpis_updated_at BEFORE UPDATE ON public.aicrm_kpis FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_market_connectors_updated_at BEFORE UPDATE ON public.aicrm_market_connectors FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_market_coverage_updated_at BEFORE UPDATE ON public.aicrm_market_coverage FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_market_discovery_queue_updated_at BEFORE UPDATE ON public.aicrm_market_discovery_queue FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_market_events_updated_at BEFORE UPDATE ON public.aicrm_market_events FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_market_refresh_queue_updated_at BEFORE UPDATE ON public.aicrm_market_refresh_queue FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_market_watchlists_updated_at BEFORE UPDATE ON public.aicrm_market_watchlists FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_notes_timeline AFTER INSERT OR DELETE OR UPDATE ON public.aicrm_notes FOR EACH ROW EXECUTE FUNCTION private.aicrm_record_opportunity_timeline_event();

CREATE TRIGGER trg_aicrm_notes_updated_at BEFORE UPDATE ON public.aicrm_notes FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_opportunities_timeline AFTER INSERT OR DELETE OR UPDATE ON public.aicrm_opportunities FOR EACH ROW EXECUTE FUNCTION private.aicrm_record_opportunity_timeline_event();

CREATE TRIGGER trg_aicrm_opportunities_updated_at BEFORE UPDATE ON public.aicrm_opportunities FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_opportunities_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_opportunities FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_opportunity_health_updated_at BEFORE UPDATE ON public.aicrm_opportunity_health FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_opportunity_timelines_updated_at BEFORE UPDATE ON public.aicrm_opportunity_timelines FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_organization_settings_updated_at BEFORE UPDATE ON public.aicrm_organization_settings FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_outcomes_updated_at BEFORE UPDATE ON public.aicrm_outcomes FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_outreach_campaigns_updated_at BEFORE UPDATE ON public.aicrm_outreach_campaigns FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_outreach_campaigns_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_outreach_campaigns FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_outreach_messages_updated_at BEFORE UPDATE ON public.aicrm_outreach_messages FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_outreach_messages_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_outreach_messages FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER aicrm_partner_organizations_touch_updated_at BEFORE UPDATE ON public.aicrm_partner_organizations FOR EACH ROW EXECUTE FUNCTION aicrm_collaboration_touch_updated_at();

CREATE TRIGGER aicrm_partnerships_touch_updated_at BEFORE UPDATE ON public.aicrm_partnerships FOR EACH ROW EXECUTE FUNCTION aicrm_collaboration_touch_updated_at();

CREATE TRIGGER trg_aicrm_people_updated_at BEFORE UPDATE ON public.aicrm_people FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_pipeline_stages_updated_at BEFORE UPDATE ON public.aicrm_pipeline_stages FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_pipeline_stages_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_pipeline_stages FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_products_updated_at BEFORE UPDATE ON public.aicrm_products FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER aicrm_referrals_touch_updated_at BEFORE UPDATE ON public.aicrm_referrals FOR EACH ROW EXECUTE FUNCTION aicrm_collaboration_touch_updated_at();

CREATE TRIGGER trg_aicrm_relationships_updated_at BEFORE UPDATE ON public.aicrm_relationships FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_route_plans_updated_at BEFORE UPDATE ON public.aicrm_route_plans FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_sales_motions_updated_at BEFORE UPDATE ON public.aicrm_sales_motions FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_sales_playbooks_updated_at BEFORE UPDATE ON public.aicrm_sales_playbooks FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_sequence_enrollments_updated_at BEFORE UPDATE ON public.aicrm_sequence_enrollments FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_sequence_enrollments_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_sequence_enrollments FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_sequence_steps_updated_at BEFORE UPDATE ON public.aicrm_sequence_steps FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_sequence_steps_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_sequence_steps FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER aicrm_shared_market_intelligence_touch_updated_at BEFORE UPDATE ON public.aicrm_shared_market_intelligence FOR EACH ROW EXECUTE FUNCTION aicrm_collaboration_touch_updated_at();

CREATE TRIGGER aicrm_shared_projects_touch_updated_at BEFORE UPDATE ON public.aicrm_shared_projects FOR EACH ROW EXECUTE FUNCTION aicrm_collaboration_touch_updated_at();

CREATE TRIGGER trg_aicrm_suppression_list_updated_at BEFORE UPDATE ON public.aicrm_suppression_list FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_suppression_list_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_suppression_list FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_tasks_updated_at BEFORE UPDATE ON public.aicrm_tasks FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_tasks_updated_by BEFORE INSERT OR UPDATE ON public.aicrm_tasks FOR EACH ROW EXECUTE FUNCTION set_created_by_and_updated_by();

CREATE TRIGGER trg_aicrm_territories_updated_at BEFORE UPDATE ON public.aicrm_territories FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER trg_aicrm_territory_heatmaps_updated_at BEFORE UPDATE ON public.aicrm_territory_heatmaps FOR EACH ROW EXECUTE FUNCTION private.set_updated_at();

CREATE TRIGGER aicrm_training_exchanges_touch_updated_at BEFORE UPDATE ON public.aicrm_training_exchanges FOR EACH ROW EXECUTE FUNCTION aicrm_collaboration_touch_updated_at();

CREATE TRIGGER intelligence_aiq_products_sync AFTER INSERT OR DELETE OR UPDATE ON public.aiq_products FOR EACH ROW EXECUTE FUNCTION intelligence_sync_aiq_product();

CREATE TRIGGER trg_aiq_products_touch_updated_at BEFORE UPDATE ON public.aiq_products FOR EACH ROW EXECUTE FUNCTION aiq_touch_updated_at();

CREATE TRIGGER trg_aiq_products_version AFTER INSERT OR UPDATE ON public.aiq_products FOR EACH ROW EXECUTE FUNCTION aiq_record_version('aiq_product_versions', 'product_id');

CREATE TRIGGER trg_pim_notification AFTER INSERT OR UPDATE ON public.aiq_products FOR EACH ROW EXECUTE FUNCTION fn_pim_notification();

CREATE TRIGGER trg_pim_to_training AFTER INSERT OR UPDATE ON public.aiq_products FOR EACH ROW EXECUTE FUNCTION fn_sync_pim_to_training();

CREATE TRIGGER trg_product_iq_guard_product_governance BEFORE INSERT OR UPDATE ON public.aiq_products FOR EACH ROW EXECUTE FUNCTION product_iq_guard_product_governance();

CREATE TRIGGER intelligence_brand_catalog_sync AFTER INSERT OR DELETE OR UPDATE ON public.brand_catalog FOR EACH ROW EXECUTE FUNCTION intelligence_sync_brand_catalog();

CREATE TRIGGER trg_auto_create_brand_course AFTER INSERT ON public.brand_catalog FOR EACH ROW EXECUTE FUNCTION fn_auto_create_brand_course();

CREATE TRIGGER companies_touch BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_ccr_notification AFTER INSERT ON public.competitive_cross_reference FOR EACH ROW EXECUTE FUNCTION fn_ccr_notification();

CREATE TRIGGER contacts_touch BEFORE UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER intelligence_sync_crm_contact_trg AFTER INSERT OR DELETE OR UPDATE ON public.contacts FOR EACH ROW EXECUTE FUNCTION intelligence_sync_crm_contact();

CREATE TRIGGER crm_deals_touch BEFORE UPDATE ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER intelligence_sync_crm_deal_trg AFTER INSERT OR DELETE OR UPDATE ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION intelligence_sync_crm_deal();

CREATE TRIGGER intelligence_sync_crm_delivery_trg AFTER INSERT OR UPDATE ON public.crm_delivery_workflows FOR EACH ROW EXECUTE FUNCTION intelligence_sync_crm_delivery();

CREATE TRIGGER intelligence_sync_iq_lead_assignment_trg AFTER INSERT OR DELETE OR UPDATE ON public.crm_iq_lead_assignments FOR EACH ROW EXECUTE FUNCTION intelligence_sync_iq_lead_assignment();

CREATE TRIGGER intelligence_sync_crm_postmortem_trg AFTER INSERT OR UPDATE ON public.crm_postmortems FOR EACH ROW EXECUTE FUNCTION intelligence_sync_crm_postmortem();

CREATE TRIGGER crm_tasks_touch BEFORE UPDATE ON public.crm_tasks FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER intelligence_sync_crm_task_trg AFTER INSERT OR UPDATE ON public.crm_tasks FOR EACH ROW EXECUTE FUNCTION intelligence_sync_crm_task();

CREATE TRIGGER intelligence_sync_daily_coaching_focus_trg AFTER INSERT OR UPDATE ON public.daily_coaching_focus FOR EACH ROW EXECUTE FUNCTION intelligence_sync_daily_coaching_focus();

CREATE TRIGGER decision_cases_touch BEFORE INSERT OR UPDATE ON public.decision_cases FOR EACH ROW EXECUTE FUNCTION decision_touch_case();

CREATE TRIGGER executive_snapshot_confidence_trg AFTER INSERT ON public.executive_intelligence_snapshots FOR EACH ROW EXECUTE FUNCTION executive_snapshot_confidence_trigger();

CREATE TRIGGER intelligence_sync_field_action_trg AFTER INSERT OR UPDATE ON public.field_actions FOR EACH ROW EXECUTE FUNCTION intelligence_sync_field_action();

CREATE TRIGGER intelligence_sync_field_competitive_trg AFTER INSERT OR UPDATE ON public.field_competitive_intel FOR EACH ROW EXECUTE FUNCTION intelligence_sync_field_competitive();

CREATE TRIGGER intelligence_sync_field_finding_trg AFTER INSERT OR UPDATE ON public.field_findings FOR EACH ROW EXECUTE FUNCTION intelligence_sync_field_finding();

CREATE TRIGGER intelligence_sync_field_store_score_trg AFTER INSERT OR UPDATE ON public.field_store_scores FOR EACH ROW EXECUTE FUNCTION intelligence_sync_field_store_score();

CREATE TRIGGER intelligence_sync_field_training_trg AFTER INSERT OR UPDATE ON public.field_training_sessions FOR EACH ROW EXECUTE FUNCTION intelligence_sync_field_training();

CREATE TRIGGER intelligence_sync_field_visit_trg AFTER INSERT OR UPDATE ON public.field_visits FOR EACH ROW EXECUTE FUNCTION intelligence_sync_field_visit();

CREATE TRIGGER trg_audit_facts AFTER INSERT OR DELETE OR UPDATE ON public.foundation_facts FOR EACH ROW EXECUTE FUNCTION foundation_audit();

CREATE TRIGGER trg_fact_guard BEFORE INSERT OR UPDATE ON public.foundation_facts FOR EACH ROW EXECUTE FUNCTION foundation_fact_guard();

CREATE TRIGGER trg_audit_objects AFTER INSERT OR DELETE OR UPDATE ON public.foundation_objects FOR EACH ROW EXECUTE FUNCTION foundation_audit();

CREATE TRIGGER trg_audit_rels AFTER INSERT OR DELETE OR UPDATE ON public.foundation_relationships FOR EACH ROW EXECUTE FUNCTION foundation_audit();

CREATE TRIGGER intelligence_context_cache_set_updated_at BEFORE UPDATE ON public.intelligence_context_cache FOR EACH ROW EXECUTE FUNCTION intelligence_set_updated_at();

CREATE TRIGGER intelligence_entities_set_updated_at BEFORE UPDATE ON public.intelligence_entities FOR EACH ROW EXECUTE FUNCTION intelligence_set_updated_at();

CREATE TRIGGER intelligence_events_create_timeline AFTER INSERT ON public.intelligence_events FOR EACH ROW EXECUTE FUNCTION intelligence_event_to_timeline();

CREATE TRIGGER intelligence_outcome_learning_trigger AFTER INSERT OR DELETE OR UPDATE ON public.intelligence_outcomes FOR EACH ROW EXECUTE FUNCTION intelligence_outcome_after_change();

CREATE TRIGGER intelligence_recommendation_event_trigger AFTER INSERT ON public.intelligence_recommendations FOR EACH ROW EXECUTE FUNCTION intelligence_recommendation_after_insert();

CREATE TRIGGER intelligence_sync_iq_customer_interaction_trg AFTER INSERT OR DELETE OR UPDATE ON public.iq_customer_interactions FOR EACH ROW EXECUTE FUNCTION intelligence_sync_iq_customer_interaction();

CREATE TRIGGER intelligence_sync_iq_product_interest_trg AFTER INSERT OR DELETE OR UPDATE ON public.iq_customer_product_interest FOR EACH ROW EXECUTE FUNCTION intelligence_sync_iq_product_interest();

CREATE TRIGGER intelligence_sync_iq_waiting_customer_trg AFTER INSERT OR DELETE OR UPDATE ON public.iq_customer_waiting_queue FOR EACH ROW EXECUTE FUNCTION intelligence_sync_iq_waiting_customer();

CREATE TRIGGER trg_new_deck_notification AFTER INSERT ON public.iq_decks FOR EACH ROW EXECUTE FUNCTION fn_new_deck_notification();

CREATE TRIGGER organizations_touch BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_aicrm_organization_execution_seed AFTER INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION private.aicrm_seed_execution_defaults_from_trigger();

CREATE TRIGGER trg_notify_pim_marketing_assets AFTER INSERT ON public.pim_marketing_assets FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_upd_pim_marketing_assets AFTER UPDATE OF embargoed ON public.pim_marketing_assets FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_pim_product_documents AFTER INSERT ON public.pim_product_documents FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_upd_pim_product_documents AFTER UPDATE OF embargoed ON public.pim_product_documents FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_pim_product_images AFTER INSERT ON public.pim_product_images FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_upd_pim_product_images AFTER UPDATE OF embargoed ON public.pim_product_images FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_pim_product_rebates AFTER INSERT ON public.pim_product_rebates FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_upd_pim_product_rebates AFTER UPDATE OF embargoed ON public.pim_product_rebates FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_pim_product_videos AFTER INSERT ON public.pim_product_videos FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER trg_notify_upd_pim_product_videos AFTER UPDATE OF embargoed ON public.pim_product_videos FOR EACH ROW EXECUTE FUNCTION piq_notify_new_asset();

CREATE TRIGGER products_touch BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER profiles_touch BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_profiles_sync_id BEFORE INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.sync_profiles_id();

CREATE TRIGGER sales_recordings_kpi AFTER INSERT OR UPDATE ON public.sales_recordings FOR EACH ROW EXECUTE FUNCTION log_recording_kpi();

CREATE TRIGGER sales_recordings_touch BEFORE UPDATE ON public.sales_recordings FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER intelligence_sync_speciq_package_event_trg AFTER INSERT ON public.speciq_package_events FOR EACH ROW EXECUTE FUNCTION intelligence_sync_speciq_package_event();

CREATE TRIGGER intelligence_sync_speciq_package_product_trg AFTER INSERT OR DELETE OR UPDATE ON public.speciq_package_products FOR EACH ROW EXECUTE FUNCTION intelligence_sync_speciq_package_product();

CREATE TRIGGER intelligence_sync_speciq_package_trg AFTER INSERT OR DELETE OR UPDATE ON public.speciq_packages FOR EACH ROW EXECUTE FUNCTION intelligence_sync_speciq_package();

CREATE TRIGGER trg_speciq_quote_number BEFORE INSERT ON public.speciq_packages FOR EACH ROW EXECUTE FUNCTION generate_speciq_quote_number();

CREATE TRIGGER intelligence_sync_speciq_project_trg AFTER INSERT OR DELETE OR UPDATE ON public.speciq_projects FOR EACH ROW EXECUTE FUNCTION intelligence_sync_speciq_project();

-- =========================
-- RLS POLICIES: academy_*
-- =========================

ALTER TABLE public.academy_brand_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own brand certs" ON public.academy_brand_certifications AS PERMISSIVE FOR SELECT TO public USING ((user_id = auth.uid()));

ALTER TABLE public.academy_brand_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "system insert brand certs" ON public.academy_brand_certifications AS PERMISSIVE FOR INSERT TO public WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.academy_brand_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own brand progress" ON public.academy_brand_progress AS PERMISSIVE FOR ALL TO public USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.academy_brand_quiz_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own brand quiz scores" ON public.academy_brand_quiz_scores AS PERMISSIVE FOR ALL TO public USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.academy_brand_quizzes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read brand quizzes" ON public.academy_brand_quizzes AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));

ALTER TABLE public.academy_cert_gates ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_cert_gates ON public.academy_cert_gates AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.academy_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_own_certs ON public.academy_certifications AS PERMISSIVE FOR ALL TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.academy_chapters ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_chapters ON public.academy_chapters AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.academy_daily_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_own_daily_metrics ON public.academy_daily_metrics AS PERMISSIVE FOR ALL TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.academy_leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can insert leads" ON public.academy_leads AS PERMISSIVE FOR INSERT TO public WITH CHECK (true);

ALTER TABLE public.academy_leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can read leads" ON public.academy_leads AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));

ALTER TABLE public.academy_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own notifications" ON public.academy_notifications AS PERMISSIVE FOR ALL TO public USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.academy_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_plans ON public.academy_plans AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.academy_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_own_profile ON public.academy_profiles AS PERMISSIVE FOR ALL TO authenticated USING ((auth.uid() = id)) WITH CHECK ((auth.uid() = id));

ALTER TABLE public.academy_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_own_progress ON public.academy_progress AS PERMISSIVE FOR ALL TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.academy_quiz_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own quiz scores" ON public.academy_quiz_scores AS PERMISSIVE FOR ALL TO public USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.academy_quizzes ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_quizzes ON public.academy_quizzes AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.academy_track_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_own_track_progress ON public.academy_track_progress AS PERMISSIVE FOR ALL TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.academy_tracks ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_tracks ON public.academy_tracks AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.academy_volumes ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_volumes ON public.academy_volumes AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.academy_worksheets ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_worksheets ON public.academy_worksheets AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY activities_org_delete ON public.activities AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY activities_org_insert ON public.activities AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY activities_org_select ON public.activities AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY activities_org_update ON public.activities AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

-- =========================
-- RLS POLICIES: ai_* through aicrm_n*
-- =========================

ALTER TABLE public.ai_assistants ENABLE ROW LEVEL SECURITY;
CREATE POLICY assistants_visible ON public.ai_assistants AS PERMISSIVE FOR SELECT TO public USING (((organization_id IS NULL) OR is_org_member(organization_id)));

ALTER TABLE public.ai_audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_admin ON public.ai_audit_events AS PERMISSIVE FOR SELECT TO public USING (is_org_admin(organization_id));

ALTER TABLE public.ai_budget_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY abp_select ON public.ai_budget_predictions AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.ai_budget_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY abp_write ON public.ai_budget_predictions AS PERMISSIVE FOR ALL TO public USING (is_org_admin(organization_id));

ALTER TABLE public.ai_coaching_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_coaching_reviews_org_delete ON public.ai_coaching_reviews AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.ai_coaching_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_coaching_reviews_org_insert ON public.ai_coaching_reviews AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.ai_coaching_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_coaching_reviews_org_select ON public.ai_coaching_reviews AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.ai_coaching_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_coaching_reviews_org_update ON public.ai_coaching_reviews AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.ai_conversation_memory ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversation_memory_delete_own ON public.ai_conversation_memory AS PERMISSIVE FOR DELETE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversation_memory ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversation_memory_insert_own ON public.ai_conversation_memory AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversation_memory ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversation_memory_select_own ON public.ai_conversation_memory AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversation_memory ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversation_memory_update_own ON public.ai_conversation_memory AS PERMISSIVE FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversation_turns ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversation_turns_delete_own ON public.ai_conversation_turns AS PERMISSIVE FOR DELETE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversation_turns ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversation_turns_insert_own ON public.ai_conversation_turns AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversation_turns ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversation_turns_select_own ON public.ai_conversation_turns AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversations_delete_own ON public.ai_conversations AS PERMISSIVE FOR DELETE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversations_insert_own ON public.ai_conversations AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversations_select_own ON public.ai_conversations AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_conversations_update_own ON public.ai_conversations AS PERMISSIVE FOR UPDATE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id)) WITH CHECK ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_knowledge_chunks ENABLE ROW LEVEL SECURITY;
CREATE POLICY kchunks_visible ON public.ai_knowledge_chunks AS PERMISSIVE FOR SELECT TO public USING (((visibility = 'global'::text) OR is_org_member(organization_id)));

ALTER TABLE public.ai_knowledge_sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY ksources_visible ON public.ai_knowledge_sources AS PERMISSIVE FOR SELECT TO public USING (((visibility = 'global'::text) OR is_org_member(organization_id)));

ALTER TABLE public.ai_manager_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_manager_assignments_org_access ON public.ai_manager_assignments AS PERMISSIVE FOR ALL TO authenticated USING (is_org_member(organization_id)) WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.ai_manager_briefs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_manager_briefs_org_access ON public.ai_manager_briefs AS PERMISSIVE FOR ALL TO authenticated USING (is_org_member(organization_id)) WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.ai_manager_escalations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_manager_escalations_org_access ON public.ai_manager_escalations AS PERMISSIVE FOR ALL TO authenticated USING (is_org_member(organization_id)) WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.ai_manager_task_attachments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_manager_task_attachments_org_access ON public.ai_manager_task_attachments AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = ai_manager_task_attachments.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = ai_manager_task_attachments.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.ai_manager_task_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_manager_task_comments_org_access ON public.ai_manager_task_comments AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = ai_manager_task_comments.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = ai_manager_task_comments.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.ai_manager_task_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_manager_task_history_org_access ON public.ai_manager_task_history AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = ai_manager_task_history.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.ai_personas ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_personas_select ON public.ai_personas AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.ai_personas ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_personas_update ON public.ai_personas AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.ai_personas ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_personas_write ON public.ai_personas AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.ai_product_comparisons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "comparison owner delete" ON public.ai_product_comparisons AS PERMISSIVE FOR DELETE TO authenticated USING ((( SELECT auth.uid() AS uid) = user_id));

ALTER TABLE public.ai_product_comparisons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "comparison owner insert" ON public.ai_product_comparisons AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((( SELECT auth.uid() AS uid) = user_id) AND ((organization_id IS NULL) OR is_org_member(organization_id))));

ALTER TABLE public.ai_product_comparisons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "comparison owner select" ON public.ai_product_comparisons AS PERMISSIVE FOR SELECT TO authenticated USING (((( SELECT auth.uid() AS uid) = user_id) OR ((organization_id IS NOT NULL) AND is_org_member(organization_id))));

ALTER TABLE public.ai_product_comparisons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "comparison owner update" ON public.ai_product_comparisons AS PERMISSIVE FOR UPDATE TO authenticated USING (((( SELECT auth.uid() AS uid) = user_id) OR ((organization_id IS NOT NULL) AND is_org_member(organization_id)))) WITH CHECK (((( SELECT auth.uid() AS uid) = user_id) AND ((organization_id IS NULL) OR is_org_member(organization_id))));

ALTER TABLE public.ai_prompt_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY templates_visible ON public.ai_prompt_templates AS PERMISSIVE FOR SELECT TO public USING (((organization_id IS NULL) OR is_org_member(organization_id)));

ALTER TABLE public.ai_proposed_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY actions_org ON public.ai_proposed_actions AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.ai_proposed_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY actions_review ON public.ai_proposed_actions AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.ai_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY requests_own ON public.ai_requests AS PERMISSIVE FOR SELECT TO public USING (((user_id = auth.uid()) OR is_org_admin(organization_id)));

ALTER TABLE public.ai_roleplay_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_roleplay_sessions_insert ON public.ai_roleplay_sessions AS PERMISSIVE FOR INSERT TO public WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.ai_roleplay_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_roleplay_sessions_select ON public.ai_roleplay_sessions AS PERMISSIVE FOR SELECT TO public USING ((is_org_member(organization_id) OR (user_id = auth.uid())));

ALTER TABLE public.ai_roleplay_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_roleplay_sessions_update ON public.ai_roleplay_sessions AS PERMISSIVE FOR UPDATE TO public USING ((user_id = auth.uid()));

ALTER TABLE public.ai_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY sessions_own ON public.ai_sessions AS PERMISSIVE FOR SELECT TO public USING ((user_id = auth.uid()));

ALTER TABLE public.ai_token_limits ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_token_limits_select ON public.ai_token_limits AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.ai_trainer_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own trainer messages" ON public.ai_trainer_messages AS PERMISSIVE FOR ALL TO public USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.ai_trainer_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own trainer sessions" ON public.ai_trainer_sessions AS PERMISSIVE FOR ALL TO public USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));

ALTER TABLE public.ai_usage_meter ENABLE ROW LEVEL SECURITY;
CREATE POLICY usage_admin ON public.ai_usage_meter AS PERMISSIVE FOR SELECT TO public USING (is_org_admin(organization_id));

ALTER TABLE public.aicrm_account_custom_field_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm custom field values select" ON public.aicrm_account_custom_field_values AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_account_custom_field_values ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm custom field values write" ON public.aicrm_account_custom_field_values AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_account_custom_fields ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm custom fields select" ON public.aicrm_account_custom_fields AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_account_custom_fields ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm custom fields write" ON public.aicrm_account_custom_fields AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_account_execution_briefs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm execution briefs select" ON public.aicrm_account_execution_briefs AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_account_execution_briefs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm execution briefs write" ON public.aicrm_account_execution_briefs AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_account_product_fit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm account product fit select" ON public.aicrm_account_product_fit AS PERMISSIVE FOR SELECT TO public USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_account_product_fit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm account product fit write" ON public.aicrm_account_product_fit AS PERMISSIVE FOR ALL TO public USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_account_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm account tags select" ON public.aicrm_account_tags AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_account_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm account tags write" ON public.aicrm_account_tags AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm accounts select" ON public.aicrm_accounts AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm accounts write" ON public.aicrm_accounts AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm activities select" ON public.aicrm_activities AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm activities write" ON public.aicrm_activities AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_ai_enrichment_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm ai enrichment jobs select" ON public.aicrm_ai_enrichment_jobs AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_ai_enrichment_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm ai enrichment jobs write" ON public.aicrm_ai_enrichment_jobs AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_ai_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm ai profiles select" ON public.aicrm_ai_profiles AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_ai_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm ai profiles write" ON public.aicrm_ai_profiles AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_ai_research ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm ai research select" ON public.aicrm_ai_research AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_ai_research ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm ai research write" ON public.aicrm_ai_research AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm audit log select" ON public.aicrm_audit_log AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm audit log write" ON public.aicrm_audit_log AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_brands ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm brands select" ON public.aicrm_brands AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_brands ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm brands write" ON public.aicrm_brands AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_business_units ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm business units select" ON public.aicrm_business_units AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_business_units ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm business units write" ON public.aicrm_business_units AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_buying_committee ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm buying committee select" ON public.aicrm_buying_committee AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_buying_committee ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm buying committee write" ON public.aicrm_buying_committee AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_campaign_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm campaign categories select" ON public.aicrm_campaign_categories AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_campaign_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm campaign categories write" ON public.aicrm_campaign_categories AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_campaign_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm campaign sequences select" ON public.aicrm_campaign_sequences AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_campaign_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm campaign sequences write" ON public.aicrm_campaign_sequences AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_campaign_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm campaign types select" ON public.aicrm_campaign_types AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_campaign_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm campaign types write" ON public.aicrm_campaign_types AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_channels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm channels select" ON public.aicrm_channels AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_channels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm channels write" ON public.aicrm_channels AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_collaboration_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "collaboration audit read participants" ON public.aicrm_collaboration_audit_log AS PERMISSIVE FOR SELECT TO public USING (((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_collaboration_audit_log.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_collaboration_audit_log.partner_organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_collaboration_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "collaboration audit write origin org" ON public.aicrm_collaboration_audit_log AS PERMISSIVE FOR INSERT TO public WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_collaboration_audit_log.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_consent_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm consent records select" ON public.aicrm_consent_records AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_consent_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm consent records write" ON public.aicrm_consent_records AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm contacts select" ON public.aicrm_contacts AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm contacts write" ON public.aicrm_contacts AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_daily_execution_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm daily execution queue select" ON public.aicrm_daily_execution_queue AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_daily_execution_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm daily execution queue write" ON public.aicrm_daily_execution_queue AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_employment_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm employment history select" ON public.aicrm_employment_history AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_employment_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm employment history write" ON public.aicrm_employment_history AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_enrichment_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm enrichment runs select" ON public.aicrm_enrichment_runs AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_enrichment_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm enrichment runs write" ON public.aicrm_enrichment_runs AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_execution_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm execution history select" ON public.aicrm_execution_history AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_execution_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm execution history write" ON public.aicrm_execution_history AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_forecasts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm forecasts select" ON public.aicrm_forecasts AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_forecasts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm forecasts write" ON public.aicrm_forecasts AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_graph_edges ENABLE ROW LEVEL SECURITY;
CREATE POLICY aicrm_graph_edges_manage_own_org ON public.aicrm_graph_edges AS PERMISSIVE FOR ALL TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_graph_edges.organization_id) AND (om.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_graph_edges.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_graph_edges ENABLE ROW LEVEL SECURITY;
CREATE POLICY aicrm_graph_edges_select_own_org ON public.aicrm_graph_edges AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_graph_edges.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_graph_nodes ENABLE ROW LEVEL SECURITY;
CREATE POLICY aicrm_graph_nodes_manage_own_org ON public.aicrm_graph_nodes AS PERMISSIVE FOR ALL TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_graph_nodes.organization_id) AND (om.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_graph_nodes.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_graph_nodes ENABLE ROW LEVEL SECURITY;
CREATE POLICY aicrm_graph_nodes_select_own_org ON public.aicrm_graph_nodes AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_graph_nodes.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_import_mappings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm import mappings select" ON public.aicrm_import_mappings AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_import_mappings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm import mappings write" ON public.aicrm_import_mappings AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_import_rows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm import rows select" ON public.aicrm_import_rows AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_import_rows ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm import rows write" ON public.aicrm_import_rows AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_imports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm imports select" ON public.aicrm_imports AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_imports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm imports write" ON public.aicrm_imports AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_kpis ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm kpis select" ON public.aicrm_kpis AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_kpis ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm kpis write" ON public.aicrm_kpis AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_market_connectors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market connectors select" ON public.aicrm_market_connectors AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_market_connectors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market connectors write" ON public.aicrm_market_connectors AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_market_coverage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market coverage select" ON public.aicrm_market_coverage AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_market_coverage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market coverage write" ON public.aicrm_market_coverage AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_market_discovery_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market discovery select" ON public.aicrm_market_discovery_queue AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_market_discovery_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market discovery write" ON public.aicrm_market_discovery_queue AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_market_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market events select" ON public.aicrm_market_events AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_market_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market events write" ON public.aicrm_market_events AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_market_refresh_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market refresh select" ON public.aicrm_market_refresh_queue AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_market_refresh_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market refresh write" ON public.aicrm_market_refresh_queue AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_market_watchlists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market watchlists select" ON public.aicrm_market_watchlists AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_market_watchlists ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm market watchlists write" ON public.aicrm_market_watchlists AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm notes select" ON public.aicrm_notes AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm notes write" ON public.aicrm_notes AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

-- =========================
-- RLS POLICIES: aicrm_o* through b*
-- =========================

ALTER TABLE public.aicrm_opportunities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm opportunities select" ON public.aicrm_opportunities AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_opportunities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm opportunities write" ON public.aicrm_opportunities AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_opportunity_health ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm opportunity health select" ON public.aicrm_opportunity_health AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_opportunity_health ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm opportunity health write" ON public.aicrm_opportunity_health AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_opportunity_timelines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm opportunity timelines select" ON public.aicrm_opportunity_timelines AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_opportunity_timelines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm opportunity timelines write" ON public.aicrm_opportunity_timelines AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_organization_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm organization settings select" ON public.aicrm_organization_settings AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_organization_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm organization settings write" ON public.aicrm_organization_settings AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_outcomes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm outcomes select" ON public.aicrm_outcomes AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_outcomes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm outcomes write" ON public.aicrm_outcomes AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_outreach_campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm outreach campaigns select" ON public.aicrm_outreach_campaigns AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_outreach_campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm outreach campaigns write" ON public.aicrm_outreach_campaigns AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_outreach_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm outreach messages select" ON public.aicrm_outreach_messages AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_outreach_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm outreach messages write" ON public.aicrm_outreach_messages AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_partner_organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "partner orgs read own or public" ON public.aicrm_partner_organizations AS PERMISSIVE FOR SELECT TO public USING (((public_visible = true) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partner_organizations.organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_partner_organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "partner orgs write own org" ON public.aicrm_partner_organizations AS PERMISSIVE FOR ALL TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partner_organizations.organization_id) AND (om.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partner_organizations.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_partnerships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "partnerships read participants" ON public.aicrm_partnerships AS PERMISSIVE FOR SELECT TO public USING (((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partnerships.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partnerships.partner_organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_partnerships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "partnerships write participants" ON public.aicrm_partnerships AS PERMISSIVE FOR ALL TO public USING (((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partnerships.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partnerships.partner_organization_id) AND (om.user_id = auth.uid())))))) WITH CHECK (((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partnerships.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_partnerships.partner_organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_people ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm people select" ON public.aicrm_people AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_people ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm people write" ON public.aicrm_people AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_pipeline_stages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm pipeline stages select" ON public.aicrm_pipeline_stages AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_pipeline_stages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm pipeline stages write" ON public.aicrm_pipeline_stages AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm products select" ON public.aicrm_products AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm products write" ON public.aicrm_products AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_referrals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "referrals read participants" ON public.aicrm_referrals AS PERMISSIVE FOR SELECT TO public USING (((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_referrals.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_referrals.destination_organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_referrals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "referrals write origin org" ON public.aicrm_referrals AS PERMISSIVE FOR ALL TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_referrals.organization_id) AND (om.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_referrals.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_relationships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm relationships select" ON public.aicrm_relationships AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_relationships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm relationships write" ON public.aicrm_relationships AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_route_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm route plans select" ON public.aicrm_route_plans AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_route_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm route plans write" ON public.aicrm_route_plans AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_sales_motions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sales motions select" ON public.aicrm_sales_motions AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_sales_motions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sales motions write" ON public.aicrm_sales_motions AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_sales_playbooks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sales playbooks select" ON public.aicrm_sales_playbooks AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_sales_playbooks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sales playbooks write" ON public.aicrm_sales_playbooks AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_saved_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm saved views select" ON public.aicrm_saved_views AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_saved_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm saved views write" ON public.aicrm_saved_views AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_sequence_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sequence enrollments select" ON public.aicrm_sequence_enrollments AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_sequence_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sequence enrollments write" ON public.aicrm_sequence_enrollments AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_sequence_steps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sequence steps select" ON public.aicrm_sequence_steps AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_sequence_steps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm sequence steps write" ON public.aicrm_sequence_steps AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_shared_market_intelligence ENABLE ROW LEVEL SECURITY;
CREATE POLICY "market intelligence read network" ON public.aicrm_shared_market_intelligence AS PERMISSIVE FOR SELECT TO public USING (((anonymous = true) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_market_intelligence.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_market_intelligence.partner_organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_shared_market_intelligence ENABLE ROW LEVEL SECURITY;
CREATE POLICY "market intelligence write origin org" ON public.aicrm_shared_market_intelligence AS PERMISSIVE FOR ALL TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_market_intelligence.organization_id) AND (om.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_market_intelligence.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_shared_projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "shared projects read participants" ON public.aicrm_shared_projects AS PERMISSIVE FOR SELECT TO public USING (((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_projects.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_projects.partner_organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_shared_projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY "shared projects write origin org" ON public.aicrm_shared_projects AS PERMISSIVE FOR ALL TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_projects.organization_id) AND (om.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_shared_projects.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aicrm_suppression_list ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm suppression list select" ON public.aicrm_suppression_list AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_suppression_list ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm suppression list write" ON public.aicrm_suppression_list AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm tags select" ON public.aicrm_tags AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_tags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm tags write" ON public.aicrm_tags AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm tasks select" ON public.aicrm_tasks AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm tasks write" ON public.aicrm_tasks AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_territories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm territories select" ON public.aicrm_territories AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_territories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm territories write" ON public.aicrm_territories AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_territory_heatmaps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm territory heatmaps select" ON public.aicrm_territory_heatmaps AS PERMISSIVE FOR SELECT TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.view'::text));

ALTER TABLE public.aicrm_territory_heatmaps ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aicrm territory heatmaps write" ON public.aicrm_territory_heatmaps AS PERMISSIVE FOR ALL TO authenticated USING (private.user_can_access_organization(organization_id, 'crm.manage'::text)) WITH CHECK (private.user_can_access_organization(organization_id, 'crm.manage'::text));

ALTER TABLE public.aicrm_training_exchanges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "training exchanges read participants" ON public.aicrm_training_exchanges AS PERMISSIVE FOR SELECT TO public USING (((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_training_exchanges.organization_id) AND (om.user_id = auth.uid())))) OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_training_exchanges.partner_organization_id) AND (om.user_id = auth.uid()))))));

ALTER TABLE public.aicrm_training_exchanges ENABLE ROW LEVEL SECURITY;
CREATE POLICY "training exchanges write origin org" ON public.aicrm_training_exchanges AS PERMISSIVE FOR ALL TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_training_exchanges.organization_id) AND (om.user_id = auth.uid()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = aicrm_training_exchanges.organization_id) AND (om.user_id = auth.uid())))));

ALTER TABLE public.aiq_product_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product iq product versions read" ON public.aiq_product_versions AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM aiq_products p
  WHERE ((p.id = aiq_product_versions.product_id) AND private.product_iq_can_read_product(p.organization_id, p.brand_name)))));

ALTER TABLE public.aiq_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_scraper_insert ON public.aiq_products AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.aiq_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_scraper_read ON public.aiq_products AS PERMISSIVE FOR SELECT TO anon USING (true);

ALTER TABLE public.aiq_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_scraper_update ON public.aiq_products AS PERMISSIVE FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.aiq_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY piq_products_retailer_read ON public.aiq_products AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.piq_is_retailer() AS piq_is_retailer) AND (public_visible = true) AND (approval_status = 'approved'::text) AND ( SELECT private.piq_carries_brand_name(aiq_products.brand_name) AS piq_carries_brand_name)));

ALTER TABLE public.aiq_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product iq products delete" ON public.aiq_products AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.aiq_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product iq products read" ON public.aiq_products AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_can_read_product(aiq_products.organization_id, aiq_products.brand_name) AS product_iq_can_read_product) OR ((approval_status = 'approved'::text) AND (public_visible = true) AND private.user_can_access_organization(organization_id, 'crm.view'::text))));

ALTER TABLE public.aiq_retailers ENABLE ROW LEVEL SECURITY;
CREATE POLICY retailers_read ON public.aiq_retailers AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.aiq_retailers ENABLE ROW LEVEL SECURITY;
CREATE POLICY retailers_update ON public.aiq_retailers AS PERMISSIVE FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.aiq_retailers ENABLE ROW LEVEL SECURITY;
CREATE POLICY retailers_write ON public.aiq_retailers AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.brand_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY bc_read_authenticated ON public.brand_catalog AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.brand_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY bc_select ON public.brand_catalog AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.brand_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product iq platform manages brand ownership" ON public.brand_catalog AS PERMISSIVE FOR ALL TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)) WITH CHECK (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.brand_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_brand_read ON public.brand_catalog AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.brand_map_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_read ON public.brand_map_policies AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.brand_map_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY sr_full ON public.brand_map_policies AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE public.brand_training_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "manage training cards" ON public.brand_training_cards AS PERMISSIVE FOR ALL TO public USING ((is_admin() OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.user_id = auth.uid()) AND (om.organization_id = brand_training_cards.organization_id)))))) WITH CHECK ((is_admin() OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.user_id = auth.uid()) AND (om.organization_id = brand_training_cards.organization_id))))));

ALTER TABLE public.brand_training_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read training cards" ON public.brand_training_cards AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));

ALTER TABLE public.budget_nodes ENABLE ROW LEVEL SECURITY;
CREATE POLICY bn_select ON public.budget_nodes AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.budget_nodes ENABLE ROW LEVEL SECURITY;
CREATE POLICY bn_write ON public.budget_nodes AS PERMISSIVE FOR ALL TO public USING (is_org_admin(organization_id));

ALTER TABLE public.budget_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY bp_select ON public.budget_plans AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.budget_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY bp_write ON public.budget_plans AS PERMISSIVE FOR ALL TO public USING (is_org_admin(organization_id));

ALTER TABLE public.buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_read ON public.buying_groups AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY sr_full ON public.buying_groups AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

-- =========================
-- RLS POLICIES: c* through e*
-- =========================

ALTER TABLE public.cad_bim_sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cad bim authenticated read" ON public.cad_bim_sources AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.cad_bim_sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cad bim platform write" ON public.cad_bim_sources AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM product_iq_platform_roles r
  WHERE ((r.user_id = auth.uid()) AND (r.status = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM product_iq_platform_roles r
  WHERE ((r.user_id = auth.uid()) AND (r.status = 'active'::text)))));

ALTER TABLE public.communication_audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_members_cae ON public.communication_audit_events AS PERMISSIVE FOR ALL TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.communication_email_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_members_cem ON public.communication_email_messages AS PERMISSIVE FOR ALL TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.communication_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_members_ct ON public.communication_templates AS PERMISSIVE FOR ALL TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.communication_webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_members_cwe ON public.communication_webhook_events AS PERMISSIVE FOR ALL TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY companies_org_delete ON public.companies AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY companies_org_insert ON public.companies AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY companies_org_select ON public.companies AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY companies_org_update ON public.companies AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY contacts_org_delete ON public.contacts AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY contacts_org_insert ON public.contacts AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY contacts_org_select ON public.contacts AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY contacts_org_update ON public.contacts AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_buying_group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_delete_bg_members ON public.crm_buying_group_members AS PERMISSIVE FOR DELETE TO public USING ((buying_group_id IN ( SELECT crm_buying_groups.id
   FROM crm_buying_groups
  WHERE (crm_buying_groups.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_buying_group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_insert_bg_members ON public.crm_buying_group_members AS PERMISSIVE FOR INSERT TO public WITH CHECK ((buying_group_id IN ( SELECT crm_buying_groups.id
   FROM crm_buying_groups
  WHERE (crm_buying_groups.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_buying_group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_select_bg_members ON public.crm_buying_group_members AS PERMISSIVE FOR SELECT TO public USING ((buying_group_id IN ( SELECT crm_buying_groups.id
   FROM crm_buying_groups
  WHERE (crm_buying_groups.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_buying_group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_update_bg_members ON public.crm_buying_group_members AS PERMISSIVE FOR UPDATE TO public USING ((buying_group_id IN ( SELECT crm_buying_groups.id
   FROM crm_buying_groups
  WHERE (crm_buying_groups.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_delete_buying_groups ON public.crm_buying_groups AS PERMISSIVE FOR DELETE TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_insert_buying_groups ON public.crm_buying_groups AS PERMISSIVE FOR INSERT TO public WITH CHECK ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_select_buying_groups ON public.crm_buying_groups AS PERMISSIVE FOR SELECT TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_update_buying_groups ON public.crm_buying_groups AS PERMISSIVE FOR UPDATE TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_daily_five ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_insert_daily_five ON public.crm_daily_five AS PERMISSIVE FOR INSERT TO public WITH CHECK ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_daily_five ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_select_daily_five ON public.crm_daily_five AS PERMISSIVE FOR SELECT TO public USING (((user_id = auth.uid()) OR (organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE ((organization_members.user_id = auth.uid()) AND (organization_members.role = ANY (ARRAY['admin'::text, 'manager'::text])))))));

ALTER TABLE public.crm_daily_five ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_update_daily_five ON public.crm_daily_five AS PERMISSIVE FOR UPDATE TO public USING (((user_id = auth.uid()) OR (organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE ((organization_members.user_id = auth.uid()) AND (organization_members.role = ANY (ARRAY['admin'::text, 'manager'::text])))))));

ALTER TABLE public.crm_deal_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_delete_deal_participants ON public.crm_deal_participants AS PERMISSIVE FOR DELETE TO public USING ((deal_id IN ( SELECT crm_deals.id
   FROM crm_deals
  WHERE (crm_deals.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_deal_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_insert_deal_participants ON public.crm_deal_participants AS PERMISSIVE FOR INSERT TO public WITH CHECK ((deal_id IN ( SELECT crm_deals.id
   FROM crm_deals
  WHERE (crm_deals.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_deal_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_select_deal_participants ON public.crm_deal_participants AS PERMISSIVE FOR SELECT TO public USING ((deal_id IN ( SELECT crm_deals.id
   FROM crm_deals
  WHERE (crm_deals.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_deal_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_update_deal_participants ON public.crm_deal_participants AS PERMISSIVE FOR UPDATE TO public USING ((deal_id IN ( SELECT crm_deals.id
   FROM crm_deals
  WHERE (crm_deals.organization_id IN ( SELECT organization_members.organization_id
           FROM organization_members
          WHERE (organization_members.user_id = auth.uid()))))));

ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_deals_org_delete ON public.crm_deals AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_deals_org_insert ON public.crm_deals AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_deals_org_select ON public.crm_deals AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_deals_org_update ON public.crm_deals AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_emails_org_delete ON public.crm_emails AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.crm_emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_emails_org_insert ON public.crm_emails AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.crm_emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_emails_org_select ON public.crm_emails AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_emails_org_update ON public.crm_emails AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_org_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_admin_upsert_crm_settings ON public.crm_org_settings AS PERMISSIVE FOR ALL TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE ((organization_members.user_id = auth.uid()) AND (organization_members.role = 'admin'::text)))));

ALTER TABLE public.crm_org_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_select_crm_settings ON public.crm_org_settings AS PERMISSIVE FOR SELECT TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_postmortems ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_insert_postmortems ON public.crm_postmortems AS PERMISSIVE FOR INSERT TO public WITH CHECK ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_postmortems ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_select_postmortems ON public.crm_postmortems AS PERMISSIVE FOR SELECT TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_postmortems ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_update_postmortems ON public.crm_postmortems AS PERMISSIVE FOR UPDATE TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_presentations ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_presentations_org_delete ON public.crm_presentations AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.crm_presentations ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_presentations_org_insert ON public.crm_presentations AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.crm_presentations ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_presentations_org_select ON public.crm_presentations AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_presentations ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_presentations_org_update ON public.crm_presentations AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_stage_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_insert_stage_history ON public.crm_stage_history AS PERMISSIVE FOR INSERT TO public WITH CHECK ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_stage_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_member_select_stage_history ON public.crm_stage_history AS PERMISSIVE FOR SELECT TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.crm_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_tasks_org_delete ON public.crm_tasks AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.crm_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_tasks_org_insert ON public.crm_tasks AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.crm_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_tasks_org_select ON public.crm_tasks AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.crm_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY crm_tasks_org_update ON public.crm_tasks AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.daily_coaching_focus ENABLE ROW LEVEL SECURITY;
CREATE POLICY daily_coaching_focus_select ON public.daily_coaching_focus AS PERMISSIVE FOR SELECT TO public USING ((is_org_member(organization_id) OR (user_id = auth.uid())));

ALTER TABLE public.dashboard_metric_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY dashboard_metric_settings_select ON public.dashboard_metric_settings AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.dashboard_metric_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY dashboard_metric_settings_update ON public.dashboard_metric_settings AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.dashboard_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY dv_select ON public.dashboard_views AS PERMISSIVE FOR SELECT TO public USING ((is_org_member(organization_id) AND (is_shared OR (owner_user_id = auth.uid()) OR is_org_admin(organization_id))));

ALTER TABLE public.dashboard_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY dv_write ON public.dashboard_views AS PERMISSIVE FOR ALL TO public USING (((owner_user_id = auth.uid()) OR is_org_admin(organization_id)));

ALTER TABLE public.decision_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY decision_actions_org_access ON public.decision_actions AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_actions.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_actions.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.decision_cases ENABLE ROW LEVEL SECURITY;
CREATE POLICY decision_cases_org_access ON public.decision_cases AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_cases.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_cases.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.decision_evidence ENABLE ROW LEVEL SECURITY;
CREATE POLICY decision_evidence_org_access ON public.decision_evidence AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_evidence.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_evidence.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.decision_model_performance ENABLE ROW LEVEL SECURITY;
CREATE POLICY decision_model_performance_member_access ON public.decision_model_performance AS PERMISSIVE FOR ALL TO authenticated USING (is_org_member(organization_id)) WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.decision_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY decision_predictions_org_access ON public.decision_predictions AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_predictions.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = decision_predictions.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.executive_intelligence_insights ENABLE ROW LEVEL SECURITY;
CREATE POLICY executive_insights_org_access ON public.executive_intelligence_insights AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = executive_intelligence_insights.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = executive_intelligence_insights.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.executive_intelligence_queries ENABLE ROW LEVEL SECURITY;
CREATE POLICY executive_queries_org_access ON public.executive_intelligence_queries AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = executive_intelligence_queries.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = executive_intelligence_queries.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.executive_intelligence_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY executive_snapshots_org_access ON public.executive_intelligence_snapshots AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = executive_intelligence_snapshots.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = executive_intelligence_snapshots.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

-- =========================
-- RLS POLICIES: f* through ip*
-- =========================

ALTER TABLE public.field_action_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_assign_read ON public.field_action_assignments AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_action_assignments.action_id) AND is_field_client_member(a.client_id)))));

ALTER TABLE public.field_action_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_assign_write ON public.field_action_assignments AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_action_assignments.action_id) AND is_field_client_member(a.client_id)))));

ALTER TABLE public.field_action_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_comments_insert ON public.field_action_comments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_action_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_comments_read ON public.field_action_comments AS PERMISSIVE FOR SELECT TO authenticated USING ((((action_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_action_comments.action_id) AND is_field_client_member(a.client_id))))) OR ((visit_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM field_visits v
  WHERE ((v.id = field_action_comments.visit_id) AND is_field_client_member(v.client_id)))))));

ALTER TABLE public.field_action_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_comments_update ON public.field_action_comments AS PERMISSIVE FOR UPDATE TO authenticated USING ((author_user_id = auth.uid()));

ALTER TABLE public.field_action_evidence ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_evidence_insert ON public.field_action_evidence AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_action_evidence.action_id) AND is_field_client_member(a.client_id)))));

ALTER TABLE public.field_action_evidence ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_evidence_read ON public.field_action_evidence AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_action_evidence.action_id) AND is_field_client_member(a.client_id)))));

ALTER TABLE public.field_action_status_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_history_insert ON public.field_action_status_history AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_action_status_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY action_history_read ON public.field_action_status_history AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_action_status_history.action_id) AND is_field_client_member(a.client_id)))));

ALTER TABLE public.field_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY actions_insert ON public.field_actions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY actions_read ON public.field_actions AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_actions ENABLE ROW LEVEL SECURITY;
CREATE POLICY actions_update ON public.field_actions AS PERMISSIVE FOR UPDATE TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_ai_detections ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_detections_read ON public.field_ai_detections AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_visits v
  WHERE ((v.id = field_ai_detections.visit_id) AND (is_field_client_member(v.client_id) OR (v.rep_user_id = auth.uid()))))));

ALTER TABLE public.field_ai_detections ENABLE ROW LEVEL SECURITY;
CREATE POLICY ai_detections_write ON public.field_ai_detections AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_visits v
  WHERE ((v.id = field_ai_detections.visit_id) AND (is_field_client_member(v.client_id) OR (v.rep_user_id = auth.uid()))))));

ALTER TABLE public.field_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY assets_read ON public.field_assets AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY assets_write ON public.field_assets AS PERMISSIVE FOR ALL TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY assignments_insert ON public.field_assignments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (is_field_client_member(client_id));

ALTER TABLE public.field_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY assignments_read ON public.field_assignments AS PERMISSIVE FOR SELECT TO authenticated USING ((is_field_client_member(client_id) OR (rep_user_id = auth.uid())));

ALTER TABLE public.field_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY assignments_update ON public.field_assignments AS PERMISSIVE FOR UPDATE TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_clients ENABLE ROW LEVEL SECURITY;
CREATE POLICY clients_read ON public.field_clients AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(id));

ALTER TABLE public.field_clients ENABLE ROW LEVEL SECURITY;
CREATE POLICY clients_write ON public.field_clients AS PERMISSIVE FOR ALL TO authenticated USING (is_field_client_member(id));

ALTER TABLE public.field_competitive_intel ENABLE ROW LEVEL SECURITY;
CREATE POLICY competitive_insert ON public.field_competitive_intel AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_competitive_intel ENABLE ROW LEVEL SECURITY;
CREATE POLICY competitive_read ON public.field_competitive_intel AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_visits v
  WHERE ((v.id = field_competitive_intel.visit_id) AND (is_field_client_member(v.client_id) OR (v.rep_user_id = auth.uid()))))));

ALTER TABLE public.field_escalations ENABLE ROW LEVEL SECURITY;
CREATE POLICY escalations_read ON public.field_escalations AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_escalations.action_id) AND is_field_client_member(a.client_id)))));

ALTER TABLE public.field_escalations ENABLE ROW LEVEL SECURITY;
CREATE POLICY escalations_write ON public.field_escalations AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_actions a
  WHERE ((a.id = field_escalations.action_id) AND is_field_client_member(a.client_id)))));

ALTER TABLE public.field_exports ENABLE ROW LEVEL SECURITY;
CREATE POLICY exports_insert ON public.field_exports AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_exports ENABLE ROW LEVEL SECURITY;
CREATE POLICY exports_read ON public.field_exports AS PERMISSIVE FOR SELECT TO authenticated USING (((client_id IS NULL) OR is_field_client_member(client_id)));

ALTER TABLE public.field_findings ENABLE ROW LEVEL SECURITY;
CREATE POLICY findings_insert ON public.field_findings AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_findings ENABLE ROW LEVEL SECURITY;
CREATE POLICY findings_read ON public.field_findings AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_findings ENABLE ROW LEVEL SECURITY;
CREATE POLICY findings_update ON public.field_findings AS PERMISSIVE FOR UPDATE TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_manufacturer_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY mfr_users_read ON public.field_manufacturer_users AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_manufacturer_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY mfr_users_write ON public.field_manufacturer_users AS PERMISSIVE FOR ALL TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_media ENABLE ROW LEVEL SECURITY;
CREATE POLICY media_insert ON public.field_media AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_media ENABLE ROW LEVEL SECURITY;
CREATE POLICY media_read ON public.field_media AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_visits v
  WHERE ((v.id = field_media.visit_id) AND (is_field_client_member(v.client_id) OR (v.rep_user_id = auth.uid()))))));

ALTER TABLE public.field_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notif_insert ON public.field_notifications AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notif_read ON public.field_notifications AS PERMISSIVE FOR SELECT TO authenticated USING ((recipient_user_id = auth.uid()));

ALTER TABLE public.field_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notif_update ON public.field_notifications AS PERMISSIVE FOR UPDATE TO authenticated USING ((recipient_user_id = auth.uid()));

ALTER TABLE public.field_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY programs_read ON public.field_programs AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_programs ENABLE ROW LEVEL SECURITY;
CREATE POLICY programs_write ON public.field_programs AS PERMISSIVE FOR ALL TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_replacement_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY repl_req_read ON public.field_replacement_requests AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_replacement_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY repl_req_write ON public.field_replacement_requests AS PERMISSIVE FOR ALL TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_retailer_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY rtl_users_read ON public.field_retailer_users AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.field_retailers ENABLE ROW LEVEL SECURITY;
CREATE POLICY retailers_read ON public.field_retailers AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.field_score_components ENABLE ROW LEVEL SECURITY;
CREATE POLICY score_comp_read ON public.field_score_components AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_store_scores s
  WHERE ((s.id = field_score_components.store_score_id) AND is_field_client_member(s.client_id)))));

ALTER TABLE public.field_score_components ENABLE ROW LEVEL SECURITY;
CREATE POLICY score_comp_write ON public.field_score_components AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_store_scores s
  WHERE ((s.id = field_score_components.store_score_id) AND is_field_client_member(s.client_id)))));

ALTER TABLE public.field_service_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY svc_req_read ON public.field_service_requests AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_service_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY svc_req_write ON public.field_service_requests AS PERMISSIVE FOR ALL TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_store_contacts ENABLE ROW LEVEL SECURITY;
CREATE POLICY store_contacts_read ON public.field_store_contacts AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.field_store_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY scores_insert ON public.field_store_scores AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_store_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY scores_read ON public.field_store_scores AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_stores ENABLE ROW LEVEL SECURITY;
CREATE POLICY stores_read ON public.field_stores AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.field_training_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY training_insert ON public.field_training_sessions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.field_training_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY training_read ON public.field_training_sessions AS PERMISSIVE FOR SELECT TO authenticated USING (is_field_client_member(client_id));

ALTER TABLE public.field_visit_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY visit_tasks_read ON public.field_visit_tasks AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_visits v
  WHERE ((v.id = field_visit_tasks.visit_id) AND (is_field_client_member(v.client_id) OR (v.rep_user_id = auth.uid()))))));

ALTER TABLE public.field_visit_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY visit_tasks_write ON public.field_visit_tasks AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM field_visits v
  WHERE ((v.id = field_visit_tasks.visit_id) AND (is_field_client_member(v.client_id) OR (v.rep_user_id = auth.uid()))))));

ALTER TABLE public.field_visits ENABLE ROW LEVEL SECURITY;
CREATE POLICY visits_insert ON public.field_visits AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((rep_user_id = auth.uid()));

ALTER TABLE public.field_visits ENABLE ROW LEVEL SECURITY;
CREATE POLICY visits_read ON public.field_visits AS PERMISSIVE FOR SELECT TO authenticated USING ((is_field_client_member(client_id) OR (rep_user_id = auth.uid())));

ALTER TABLE public.field_visits ENABLE ROW LEVEL SECURITY;
CREATE POLICY visits_update ON public.field_visits AS PERMISSIVE FOR UPDATE TO authenticated USING ((is_field_client_member(client_id) OR (rep_user_id = auth.uid())));

ALTER TABLE public.foundation_facts ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_facts ON public.foundation_facts AS PERMISSIVE FOR SELECT TO authenticated USING (((status = 'verified'::text) OR ((auth.jwt() ->> 'aiq_role'::text) = ANY (ARRAY['steward'::text, 'admin'::text]))));

ALTER TABLE public.foundation_facts ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_steward_update_facts ON public.foundation_facts AS PERMISSIVE FOR UPDATE TO authenticated USING (((auth.jwt() ->> 'aiq_role'::text) = ANY (ARRAY['steward'::text, 'admin'::text])));

ALTER TABLE public.foundation_facts ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_steward_write_facts ON public.foundation_facts AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((auth.jwt() ->> 'aiq_role'::text) = ANY (ARRAY['steward'::text, 'admin'::text, 'extractor'::text])));

ALTER TABLE public.foundation_object_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_otypes ON public.foundation_object_types AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.foundation_objects ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_objects ON public.foundation_objects AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.foundation_relationship_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_rtypes ON public.foundation_relationship_types AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.foundation_relationships ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_rels ON public.foundation_relationships AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.installation_requirements ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_read ON public.installation_requirements AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.installation_requirements ENABLE ROW LEVEL SECURITY;
CREATE POLICY sr_full ON public.installation_requirements AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE public.intel_companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY intel_co_read ON public.intel_companies AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.intel_companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY intel_co_update ON public.intel_companies AS PERMISSIVE FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.intel_companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY intel_co_write ON public.intel_companies AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.intel_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY intel_loc_read ON public.intel_locations AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.intel_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY intel_loc_write ON public.intel_locations AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.intel_news ENABLE ROW LEVEL SECURITY;
CREATE POLICY intel_news_read ON public.intel_news AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.intel_news ENABLE ROW LEVEL SECURITY;
CREATE POLICY intel_news_write ON public.intel_news AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.intelligence_context_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_context_cache_org_access ON public.intelligence_context_cache AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_context_cache.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_context_cache.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.intelligence_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_entities_anon_insert ON public.intelligence_entities AS PERMISSIVE FOR INSERT TO anon WITH CHECK (true);

ALTER TABLE public.intelligence_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_entities_anon_select ON public.intelligence_entities AS PERMISSIVE FOR SELECT TO anon USING (true);

ALTER TABLE public.intelligence_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_entities_anon_update ON public.intelligence_entities AS PERMISSIVE FOR UPDATE TO anon USING (true) WITH CHECK (true);

ALTER TABLE public.intelligence_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_entities_auth_insert ON public.intelligence_entities AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.intelligence_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_entities_auth_update ON public.intelligence_entities AS PERMISSIVE FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.intelligence_entities ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_entities_org_access ON public.intelligence_entities AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_entities.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_entities.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.intelligence_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_events_org_access ON public.intelligence_events AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_events.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_events.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.intelligence_learning_signals ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_learning_signals_org_access ON public.intelligence_learning_signals AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_learning_signals.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_learning_signals.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.intelligence_outcomes ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_outcomes_org_access ON public.intelligence_outcomes AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_outcomes.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_outcomes.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.intelligence_recommendations ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_recommendations_org_access ON public.intelligence_recommendations AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_recommendations.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_recommendations.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

ALTER TABLE public.intelligence_timelines ENABLE ROW LEVEL SECURITY;
CREATE POLICY intelligence_timelines_org_access ON public.intelligence_timelines AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_timelines.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM organization_members m
  WHERE ((m.organization_id = intelligence_timelines.organization_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (COALESCE(m.status, 'active'::text) = 'active'::text)))));

-- =========================
-- RLS POLICIES: iq* through n*
-- =========================

ALTER TABLE public.iq_audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_audit_insert ON public.iq_audit_events AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_audit_select ON public.iq_audit_events AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_interactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_interactions_insert ON public.iq_customer_interactions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_interactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_interactions_select ON public.iq_customer_interactions AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_interactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_interactions_update ON public.iq_customer_interactions AS PERMISSIVE FOR UPDATE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_product_interest ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_product_interest_delete ON public.iq_customer_product_interest AS PERMISSIVE FOR DELETE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_product_interest ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_product_interest_insert ON public.iq_customer_product_interest AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_product_interest ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_product_interest_select ON public.iq_customer_product_interest AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_product_interest ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_product_interest_update ON public.iq_customer_product_interest AS PERMISSIVE FOR UPDATE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_waiting_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_waiting_insert ON public.iq_customer_waiting_queue AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_waiting_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_waiting_select ON public.iq_customer_waiting_queue AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_customer_waiting_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_waiting_update ON public.iq_customer_waiting_queue AS PERMISSIVE FOR UPDATE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_floor_managers ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_managers_insert ON public.iq_floor_managers AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.iq_floor_managers ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_managers_select ON public.iq_floor_managers AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_floor_managers ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_managers_update ON public.iq_floor_managers AS PERMISSIVE FOR UPDATE TO authenticated USING (is_org_admin(organization_id));

ALTER TABLE public.iq_hourly_traffic_summaries ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_hourly_insert ON public.iq_hourly_traffic_summaries AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_hourly_traffic_summaries ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_hourly_select ON public.iq_hourly_traffic_summaries AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_integration_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_integration_insert ON public.iq_integration_links AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.iq_integration_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_integration_select ON public.iq_integration_links AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_integration_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_integration_update ON public.iq_integration_links AS PERMISSIVE FOR UPDATE TO authenticated USING (is_org_admin(organization_id));

ALTER TABLE public.iq_intelligence_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_intel_insert ON public.iq_intelligence_events AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_intelligence_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_intel_select ON public.iq_intelligence_events AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_missed_and_potential_missed_ups ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_missed_insert ON public.iq_missed_and_potential_missed_ups AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_missed_and_potential_missed_ups ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_missed_select ON public.iq_missed_and_potential_missed_ups AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_open_rotation_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_rotation_insert ON public.iq_open_rotation_sessions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.iq_open_rotation_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_rotation_select ON public.iq_open_rotation_sessions AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_open_rotation_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_rotation_update ON public.iq_open_rotation_sessions AS PERMISSIVE FOR UPDATE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_queue_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_notifications_insert ON public.iq_queue_notifications AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_queue_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_notifications_select ON public.iq_queue_notifications AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_queue_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_snapshots_insert ON public.iq_queue_snapshots AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_queue_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_snapshots_select ON public.iq_queue_snapshots AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_shift_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_shifts_insert ON public.iq_shift_records AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_shift_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_shifts_select ON public.iq_shift_records AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_shift_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_shifts_update ON public.iq_shift_records AS PERMISSIVE FOR UPDATE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_staffing_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_staffing_insert ON public.iq_staffing_predictions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_staffing_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_staffing_select ON public.iq_staffing_predictions AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_status_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_status_insert ON public.iq_status_sessions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_status_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_status_select ON public.iq_status_sessions AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_status_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_status_update ON public.iq_status_sessions AS PERMISSIVE FOR UPDATE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_store_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_settings_insert ON public.iq_store_settings AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.iq_store_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_settings_select ON public.iq_store_settings AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_store_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_settings_update ON public.iq_store_settings AS PERMISSIVE FOR UPDATE TO authenticated USING (is_org_admin(organization_id));

ALTER TABLE public.iq_traffic_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_traffic_evt_insert ON public.iq_traffic_events AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_traffic_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_traffic_evt_select ON public.iq_traffic_events AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_traffic_sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_traffic_src_insert ON public.iq_traffic_sources AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_traffic_sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_traffic_src_select ON public.iq_traffic_sources AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_up_disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_disputes_insert ON public.iq_up_disputes AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_up_disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_disputes_select ON public.iq_up_disputes AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_up_disputes ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_disputes_update ON public.iq_up_disputes AS PERMISSIVE FOR UPDATE TO authenticated USING (is_org_admin(organization_id));

ALTER TABLE public.iq_up_queue_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_queue_insert ON public.iq_up_queue_entries AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_up_queue_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_queue_select ON public.iq_up_queue_entries AS PERMISSIVE FOR SELECT TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.iq_up_queue_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY iq_queue_update ON public.iq_up_queue_entries AS PERMISSIVE FOR UPDATE TO authenticated USING ((organization_id IN ( SELECT my_org_ids() AS my_org_ids)));

ALTER TABLE public.kpi_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY kpi_events_select ON public.kpi_events AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.media_discovery_candidates ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_full_mdc ON public.media_discovery_candidates AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.media_discovery_candidates ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_role_full_mdc ON public.media_discovery_candidates AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE public.media_discovery_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_full_mdr ON public.media_discovery_runs AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.media_discovery_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_role_full_mdr ON public.media_discovery_runs AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE public.media_source_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_full_msr ON public.media_source_registry AS PERMISSIVE FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.media_source_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_role_full_msr ON public.media_source_registry AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE public.metric_definitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY md_select ON public.metric_definitions AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.metric_definitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY md_write ON public.metric_definitions AS PERMISSIVE FOR ALL TO public USING (is_org_admin(organization_id));

ALTER TABLE public.metric_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY ms_select ON public.metric_snapshots AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.metric_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY ms_write ON public.metric_snapshots AS PERMISSIVE FOR ALL TO public USING (is_org_member(organization_id)) WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.mfr_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin invites" ON public.mfr_invites AS PERMISSIVE FOR ALL TO public USING (is_admin()) WITH CHECK (is_admin());

ALTER TABLE public.mfr_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY invites_admin_all ON public.mfr_invites AS PERMISSIVE FOR ALL TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)) WITH CHECK (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.mfr_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read invite by code" ON public.mfr_invites AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));

ALTER TABLE public.mfr_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product iq own membership read" ON public.mfr_members AS PERMISSIVE FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)));

ALTER TABLE public.mfr_user_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product iq own role read" ON public.mfr_user_roles AS PERMISSIVE FOR SELECT TO authenticated USING (((user_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)));

ALTER TABLE public.mfr_vendor_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY groups_admin ON public.mfr_vendor_groups AS PERMISSIVE FOR ALL TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)) WITH CHECK (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.mfr_vendor_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY groups_read ON public.mfr_vendor_groups AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.mfr_vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "product iq platform manages vendors" ON public.mfr_vendors AS PERMISSIVE FOR ALL TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)) WITH CHECK (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.mfr_vendors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read vendors" ON public.mfr_vendors AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));

-- =========================
-- RLS POLICIES: o* through r*
-- =========================

ALTER TABLE public.org_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_invites_delete ON public.org_invites AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_invites_insert ON public.org_invites AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.org_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_invites_select ON public.org_invites AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.org_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_invites_self_accept ON public.org_invites AS PERMISSIVE FOR UPDATE TO authenticated USING ((invited_email = (( SELECT users.email
   FROM auth.users
  WHERE (users.id = auth.uid())))::text));

ALTER TABLE public.org_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_invites_self_select ON public.org_invites AS PERMISSIVE FOR SELECT TO authenticated USING ((invited_email = (( SELECT users.email
   FROM auth.users
  WHERE (users.id = auth.uid())))::text));

ALTER TABLE public.org_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_invites_update ON public.org_invites AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_kpis ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_kpis_delete ON public.org_kpis AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_kpis ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_kpis_select ON public.org_kpis AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.org_kpis ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_kpis_update ON public.org_kpis AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_kpis ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_kpis_write ON public.org_kpis AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.org_location_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY olm_select ON public.org_location_members AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.org_location_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY olm_write ON public.org_location_members AS PERMISSIVE FOR ALL TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_locations_select ON public.org_locations AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.org_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_locations_write ON public.org_locations AS PERMISSIVE FOR ALL TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_roles_select ON public.org_roles AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.org_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_roles_update ON public.org_roles AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_roles_write ON public.org_roles AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.org_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_targets_select ON public.org_targets AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.org_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_targets_update ON public.org_targets AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.org_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_targets_write ON public.org_targets AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.organization_brands ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin manage org brands" ON public.organization_brands AS PERMISSIVE FOR ALL TO public USING ((is_admin() OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.user_id = auth.uid()) AND (om.organization_id = organization_brands.organization_id) AND (om.role = ANY (ARRAY['owner'::text, 'admin'::text, 'manager'::text]))))))) WITH CHECK ((is_admin() OR (EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.user_id = auth.uid()) AND (om.organization_id = organization_brands.organization_id) AND (om.role = ANY (ARRAY['owner'::text, 'admin'::text, 'manager'::text])))))));

ALTER TABLE public.organization_brands ENABLE ROW LEVEL SECURITY;
CREATE POLICY "read org brands" ON public.organization_brands AS PERMISSIVE FOR SELECT TO public USING ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.user_id = auth.uid()) AND (om.organization_id = organization_brands.organization_id)))));

ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can join orgs" ON public.organization_members AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY members_admin ON public.organization_members AS PERMISSIVE FOR ALL TO public USING (is_org_admin(organization_id));

ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY members_select ON public.organization_members AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated users can create orgs" ON public.organizations AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_select ON public.organizations AS PERMISSIVE FOR SELECT TO public USING (is_org_member(id));

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY org_update ON public.organizations AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(id));

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_org_read ON public.organizations AS PERMISSIVE FOR SELECT TO anon USING (true);

ALTER TABLE public.persona_communication_protocol ENABLE ROW LEVEL SECURITY;
CREATE POLICY comm_protocol_select ON public.persona_communication_protocol AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.persona_communication_protocol ENABLE ROW LEVEL SECURITY;
CREATE POLICY comm_protocol_update ON public.persona_communication_protocol AS PERMISSIVE FOR UPDATE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.persona_communication_protocol ENABLE ROW LEVEL SECURITY;
CREATE POLICY comm_protocol_write ON public.persona_communication_protocol AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_admin(organization_id));

ALTER TABLE public.pim_marketing_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_marketing_assets_delete ON public.pim_marketing_assets AS PERMISSIVE FOR DELETE TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_marketing_assets.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_marketing_assets.brand_id) AS piq_can_manage_brand))));

ALTER TABLE public.pim_marketing_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_marketing_assets_read ON public.pim_marketing_assets AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_marketing_assets.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_marketing_assets.brand_id) AS piq_can_manage_brand)) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_retailer_can_see(pim_marketing_assets.available_from, pim_marketing_assets.available_until, pim_marketing_assets.embargoed, pim_marketing_assets.audience_tiers, pim_marketing_assets.exclusive_codes) AS piq_retailer_can_see) AND (((product_id IS NOT NULL) AND ( SELECT private.piq_carries_product(pim_marketing_assets.product_id) AS piq_carries_product)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_carries_brand_id(pim_marketing_assets.brand_id) AS piq_carries_brand_id))))));

ALTER TABLE public.pim_marketing_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_marketing_assets_update ON public.pim_marketing_assets AS PERMISSIVE FOR UPDATE TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_marketing_assets.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_marketing_assets.brand_id) AS piq_can_manage_brand))));

ALTER TABLE public.pim_marketing_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_marketing_assets_write ON public.pim_marketing_assets AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_marketing_assets.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_marketing_assets.brand_id) AS piq_can_manage_brand))));

ALTER TABLE public.pim_price_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY price_history_insert ON public.pim_price_history AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.pim_price_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY price_history_read ON public.pim_price_history AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.pim_price_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_price_ins ON public.pim_price_history AS PERMISSIVE FOR INSERT TO anon WITH CHECK (true);

ALTER TABLE public.pim_product_accessories ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_accessories_delete ON public.pim_product_accessories AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_accessories.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_accessories ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_accessories_insert ON public.pim_product_accessories AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_accessories.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_accessories ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_accessories_read ON public.pim_product_accessories AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_product_accessories.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_product_accessories.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_product_accessories.product_id) AS piq_carries_product))));

ALTER TABLE public.pim_product_accessories ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_accessories_update ON public.pim_product_accessories AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_accessories.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_accessories.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_certifications_delete ON public.pim_product_certifications AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_certifications.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_certifications_insert ON public.pim_product_certifications AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_certifications.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_certifications_read ON public.pim_product_certifications AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_product_certifications.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_product_certifications.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_product_certifications.product_id) AS piq_carries_product))));

ALTER TABLE public.pim_product_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_certifications_update ON public.pim_product_certifications AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_certifications.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_certifications.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_cert_ins ON public.pim_product_certifications AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.pim_product_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_cert_read ON public.pim_product_certifications AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.pim_product_certifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_cert_upd ON public.pim_product_certifications AS PERMISSIVE FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_dimensions_delete ON public.pim_product_dimensions AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_dimensions.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_dimensions_insert ON public.pim_product_dimensions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_dimensions.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_dimensions_read ON public.pim_product_dimensions AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_product_dimensions.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_product_dimensions.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_product_dimensions.product_id) AS piq_carries_product))));

ALTER TABLE public.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_dimensions_update ON public.pim_product_dimensions AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_dimensions.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_dimensions.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_dim_ins ON public.pim_product_dimensions AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_dim_read ON public.pim_product_dimensions AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_dim_upd ON public.pim_product_dimensions AS PERMISSIVE FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.pim_product_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_documents_delete ON public.pim_product_documents AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_documents.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_documents_insert ON public.pim_product_documents AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_documents.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_documents_read ON public.pim_product_documents AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_product_documents.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_product_documents.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_product_documents.product_id) AS piq_carries_product) AND ( SELECT private.piq_retailer_can_see(pim_product_documents.available_from, pim_product_documents.available_until, pim_product_documents.embargoed, pim_product_documents.audience_tiers, pim_product_documents.exclusive_codes) AS piq_retailer_can_see))));

ALTER TABLE public.pim_product_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_documents_update ON public.pim_product_documents AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_documents.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_documents.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_doc_ins ON public.pim_product_documents AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.pim_product_documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_doc_read ON public.pim_product_documents AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.pim_product_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_features_delete ON public.pim_product_features AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_features.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_features_insert ON public.pim_product_features AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_features.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_features_read ON public.pim_product_features AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_product_features.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_product_features.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_product_features.product_id) AS piq_carries_product))));

ALTER TABLE public.pim_product_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_features_update ON public.pim_product_features AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_features.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_features.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_feat_del ON public.pim_product_features AS PERMISSIVE FOR DELETE TO anon, authenticated USING (true);

ALTER TABLE public.pim_product_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_feat_ins ON public.pim_product_features AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.pim_product_features ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_feat_read ON public.pim_product_features AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.pim_product_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_images_delete ON public.pim_product_images AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_images.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_images_insert ON public.pim_product_images AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_images.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_images_read ON public.pim_product_images AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_product_images.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_product_images.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_product_images.product_id) AS piq_carries_product) AND ( SELECT private.piq_retailer_can_see(pim_product_images.available_from, pim_product_images.available_until, pim_product_images.embargoed, pim_product_images.audience_tiers, pim_product_images.exclusive_codes) AS piq_retailer_can_see))));

ALTER TABLE public.pim_product_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_images_update ON public.pim_product_images AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_images.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_images.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_img_del ON public.pim_product_images AS PERMISSIVE FOR DELETE TO anon, authenticated USING (true);

ALTER TABLE public.pim_product_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_img_ins ON public.pim_product_images AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.pim_product_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY scraper_img_read ON public.pim_product_images AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.pim_product_rebates ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_rebates_delete ON public.pim_product_rebates AS PERMISSIVE FOR DELETE TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_product_rebates.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_product_rebates.brand_id) AS piq_can_manage_brand))));

ALTER TABLE public.pim_product_rebates ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_rebates_read ON public.pim_product_rebates AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_product_rebates.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_product_rebates.brand_id) AS piq_can_manage_brand)) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_retailer_can_see(pim_product_rebates.available_from, pim_product_rebates.available_until, pim_product_rebates.embargoed, pim_product_rebates.audience_tiers, pim_product_rebates.exclusive_codes) AS piq_retailer_can_see) AND (((product_id IS NOT NULL) AND ( SELECT private.piq_carries_product(pim_product_rebates.product_id) AS piq_carries_product)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_carries_brand_id(pim_product_rebates.brand_id) AS piq_carries_brand_id))))));

ALTER TABLE public.pim_product_rebates ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_rebates_update ON public.pim_product_rebates AS PERMISSIVE FOR UPDATE TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_product_rebates.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_product_rebates.brand_id) AS piq_can_manage_brand))));

ALTER TABLE public.pim_product_rebates ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_rebates_write ON public.pim_product_rebates AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ((product_id IS NOT NULL) AND ( SELECT private.piq_can_manage_product_assets(pim_product_rebates.product_id) AS piq_can_manage_product_assets)) OR ((brand_id IS NOT NULL) AND ( SELECT private.piq_can_manage_brand(pim_product_rebates.brand_id) AS piq_can_manage_brand))));

ALTER TABLE public.pim_product_videos ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_videos_delete ON public.pim_product_videos AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_videos.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_videos ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_videos_insert ON public.pim_product_videos AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_videos.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_product_videos ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_videos_read ON public.pim_product_videos AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_product_videos.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_product_videos.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_product_videos.product_id) AS piq_carries_product) AND ( SELECT private.piq_retailer_can_see(pim_product_videos.available_from, pim_product_videos.available_until, pim_product_videos.embargoed, pim_product_videos.audience_tiers, pim_product_videos.exclusive_codes) AS piq_retailer_can_see))));

ALTER TABLE public.pim_product_videos ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_product_videos_update ON public.pim_product_videos AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_product_videos.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_product_videos.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_retailer_prices ENABLE ROW LEVEL SECURITY;
CREATE POLICY retailer_prices_read ON public.pim_retailer_prices AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);

ALTER TABLE public.pim_retailer_prices ENABLE ROW LEVEL SECURITY;
CREATE POLICY retailer_prices_update ON public.pim_retailer_prices AS PERMISSIVE FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.pim_retailer_prices ENABLE ROW LEVEL SECURITY;
CREATE POLICY retailer_prices_write ON public.pim_retailer_prices AS PERMISSIVE FOR INSERT TO anon, authenticated WITH CHECK (true);

ALTER TABLE public.pim_warranty_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_warranty_details_delete ON public.pim_warranty_details AS PERMISSIVE FOR DELETE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_warranty_details.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_warranty_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_warranty_details_insert ON public.pim_warranty_details AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_warranty_details.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pim_warranty_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_warranty_details_read ON public.pim_warranty_details AS PERMISSIVE FOR SELECT TO authenticated USING ((( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR ( SELECT private.piq_can_manage_product_assets(pim_warranty_details.product_id) AS piq_can_manage_product_assets) OR (( SELECT private.piq_is_retailer() AS piq_is_retailer) AND ( SELECT private.piq_product_is_published(pim_warranty_details.product_id) AS piq_product_is_published) AND ( SELECT private.piq_carries_product(pim_warranty_details.product_id) AS piq_carries_product))));

ALTER TABLE public.pim_warranty_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY pim_warranty_details_update ON public.pim_warranty_details AS PERMISSIVE FOR UPDATE TO authenticated USING (( SELECT private.piq_can_manage_product_assets(pim_warranty_details.product_id) AS piq_can_manage_product_assets)) WITH CHECK (( SELECT private.piq_can_manage_product_assets(pim_warranty_details.product_id) AS piq_can_manage_product_assets));

ALTER TABLE public.pipeline_stages ENABLE ROW LEVEL SECURITY;
CREATE POLICY pipeline_stages_org_delete ON public.pipeline_stages AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.pipeline_stages ENABLE ROW LEVEL SECURITY;
CREATE POLICY pipeline_stages_org_insert ON public.pipeline_stages AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.pipeline_stages ENABLE ROW LEVEL SECURITY;
CREATE POLICY pipeline_stages_org_select ON public.pipeline_stages AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.pipeline_stages ENABLE ROW LEVEL SECURITY;
CREATE POLICY pipeline_stages_org_update ON public.pipeline_stages AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.piq_notification_reads ENABLE ROW LEVEL SECURITY;
CREATE POLICY notif_reads_self ON public.piq_notification_reads AS PERMISSIVE FOR ALL TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

ALTER TABLE public.piq_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notif_admin_write ON public.piq_notifications AS PERMISSIVE FOR ALL TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)) WITH CHECK (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.piq_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY notif_read ON public.piq_notifications AS PERMISSIVE FOR SELECT TO authenticated USING (((publish_at <= now()) AND ((expires_at IS NULL) OR (expires_at > now())) AND (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin) OR (( SELECT private.piq_audience_match(piq_notifications.audience_tiers, piq_notifications.exclusive_codes) AS piq_audience_match) AND ((brand_name IS NULL) OR ( SELECT private.piq_carries_brand_name(piq_notifications.brand_name) AS piq_carries_brand_name))))));

ALTER TABLE public.piq_retailer_brands ENABLE ROW LEVEL SECURITY;
CREATE POLICY rb_admin_all ON public.piq_retailer_brands AS PERMISSIVE FOR ALL TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)) WITH CHECK (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.piq_retailer_brands ENABLE ROW LEVEL SECURITY;
CREATE POLICY rb_self_read ON public.piq_retailer_brands AS PERMISSIVE FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR ( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)));

ALTER TABLE public.piq_retailer_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY rp_admin_all ON public.piq_retailer_profiles AS PERMISSIVE FOR ALL TO authenticated USING (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)) WITH CHECK (( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin));

ALTER TABLE public.piq_retailer_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY rp_self_read ON public.piq_retailer_profiles AS PERMISSIVE FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR ( SELECT private.product_iq_is_platform_admin() AS product_iq_is_platform_admin)));

ALTER TABLE public.privacy_jurisdictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_jurisdictions ON public.privacy_jurisdictions AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.privacy_retention_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_read_retention ON public.privacy_retention_policies AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.product_design_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pda_delete ON public.product_design_assets AS PERMISSIVE FOR DELETE TO authenticated USING ((private.product_iq_is_platform_admin() OR private.piq_can_manage_product_assets(product_id)));

ALTER TABLE public.product_design_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pda_insert ON public.product_design_assets AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.product_design_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pda_read ON public.product_design_assets AS PERMISSIVE FOR SELECT TO authenticated USING ((private.product_iq_is_platform_admin() OR private.piq_can_manage_product_assets(product_id) OR (private.piq_is_retailer() AND private.piq_product_is_published(product_id) AND private.piq_carries_product(product_id) AND private.piq_retailer_can_see(available_from, available_until, embargoed, audience_tiers, exclusive_codes))));

ALTER TABLE public.product_design_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pda_update ON public.product_design_assets AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.product_iq_is_platform_admin() OR private.piq_can_manage_product_assets(product_id)));

ALTER TABLE public.product_installation_geometry ENABLE ROW LEVEL SECURITY;
CREATE POLICY "geometry authenticated read" ON public.product_installation_geometry AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.product_installation_geometry ENABLE ROW LEVEL SECURITY;
CREATE POLICY "geometry platform write" ON public.product_installation_geometry AS PERMISSIVE FOR ALL TO authenticated USING ((EXISTS ( SELECT 1
   FROM product_iq_platform_roles r
  WHERE ((r.user_id = auth.uid()) AND (r.status = 'active'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM product_iq_platform_roles r
  WHERE ((r.user_id = auth.uid()) AND (r.status = 'active'::text)))));

ALTER TABLE public.product_iq_brand_scopes ENABLE ROW LEVEL SECURITY;
CREATE POLICY piq_scopes_read ON public.product_iq_brand_scopes AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.product_iq_governance_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY piq_audit_insert ON public.product_iq_governance_audit_log AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.product_iq_governance_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY piq_audit_read ON public.product_iq_governance_audit_log AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.product_iq_platform_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY piq_roles_read ON public.product_iq_platform_roles AS PERMISSIVE FOR SELECT TO authenticated USING ((user_id = auth.uid()));

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY products_org_delete ON public.products AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY products_org_insert ON public.products AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY products_org_select ON public.products AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY products_org_update ON public.products AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_self ON public.profiles AS PERMISSIVE FOR ALL TO public USING ((user_id = auth.uid()));

ALTER TABLE public.recording_transcripts ENABLE ROW LEVEL SECURITY;
CREATE POLICY recording_transcripts_org_delete ON public.recording_transcripts AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.recording_transcripts ENABLE ROW LEVEL SECURITY;
CREATE POLICY recording_transcripts_org_insert ON public.recording_transcripts AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.recording_transcripts ENABLE ROW LEVEL SECURITY;
CREATE POLICY recording_transcripts_org_select ON public.recording_transcripts AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.recording_transcripts ENABLE ROW LEVEL SECURITY;
CREATE POLICY recording_transcripts_org_update ON public.recording_transcripts AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.retailer_buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_read ON public.retailer_buying_groups AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.retailer_buying_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY sr_full ON public.retailer_buying_groups AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

ALTER TABLE public.retailer_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated read" ON public.retailer_locations AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.retailer_locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Service role full access" ON public.retailer_locations AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);

-- =========================
-- RLS POLICIES: s* through z*
-- =========================

ALTER TABLE public.sales_recordings ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_recordings_org_delete ON public.sales_recordings AS PERMISSIVE FOR DELETE TO public USING (is_org_admin(organization_id));

ALTER TABLE public.sales_recordings ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_recordings_org_insert ON public.sales_recordings AS PERMISSIVE FOR INSERT TO public WITH CHECK (is_org_member(organization_id));

ALTER TABLE public.sales_recordings ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_recordings_org_select ON public.sales_recordings AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.sales_recordings ENABLE ROW LEVEL SECURITY;
CREATE POLICY sales_recordings_org_update ON public.sales_recordings AS PERMISSIVE FOR UPDATE TO public USING (is_org_member(organization_id));

ALTER TABLE public.sales_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY st_select ON public.sales_transactions AS PERMISSIVE FOR SELECT TO public USING (is_org_member(organization_id));

ALTER TABLE public.sales_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY st_write ON public.sales_transactions AS PERMISSIVE FOR ALL TO public USING (is_org_member(organization_id));

ALTER TABLE public.speciq_approval_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_history_insert ON public.speciq_approval_history AS PERMISSIVE FOR INSERT TO public WITH CHECK (true);

ALTER TABLE public.speciq_approval_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_history_select ON public.speciq_approval_history AS PERMISSIVE FOR SELECT TO public USING (true);

ALTER TABLE public.speciq_extension_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY extension_requests_insert ON public.speciq_extension_requests AS PERMISSIVE FOR INSERT TO public WITH CHECK (true);

ALTER TABLE public.speciq_extension_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY extension_requests_select ON public.speciq_extension_requests AS PERMISSIVE FOR SELECT TO public USING (true);

ALTER TABLE public.speciq_extension_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY extension_requests_update ON public.speciq_extension_requests AS PERMISSIVE FOR UPDATE TO public USING (true);

ALTER TABLE public.speciq_followup_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_followup_sequences_delete ON public.speciq_followup_sequences AS PERMISSIVE FOR DELETE TO public USING (true);

ALTER TABLE public.speciq_followup_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_followup_sequences_insert ON public.speciq_followup_sequences AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_followup_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_followup_sequences_select ON public.speciq_followup_sequences AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_followup_sequences ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_followup_sequences_update ON public.speciq_followup_sequences AS PERMISSIVE FOR UPDATE TO public USING (true);

ALTER TABLE public.speciq_package_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_events_insert ON public.speciq_package_events AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_package_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_events_select ON public.speciq_package_events AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_package_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_products_delete ON public.speciq_package_products AS PERMISSIVE FOR DELETE TO public USING (true);

ALTER TABLE public.speciq_package_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_products_insert ON public.speciq_package_products AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_package_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_products_select ON public.speciq_package_products AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_package_products ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_products_update ON public.speciq_package_products AS PERMISSIVE FOR UPDATE TO authenticated USING (true);

ALTER TABLE public.speciq_package_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_services_delete ON public.speciq_package_services AS PERMISSIVE FOR DELETE TO public USING (true);

ALTER TABLE public.speciq_package_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_services_insert ON public.speciq_package_services AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_package_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_services_select ON public.speciq_package_services AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_package_services ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_services_update ON public.speciq_package_services AS PERMISSIVE FOR UPDATE TO public USING (true);

ALTER TABLE public.speciq_package_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_versions_insert ON public.speciq_package_versions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_package_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_package_versions_select ON public.speciq_package_versions AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_packages ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_packages_delete ON public.speciq_packages AS PERMISSIVE FOR DELETE TO public USING ((auth.uid() = created_by));

ALTER TABLE public.speciq_packages ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_packages_insert ON public.speciq_packages AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((auth.uid() = created_by));

ALTER TABLE public.speciq_packages ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_packages_select ON public.speciq_packages AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_packages ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_packages_update ON public.speciq_packages AS PERMISSIVE FOR UPDATE TO authenticated USING ((auth.uid() = created_by));

ALTER TABLE public.speciq_pricing_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_pricing_rules_delete ON public.speciq_pricing_rules AS PERMISSIVE FOR DELETE TO public USING (true);

ALTER TABLE public.speciq_pricing_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_pricing_rules_insert ON public.speciq_pricing_rules AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_pricing_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_pricing_rules_select ON public.speciq_pricing_rules AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_pricing_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_pricing_rules_update ON public.speciq_pricing_rules AS PERMISSIVE FOR UPDATE TO public USING (true);

ALTER TABLE public.speciq_product_warranties ENABLE ROW LEVEL SECURITY;
CREATE POLICY product_warranties_delete ON public.speciq_product_warranties AS PERMISSIVE FOR DELETE TO public USING (true);

ALTER TABLE public.speciq_product_warranties ENABLE ROW LEVEL SECURITY;
CREATE POLICY product_warranties_insert ON public.speciq_product_warranties AS PERMISSIVE FOR INSERT TO public WITH CHECK (true);

ALTER TABLE public.speciq_product_warranties ENABLE ROW LEVEL SECURITY;
CREATE POLICY product_warranties_select ON public.speciq_product_warranties AS PERMISSIVE FOR SELECT TO public USING (true);

ALTER TABLE public.speciq_product_warranties ENABLE ROW LEVEL SECURITY;
CREATE POLICY product_warranties_update ON public.speciq_product_warranties AS PERMISSIVE FOR UPDATE TO public USING (true);

ALTER TABLE public.speciq_projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_projects_delete ON public.speciq_projects AS PERMISSIVE FOR DELETE TO public USING ((auth.uid() = created_by));

ALTER TABLE public.speciq_projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_projects_insert ON public.speciq_projects AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((auth.uid() = created_by));

ALTER TABLE public.speciq_projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_projects_select ON public.speciq_projects AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_projects_update ON public.speciq_projects AS PERMISSIVE FOR UPDATE TO authenticated USING ((auth.uid() = created_by));

ALTER TABLE public.speciq_retailer_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org admins can manage retailer settings" ON public.speciq_retailer_settings AS PERMISSIVE FOR ALL TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.speciq_retailer_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Org members can view retailer settings" ON public.speciq_retailer_settings AS PERMISSIVE FOR SELECT TO public USING ((organization_id IN ( SELECT organization_members.organization_id
   FROM organization_members
  WHERE (organization_members.user_id = auth.uid()))));

ALTER TABLE public.speciq_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_subscriptions_insert ON public.speciq_subscriptions AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_subscriptions_select ON public.speciq_subscriptions AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_tax_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_tax_rules_delete ON public.speciq_tax_rules AS PERMISSIVE FOR DELETE TO public USING (true);

ALTER TABLE public.speciq_tax_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_tax_rules_insert ON public.speciq_tax_rules AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_tax_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_tax_rules_select ON public.speciq_tax_rules AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_tax_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_tax_rules_update ON public.speciq_tax_rules AS PERMISSIVE FOR UPDATE TO public USING (true);

ALTER TABLE public.speciq_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_templates_insert ON public.speciq_templates AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.speciq_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_templates_select ON public.speciq_templates AS PERMISSIVE FOR SELECT TO authenticated USING (true);

ALTER TABLE public.speciq_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY speciq_templates_update ON public.speciq_templates AS PERMISSIVE FOR UPDATE TO authenticated USING (true);

ALTER TABLE public.speciq_warranty_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY warranty_catalog_delete ON public.speciq_warranty_catalog AS PERMISSIVE FOR DELETE TO public USING (true);

ALTER TABLE public.speciq_warranty_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY warranty_catalog_insert ON public.speciq_warranty_catalog AS PERMISSIVE FOR INSERT TO public WITH CHECK (true);

ALTER TABLE public.speciq_warranty_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY warranty_catalog_select ON public.speciq_warranty_catalog AS PERMISSIVE FOR SELECT TO public USING (true);

ALTER TABLE public.speciq_warranty_catalog ENABLE ROW LEVEL SECURITY;
CREATE POLICY warranty_catalog_update ON public.speciq_warranty_catalog AS PERMISSIVE FOR UPDATE TO public USING (true);

