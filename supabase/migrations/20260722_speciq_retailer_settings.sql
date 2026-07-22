-- ============================================================
-- SPEC IQ — Retailer Settings + User Management
-- ============================================================

-- Retailer branding and store info per organization
CREATE TABLE IF NOT EXISTS speciq_retailer_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) UNIQUE,
  store_name text,
  store_phone text,
  store_email text,
  store_address text,
  store_city text,
  store_province text,
  store_postal text,
  store_website text,
  logo_url text,
  primary_color text DEFAULT '#0f1f3d',
  secondary_color text DEFAULT '#2f6fed',
  default_disclaimer text,
  default_welcome_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE speciq_retailer_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Org members can view retailer settings" ON speciq_retailer_settings
  FOR SELECT USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

CREATE POLICY "Org admins can update retailer settings" ON speciq_retailer_settings
  FOR ALL USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

-- Indexes
CREATE INDEX IF NOT EXISTS idx_speciq_retailer_settings_org ON speciq_retailer_settings(organization_id);

-- Storage bucket for retailer logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('retailer-logos', 'retailer-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload logos
CREATE POLICY "Authenticated users can upload logos" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'retailer-logos');

CREATE POLICY "Anyone can view logos" ON storage.objects
  FOR SELECT
  USING (bucket_id = 'retailer-logos');

CREATE POLICY "Authenticated users can update their logos" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'retailer-logos');

CREATE POLICY "Authenticated users can delete their logos" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'retailer-logos');
