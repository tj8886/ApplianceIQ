BEGIN;SET LOCAL statement_timeout='60s';
DO $$ DECLARE u uuid;src uuid;org uuid:=gen_random_uuid();other uuid:=gen_random_uuid();p uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();d uuid:=gen_random_uuid();hidden_d uuid:=gen_random_uuid();BEGIN
 SELECT target_user_id,source_user_id INTO u,src FROM tj.source_user_identity_map im WHERE activation_status='activated' AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 INSERT INTO tj.organizations(id,name,slug) VALUES(org,'Rollback graph',org::text),(other,'Rollback foreign graph',other::text);
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,src,'admin','active');
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.foreign',other::text,true);PERFORM set_config('test.source',src::text,true);PERFORM set_config('test.product',p::text,true);PERFORM set_config('test.product2',p2::text,true);PERFORM set_config('test.document',d::text,true);PERFORM set_config('test.hidden_document',hidden_d::text,true);
 INSERT INTO tj.aiq_products(id,organization_id,manufacturer_name,brand_name,model,status,public_visible,replacement_model) VALUES(p,org,'Rollback','Rollback','ROLLBACK-P1','draft',true,'ROLLBACK-P2'),(p2,org,'Rollback','Rollback','ROLLBACK-P2','draft',true,NULL);
 INSERT INTO tj.pim_product_documents(id,product_id,doc_type,title,file_url,approved,is_current,audience_tiers) VALUES(d,p,'spec_sheet','Rollback approved','https://example.invalid/allowed',true,true,ARRAY['all']),(hidden_d,p,'spec_sheet','Rollback unapproved','https://example.invalid/private',false,true,ARRAY['all']);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid;r jsonb;counts jsonb;first_nodes integer;first_edges integer;BEGIN
 counts:=public.tj_sync_product_graph(org);first_nodes:=(counts->>'nodes')::integer;first_edges:=(counts->>'edges')::integer;
 counts:=public.tj_sync_product_graph(org);
 IF (counts->>'nodes')::integer<>first_nodes OR (counts->>'edges')::integer<>first_edges THEN RAISE EXCEPTION 'Repeated sync duplicates';END IF;
 r:=public.tj_product_graph_lookup(org,ARRAY[current_setting('test.product')::uuid]);
 IF r->>'node_count'<>'1' OR r->>'relationship_count'<>'2' THEN RAISE EXCEPTION 'Product/approved doc/replacement result: %',r;END IF;
 IF r::text LIKE '%example.invalid%' OR r::text LIKE '%Rollback unapproved%' THEN RAISE EXCEPTION 'Private metadata/document exposed';END IF;
 r:=public.tj_product_graph_lookup(org,'{}',ARRAY['ROLLBACK-P2']);IF r->>'node_count'<>'1' THEN RAISE EXCEPTION 'Model lookup';END IF;
 r:=public.tj_product_graph_lookup(org,'{}','{}','unapproved');IF r->>'node_count'<>'0' THEN RAISE EXCEPTION 'Unapproved lookup';END IF;
 BEGIN PERFORM public.tj_sync_product_graph(NULL);RAISE EXCEPTION 'Global sync allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_product_graph_lookup(current_setting('test.foreign')::uuid);RAISE EXCEPTION 'Foreign graph allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid;n uuid:=gen_random_uuid();pnode uuid;foreign_n uuid:=gen_random_uuid();BEGIN
 SELECT id INTO pnode FROM tj.aicrm_graph_nodes WHERE entity_type='aiq_products' AND entity_id=current_setting('test.product')::uuid;
 INSERT INTO tj.aicrm_graph_nodes(id,organization_id,node_type,label,entity_type,metadata) VALUES(n,org,'Person','PRIVATE CRM PERSON','contacts','{"dealer_cost":999}'),(foreign_n,current_setting('test.foreign')::uuid,'Product','FOREIGN PRODUCT','aiq_products','{}');
 INSERT INTO tj.aicrm_graph_edges(organization_id,from_node_id,to_node_id,relationship_type) VALUES(org,pnode,n,'CONNECTED_TO'),(org,pnode,foreign_n,'CONNECTED_TO');
 UPDATE tj.pim_product_documents SET embargoed=true WHERE id=current_setting('test.document')::uuid;
 UPDATE tj.organization_members SET role='member' WHERE organization_id=org AND user_id=current_setting('test.source')::uuid;
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;org uuid:=current_setting('test.org')::uuid;BEGIN
 BEGIN PERFORM public.tj_sync_product_graph(org);RAISE EXCEPTION 'Member sync allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET role='admin' WHERE organization_id=current_setting('test.org')::uuid AND user_id=current_setting('test.source')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb;org uuid:=current_setting('test.org')::uuid;BEGIN
 r:=public.tj_product_graph_lookup(org,ARRAY[current_setting('test.product')::uuid]);
 IF r::text LIKE '%PRIVATE CRM%' OR r::text LIKE '%FOREIGN PRODUCT%' OR r::text LIKE '%dealer_cost%' OR r::text LIKE '%Rollback approved%' THEN RAISE EXCEPTION 'Restricted graph records exposed';END IF;
 IF r->>'relationship_count'<>'1' THEN RAISE EXCEPTION 'Embargo/CRM/cross-org edge not filtered';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_product_graph_lookup(org);RAISE EXCEPTION 'Unmapped graph lookup';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF has_table_privilege('authenticated','tj.aicrm_graph_nodes','SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','tj.aicrm_graph_edges','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Raw graph privileges exposed';END IF;
END $$;
ROLLBACK;
