-- The retained source index already covers this organization foreign key.
-- Remove only the duplicate index introduced by the IQ Build US access migration.
DROP INDEX tj.iqbuild_projects_org_us_idx;
