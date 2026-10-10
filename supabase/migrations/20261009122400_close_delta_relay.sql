-- Transfer verified: revoke the service-only temporary RPC. Retain journal as provenance.
REVOKE ALL ON FUNCTION public.aiq_apply_delta_batch(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION tj_private.apply_delta_batch(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
