CREATE POLICY consolidation_owned_member_unlink ON tj.crm_buying_group_members FOR DELETE TO authenticated USING(tj_private.can_write_crm_relation('crm_buying_group_members',buying_group_id,contact_id));
GRANT DELETE ON tj.crm_buying_group_members TO authenticated;
