-- INSERT RETURNING checks must see creator metadata written by the BEFORE trigger.
ALTER FUNCTION tj_private.can_access_crm_container(text,uuid,uuid,boolean) VOLATILE;
