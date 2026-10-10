-- Read-only verification: application cleanup relies on these existing FK rules.
DO $$BEGIN
 IF to_regclass('tj.speciq_package_warranties') IS NOT NULL THEN RAISE EXCEPTION 'obsolete table exists; re-review cleanup';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
  WHERE c.conrelid='tj.speciq_product_warranties'::regclass AND c.confrelid='tj.speciq_packages'::regclass AND c.contype='f' AND c.confdeltype='c' AND a.attname='package_id') THEN RAISE EXCEPTION 'package warranty cascade missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
  WHERE c.conrelid='tj.speciq_product_warranties'::regclass AND c.confrelid='tj.speciq_package_products'::regclass AND c.contype='f' AND c.confdeltype='c' AND a.attname='package_product_id') THEN RAISE EXCEPTION 'product warranty cascade missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='tj.speciq_package_products'::regclass AND confrelid='tj.speciq_packages'::regclass AND contype='f' AND confdeltype='c') THEN RAISE EXCEPTION 'package product cascade missing';END IF;
 IF has_table_privilege('authenticated','tj.speciq_packages','DELETE') OR has_table_privilege('authenticated','tj.speciq_product_warranties','DELETE') THEN RAISE EXCEPTION 'write authorization changed; re-review application contract';END IF;
END $$;
SELECT 'PASS: read-only catalog proves real package/product warranty cascades and closed direct delete grants; obsolete table absent; no rows changed' result;
