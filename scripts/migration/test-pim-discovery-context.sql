BEGIN; SET LOCAL statement_timeout='30s';
DO $$ DECLARE u uuid;src uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id INTO u,src FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 INSERT INTO tj.product_iq_platform_roles(user_id,role,status) VALUES(src,'data_reviewer','active') ON CONFLICT DO NOTHING;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE c jsonb;BEGIN
 c:=public.tj_pim_scraper_context();IF NOT (c->>'allowed')::boolean THEN RAISE EXCEPTION 'Approved governance context denied';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);c:=public.tj_pim_scraper_context();IF (c->>'allowed')::boolean THEN RAISE EXCEPTION 'Unmapped governance access';END IF;
END $$;
SELECT id,brand_name,ca_website,us_website,sitemap_url,product_scope,scrape_tier,server_fetchable,bot_protection FROM tj.scraper_brand_sources WHERE false;
SELECT model,source_reference FROM tj.aiq_products_app WHERE false;
RESET ROLE;
DO $$BEGIN IF has_function_privilege('anon','public.tj_pim_scraper_context()','EXECUTE') THEN RAISE EXCEPTION 'Anonymous governance context granted';END IF;END $$;
ROLLBACK;
