-- Source lifecycle reference catalog was public. Destination requires an active mapped organization and grants only router reference columns.
ALTER TABLE tj.product_lifecycle ENABLE ROW LEVEL SECURITY;
CREATE POLICY consolidation_lifecycle_reference_read ON tj.product_lifecycle FOR SELECT TO authenticated USING((SELECT tj_private.has_active_mapped_org()));
GRANT SELECT(brand_name,model_number,product_name,category,lifecycle_status,announced_date,launch_date,discontinued_date,end_of_life_date,predecessor_model,successor_model,changes_from_predecessor,notes) ON tj.product_lifecycle TO authenticated;
NOTIFY pgrst,'reload schema';
