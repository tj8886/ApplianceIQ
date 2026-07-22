-- ============================================================
-- SPEC IQ — Core Tables (shared Supabase, separate application)
-- Applied via MCP on 2026-07-22, recorded here for repo parity.
-- ============================================================

-- Spec IQ subscriptions per organization
CREATE TABLE IF NOT EXISTS speciq_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  plan text NOT NULL DEFAULT 'starter' CHECK (plan IN ('starter','professional','retail_location','multi_location','builder_designer')),
  status text NOT NULL DEFAULT 'trialing' CHECK (status IN ('trialing','active','past_due','canceled','suspended')),
  max_users integer NOT NULL DEFAULT 1,
  stripe_subscription_id text,
  trial_ends_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_subscriptions ENABLE ROW LEVEL SECURITY;

-- Spec IQ projects
CREATE TABLE IF NOT EXISTS speciq_projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
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
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','archived')),
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_projects ENABLE ROW LEVEL SECURITY;

-- Spec IQ packages
CREATE TABLE IF NOT EXISTS speciq_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  project_id uuid NOT NULL REFERENCES speciq_projects(id) ON DELETE CASCADE,
  package_name text NOT NULL,
  version integer NOT NULL DEFAULT 1,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','generated','sent','viewed','revised','expired','superseded')),
  cover_image_url text,
  welcome_message text,
  retailer_disclaimer text,
  include_pricing boolean NOT NULL DEFAULT false,
  share_token text UNIQUE,
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
  created_by uuid REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_packages ENABLE ROW LEVEL SECURITY;

-- Products within a package
CREATE TABLE IF NOT EXISTS speciq_package_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES speciq_packages(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES organizations(id),
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
  clearances jsonb DEFAULT '{}',
  cutout_dimensions jsonb DEFAULT '{}',
  door_swing text,
  installation_type text,
  key_benefits text,
  warranty_summary text,
  included_accessories text,
  required_accessories text,
  retailer_notes text,
  specifications jsonb DEFAULT '{}',
  msrp numeric,
  promo_price numeric,
  negotiated_price numeric,
  discount_reason text,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_package_products ENABLE ROW LEVEL SECURITY;

-- Package services
CREATE TABLE IF NOT EXISTS speciq_package_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES speciq_packages(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  service_type text NOT NULL CHECK (service_type IN ('delivery','installation','haul_away','extended_warranty','accessories','environmental_fee','other')),
  description text,
  amount numeric NOT NULL DEFAULT 0,
  taxable boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_package_services ENABLE ROW LEVEL SECURITY;

-- Package engagement tracking
CREATE TABLE IF NOT EXISTS speciq_package_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES speciq_packages(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN ('created','sent','email_delivered','link_opened','page_viewed','product_clicked','downloaded','pricing_viewed','revision_requested','customer_response')),
  event_data jsonb DEFAULT '{}',
  ip_address text,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_package_events ENABLE ROW LEVEL SECURITY;

-- Package versions (immutable snapshots)
CREATE TABLE IF NOT EXISTS speciq_package_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES speciq_packages(id) ON DELETE CASCADE,
  version_number integer NOT NULL,
  snapshot jsonb NOT NULL,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_package_versions ENABLE ROW LEVEL SECURITY;

-- Package templates
CREATE TABLE IF NOT EXISTS speciq_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  template_name text NOT NULL,
  cover_config jsonb DEFAULT '{}',
  welcome_message text,
  disclaimer text,
  include_pricing boolean NOT NULL DEFAULT false,
  is_default boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_templates ENABLE ROW LEVEL SECURITY;

-- Tax rules
CREATE TABLE IF NOT EXISTS speciq_tax_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  jurisdiction_name text NOT NULL,
  province_state text,
  country text NOT NULL DEFAULT 'CA',
  gst_rate numeric DEFAULT 0,
  hst_rate numeric DEFAULT 0,
  pst_rate numeric DEFAULT 0,
  qst_rate numeric DEFAULT 0,
  env_fee_rate numeric DEFAULT 0,
  delivery_taxable boolean NOT NULL DEFAULT true,
  installation_taxable boolean NOT NULL DEFAULT true,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_tax_rules ENABLE ROW LEVEL SECURITY;

-- Pricing rules
CREATE TABLE IF NOT EXISTS speciq_pricing_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  rule_type text NOT NULL CHECK (rule_type IN ('min_margin','approval_threshold','map_alert','max_discount_pct')),
  rule_value numeric NOT NULL,
  requires_approval boolean NOT NULL DEFAULT false,
  approval_role text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_pricing_rules ENABLE ROW LEVEL SECURITY;

-- CRM follow-up sequences
CREATE TABLE IF NOT EXISTS speciq_followup_sequences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  step_order integer NOT NULL,
  delay_days integer NOT NULL DEFAULT 0,
  action_type text NOT NULL CHECK (action_type IN ('send_package','confirm_receipt','ask_questions','review_pricing','followup_promo','custom')),
  action_label text NOT NULL,
  email_template text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_followup_sequences ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_speciq_projects_org ON speciq_projects(organization_id);
CREATE INDEX IF NOT EXISTS idx_speciq_packages_project ON speciq_packages(project_id);
CREATE INDEX IF NOT EXISTS idx_speciq_packages_org ON speciq_packages(organization_id);
CREATE INDEX IF NOT EXISTS idx_speciq_packages_share ON speciq_packages(share_token);
CREATE INDEX IF NOT EXISTS idx_speciq_package_products_pkg ON speciq_package_products(package_id);
CREATE INDEX IF NOT EXISTS idx_speciq_package_events_pkg ON speciq_package_events(package_id);
CREATE INDEX IF NOT EXISTS idx_speciq_tax_rules_org ON speciq_tax_rules(organization_id);
