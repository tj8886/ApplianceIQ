-- Explicit owner approval for all existing PIM images; bounded batch, retained source evidence.
BEGIN;
SET LOCAL statement_timeout='25s';
WITH selected AS MATERIALIZED(
 SELECT i.*,t.organization_id FROM tj.pim_product_images i JOIN tj.aiq_products t ON t.id=i.product_id
 WHERE NOT coalesce(i.approved,false) ORDER BY i.id LIMIT 3000 FOR UPDATE OF i SKIP LOCKED
), changed AS(
 UPDATE tj.pim_product_images i SET approved=true,approved_at=clock_timestamp()
 FROM selected s WHERE i.id=s.id RETURNING i.id,i.product_id
), logged AS(
 INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,source_updated_at,action,before_values,after_values,detail)
 SELECT s.organization_id,s.product_id,max(s.updated_at),'owner_image_approval',
 jsonb_build_object('assets',jsonb_agg(jsonb_build_object('id',s.id,'approved',s.approved,'approved_at',s.approved_at,'created_at',s.created_at,'updated_at',s.updated_at))),
 jsonb_build_object('approved',true),
 jsonb_build_object('operation','record_owner_approval_all_pim_images','evidence','Okay but I have approved all images in the pim they are approved the need to be loaded','approved_on','2026-10-11','manufacturer_verification_unchanged',true,'publication_not_claimed',true)
 FROM selected s JOIN changed c ON c.id=s.id GROUP BY s.organization_id,s.product_id RETURNING id
)
SELECT (SELECT count(*) FROM changed) as approved_assets,(SELECT count(*) FROM logged) as audit_rows;
COMMIT;
