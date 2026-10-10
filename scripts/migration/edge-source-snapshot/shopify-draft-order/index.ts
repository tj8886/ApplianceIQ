// shopify-draft-order — Push a Spec IQ package to Shopify as a draft order.
// Auth: user JWT (called from Spec IQ frontend)
// Flow: Read package + products → create Shopify draft order → save draft URL back

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST required' }, 405);
  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return json({ error: 'auth_required' }, 401);

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(url, serviceKey);

  const { data: userData } = await userClient.auth.getUser();
  if (!userData?.user?.id) return json({ error: 'auth_required' }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: 'invalid_json' }, 400); }

  const packageId = String(body.package_id ?? '');
  const orgId = String(body.organization_id ?? '');
  if (!packageId || !orgId) return json({ error: 'package_id and organization_id required' }, 400);

  // Load the package and its products
  const { data: pkg } = await admin.from('speciq_packages').select('*').eq('id', packageId).eq('organization_id', orgId).single();
  if (!pkg) return json({ error: 'Package not found' }, 404);

  const { data: products } = await admin.from('speciq_package_products').select('*').eq('package_id', packageId).order('sort_order');
  if (!products?.length) return json({ error: 'Package has no products' }, 400);

  // Find the Shopify store for this org
  const { data: store } = await admin.from('shopify_stores').select('id,shop_domain,access_token').eq('organization_id', orgId).eq('status', 'active').maybeSingle();
  if (!store || store.access_token === 'REVOKED') return json({ error: 'No active Shopify connection for this organization' }, 404);

  // Find the customer in Shopify (if we have a contact linked)
  let shopifyCustomerId: number | null = null;
  if (pkg.contact_id) {
    const { data: idMap } = await admin.from('shopify_id_map').select('shopify_id').eq('store_id', store.id).eq('shopify_entity_type', 'customer').eq('local_id', pkg.contact_id).maybeSingle();
    if (idMap) shopifyCustomerId = Number(idMap.shopify_id);
  }

  // Build draft order line items
  const lineItems = products.map(p => {
    const item: Record<string, unknown> = {
      title: `${p.brand ?? ''} ${p.model_number ?? ''} ${p.product_name ?? ''}`.trim(),
      quantity: p.quantity ?? 1,
      price: String(p.negotiated_price ?? p.promo_price ?? p.msrp ?? 0),
    };

    // If we have a Shopify variant ID, use it for proper inventory tracking
    if (p.aiq_product_id) {
      // Try to find the Shopify variant via retailer_products
      // This is async so we'll do it below
    }

    return item;
  });

  // Enrich with Shopify variant IDs where possible
  for (let i = 0; i < products.length; i++) {
    if (products[i].aiq_product_id) {
      const { data: rp } = await admin.from('retailer_products').select('shopify_variant_id').eq('organization_id', orgId).eq('aiq_product_id', products[i].aiq_product_id).maybeSingle();
      if (rp?.shopify_variant_id) {
        lineItems[i] = { variant_id: Number(rp.shopify_variant_id), quantity: products[i].quantity ?? 1 };
      }
    }
  }

  // Build the draft order payload
  const draftOrder: Record<string, unknown> = {
    line_items: lineItems,
    note: `ApplianceIQ Spec IQ Package: ${pkg.package_name ?? 'Package'}\nQuote #${pkg.quote_number ?? 'N/A'}\nSalesperson: ${pkg.salesperson_name ?? 'N/A'}`,
    tags: 'applianceiq,speciq',
    use_customer_default_address: true,
  };

  if (shopifyCustomerId) draftOrder.customer = { id: shopifyCustomerId };

  // Services as additional line items
  const { data: services } = await admin.from('speciq_package_services').select('*').eq('package_id', packageId);
  if (services?.length) {
    for (const svc of services) {
      (draftOrder.line_items as unknown[]).push({
        title: svc.service_name ?? 'Service',
        quantity: svc.quantity ?? 1,
        price: String(svc.price ?? 0),
        requires_shipping: false,
      });
    }
  }

  // Taxes and discounts
  if (pkg.volume_discount && Number(pkg.volume_discount) > 0) {
    draftOrder.applied_discount = {
      value_type: 'fixed_amount',
      value: String(pkg.volume_discount),
      title: 'Package Volume Discount',
    };
  }

  // Push to Shopify
  const resp = await fetch(`https://${store.shop_domain}/admin/api/2024-01/draft_orders.json`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': store.access_token },
    body: JSON.stringify({ draft_order: draftOrder }),
  });
  const result = await resp.json();

  if (!resp.ok) {
    return json({ error: 'Shopify draft order creation failed', detail: result.errors ?? result }, 502);
  }

  const draft = result.draft_order;
  const draftId = String(draft.id);
  const draftUrl = `https://${store.shop_domain}/admin/draft_orders/${draftId}`;
  const invoiceUrl = draft.invoice_url ?? '';

  // Save back to Spec IQ package
  await admin.from('speciq_packages').update({
    shopify_draft_order_id: draftId,
    shopify_draft_order_url: draftUrl,
    shopify_pushed_at: new Date().toISOString(),
  }).eq('id', packageId);

  // Log sync
  await admin.from('shopify_sync_log').insert({
    store_id: store.id, event_type: 'draft_order_created', shopify_id: draftId,
    entity_type: 'package', entity_id: packageId, status: 'success',
  });

  return json({
    ok: true,
    draft_order_id: draftId,
    admin_url: draftUrl,
    invoice_url: invoiceUrl,
    line_items_count: (draftOrder.line_items as unknown[]).length,
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' } });
}
