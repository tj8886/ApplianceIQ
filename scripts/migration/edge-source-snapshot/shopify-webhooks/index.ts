// shopify-webhooks v2 — Cross-app Shopify sync engine.
// Fans out to: CRM (contacts/deals), Spec IQ (products/prices),
// Up System (order assignments), Academy (training catalog)
// Auth: HMAC-SHA256 via X-Shopify-Hmac-Sha256

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'POST required' }, 405);

  const apiSecret = Deno.env.get('SHOPIFY_API_SECRET') ?? '';
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const admin = createClient(supabaseUrl, serviceKey);

  const rawBody = await req.text();
  const hmacHeader = req.headers.get('X-Shopify-Hmac-Sha256') ?? '';
  const shopDomain = req.headers.get('X-Shopify-Shop-Domain') ?? '';
  const topic = req.headers.get('X-Shopify-Topic') ?? '';

  if (!hmacHeader || !shopDomain || !topic) return json({ error: 'Missing Shopify headers' }, 400);

  // HMAC verification
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(apiSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  const computed = btoa(String.fromCharCode(...new Uint8Array(sig)));
  if (computed !== hmacHeader) return json({ error: 'HMAC verification failed' }, 401);

  const { data: store } = await admin.from('shopify_stores').select('id,organization_id,currency').eq('shop_domain', shopDomain).eq('status', 'active').maybeSingle();
  if (!store && topic !== 'app/uninstalled') return json({ error: 'Unknown store' }, 404);

  let payload: Record<string, unknown>;
  try { payload = JSON.parse(rawBody); } catch { return json({ error: 'Invalid JSON' }, 400); }

  const storeId = store?.id;
  const orgId = store?.organization_id;
  const results: string[] = [];

  try {
    switch (topic) {
      // ===== CUSTOMERS → CRM Contacts =====
      case 'customers/create':
      case 'customers/update': {
        const c = payload;
        const shopifyId = String(c.id);
        const email = String(c.email ?? '').toLowerCase().trim();
        const firstName = String(c.first_name ?? '').trim();
        const lastName = String(c.last_name ?? '').trim();
        const phone = String(c.phone ?? '').trim();
        if (!firstName && !email) break;

        const { data: mapped } = await admin.from('shopify_id_map').select('local_id').eq('store_id', storeId).eq('shopify_entity_type', 'customer').eq('shopify_id', shopifyId).maybeSingle();

        const contactData: Record<string, unknown> = {
          organization_id: orgId,
          first_name: firstName || email.split('@')[0],
          last_name: lastName || null,
          email: email || null,
          phone: phone || null,
          source: 'shopify',
          metadata: { shopify_id: shopifyId, shopify_tags: c.tags ?? '', shopify_orders_count: c.orders_count ?? 0, shopify_total_spent: c.total_spent ?? '0.00' },
        };
        const addr = (c.default_address ?? (c.addresses as unknown[])?.[0]) as Record<string, unknown> | undefined;
        if (addr) {
          (contactData.metadata as Record<string,unknown>).address = { address1: addr.address1, city: addr.city, province: addr.province, country: addr.country, zip: addr.zip };
        }

        if (mapped) {
          delete contactData.organization_id; delete contactData.source;
          await admin.from('contacts').update(contactData).eq('id', mapped.local_id);
        } else {
          let existingId: string | null = null;
          if (email) { const { data: byEmail } = await admin.from('contacts').select('id').eq('organization_id', orgId).eq('email', email).maybeSingle(); existingId = byEmail?.id ?? null; }
          if (existingId) {
            delete contactData.organization_id; delete contactData.source;
            await admin.from('contacts').update(contactData).eq('id', existingId);
            await admin.from('shopify_id_map').insert({ store_id: storeId, shopify_entity_type: 'customer', shopify_id: shopifyId, local_entity_type: 'contact', local_id: existingId });
          } else {
            const { data: nc } = await admin.from('contacts').insert(contactData).select('id').single();
            if (nc) await admin.from('shopify_id_map').insert({ store_id: storeId, shopify_entity_type: 'customer', shopify_id: shopifyId, local_entity_type: 'contact', local_id: nc.id });
          }
        }
        results.push('crm:contact');
        await logSync(admin, storeId!, topic, shopifyId, 'contact', null, 'success');
        break;
      }

      // ===== ORDERS → CRM Deals + Up System Queue =====
      case 'orders/create':
      case 'orders/updated': {
        const o = payload;
        const shopifyId = String(o.id);
        const orderNum = String(o.name ?? o.order_number ?? '');
        const totalPrice = Number(o.total_price ?? 0);
        const financialStatus = String(o.financial_status ?? '');
        const fulfillmentStatus = String(o.fulfillment_status ?? '');

        let contactId: string | null = null;
        const custId = o.customer ? String((o.customer as Record<string, unknown>).id ?? '') : '';
        if (custId) {
          const { data: custMap } = await admin.from('shopify_id_map').select('local_id').eq('store_id', storeId).eq('shopify_entity_type', 'customer').eq('shopify_id', custId).maybeSingle();
          contactId = custMap?.local_id ?? null;
        }

        let stage = 'Lead';
        if (financialStatus === 'paid') stage = fulfillmentStatus === 'fulfilled' ? 'Closed Won' : 'Order Placed';
        else if (financialStatus === 'pending') stage = 'Quote Sent';
        else if (financialStatus === 'refunded' || financialStatus === 'voided') stage = 'Closed Lost';

        const lineItems = (o.line_items ?? []) as Array<Record<string, unknown>>;
        const categories = [...new Set(lineItems.map(li => String(li.product_type ?? '')).filter(Boolean))];
        const productNames = lineItems.map(li => String(li.title ?? '')).filter(Boolean);

        const { data: mapped } = await admin.from('shopify_id_map').select('local_id').eq('store_id', storeId).eq('shopify_entity_type', 'order').eq('shopify_id', shopifyId).maybeSingle();

        const dealData: Record<string, unknown> = {
          organization_id: orgId, title: `Shopify ${orderNum}`, stage, value_amount: totalPrice,
          value_currency: store?.currency ?? 'CAD', contact_id: contactId, source: 'shopify',
          order_number: orderNum, product_categories: categories,
          metadata: { shopify_order_id: shopifyId, shopify_financial_status: financialStatus, products: productNames },
        };
        if (stage.includes('Won')) { dealData.closed_at = o.created_at; dealData.purchase_date = String(o.created_at ?? '').slice(0, 10); dealData.won_products = productNames; }
        if (stage.includes('Lost')) { dealData.closed_at = new Date().toISOString(); dealData.lost_reason = financialStatus; }

        let dealId: string | null = null;
        if (mapped) {
          dealId = mapped.local_id;
          delete dealData.organization_id; delete dealData.source;
          await admin.from('crm_deals').update(dealData).eq('id', mapped.local_id);
        } else {
          dealData.stage_entered_at = new Date().toISOString();
          const { data: nd } = await admin.from('crm_deals').insert(dealData).select('id').single();
          if (nd) {
            dealId = nd.id;
            await admin.from('shopify_id_map').insert({ store_id: storeId, shopify_entity_type: 'order', shopify_id: shopifyId, local_entity_type: 'deal', local_id: nd.id });
            await admin.from('activities').insert({ organization_id: orgId, entity_type: 'deal', entity_id: nd.id, activity_type: 'note', title: `Shopify order ${orderNum} — $${totalPrice}`, summary: `Products: ${productNames.join(', ')}`, source: 'crm', metadata: { shopify_order: true } });
          }
        }
        results.push('crm:deal');

        // ===== UP SYSTEM: Queue online orders for assignment =====
        if (topic === 'orders/create' && financialStatus === 'paid') {
          const custName = o.customer ? `${(o.customer as Record<string,unknown>).first_name ?? ''} ${(o.customer as Record<string,unknown>).last_name ?? ''}`.trim() : 'Online Customer';
          const custEmail = o.customer ? String((o.customer as Record<string,unknown>).email ?? '') : '';
          // Find active rotation session for the org's first store
          const { data: session } = await admin.from('iq_open_rotation_sessions').select('id,store_id').eq('organization_id', orgId).eq('is_active', true).limit(1).maybeSingle();
          if (session) {
            await admin.from('iq_customer_waiting_queue').insert({
              organization_id: orgId, store_id: session.store_id, shift_id: session.id,
              customer_display_name: custName, customer_email: custEmail,
              customer_category: 'online_order', requested_source: 'shopify_online',
              lead_source: 'shopify', shopify_order_id: shopifyId,
              crm_contact_id: contactId, crm_deal_id: dealId,
              customer_needs: productNames.join(', '),
              priority: 2, is_anonymous: false,
            });
            results.push('up:queued');
          }
        }
        await logSync(admin, storeId!, topic, shopifyId, 'deal', dealId, 'success');
        break;
      }

      // ===== PRODUCTS → PIM + Spec IQ Pricing + Academy Catalog =====
      case 'products/create':
      case 'products/update': {
        const p = payload;
        const shopifyId = String(p.id);
        const title = String(p.title ?? '');
        const vendor = String(p.vendor ?? '');
        const productType = String(p.product_type ?? '');
        const variants = (p.variants ?? []) as Array<Record<string, unknown>>;
        const firstVariant = variants[0] ?? {};
        const price = Number(firstVariant.price ?? 0);
        const sku = String(firstVariant.sku ?? '');
        const inventoryQty = Number(firstVariant.inventory_quantity ?? 0);
        const variantId = String(firstVariant.id ?? '');
        const images = (p.images ?? []) as Array<Record<string, unknown>>;
        const imageUrl = images.length ? String(images[0].src ?? '') : '';
        const productUrl = `https://${shopDomain}/products/${p.handle ?? ''}`;

        // 1. PIM: retailer_discovered_products
        await admin.from('retailer_discovered_products').upsert({
          retailer_source_id: storeId, product_url: productUrl,
          brand_name: vendor, model_number: sku || title, product_name: title,
          category: productType, discovered_at: new Date().toISOString(),
          metadata: { shopify_id: shopifyId, price, variants: variants.length, image: imageUrl },
        }, { onConflict: 'product_url' });
        results.push('pim:discovered');

        // 2. Spec IQ: update retailer_products with live Shopify pricing
        if (sku) {
          // Try to find matching aiq_product by model
          const { data: aiqMatch } = await admin.from('aiq_products').select('id').or(`model.eq.${sku},model.ilike.%${sku}%`).limit(1).maybeSingle();
          if (aiqMatch) {
            await admin.from('retailer_products').upsert({
              organization_id: orgId, aiq_product_id: aiqMatch.id,
              shopify_product_id: shopifyId, shopify_variant_id: variantId,
              shopify_price: price, shopify_inventory_quantity: inventoryQty,
              shopify_synced_at: new Date().toISOString(), in_stock: inventoryQty > 0,
            }, { onConflict: 'organization_id,aiq_product_id' });
            results.push('speciq:price_synced');
          }
        }

        // 3. Academy: training catalog — so reps train on what they sell
        await admin.from('iq_retailer_training_catalog').upsert({
          organization_id: orgId, brand_name: vendor, model: sku || title,
          category: productType, price, in_stock: inventoryQty > 0,
          shopify_product_id: shopifyId, source: 'shopify',
          updated_at: new Date().toISOString(),
        }, { onConflict: 'organization_id,brand_name,model' });
        results.push('academy:catalog');

        await logSync(admin, storeId!, topic, shopifyId, 'product', null, 'success');
        break;
      }

      // ===== APP UNINSTALLED =====
      case 'app/uninstalled': {
        await admin.from('shopify_stores').update({ status: 'uninstalled', uninstalled_at: new Date().toISOString(), access_token: 'REVOKED' }).eq('shop_domain', shopDomain);
        results.push('uninstalled');
        break;
      }

      default:
        return json({ ok: true, skipped: true, topic });
    }
  } catch (err) {
    if (storeId) await logSync(admin, storeId, topic, '', '', null, 'error', String(err));
    return json({ error: 'Processing failed', detail: String(err) }, 500);
  }

  // Update last sync timestamp
  if (storeId) await admin.from('shopify_stores').update({ last_sync_at: new Date().toISOString() }).eq('id', storeId);

  return json({ ok: true, topic, shop: shopDomain, results });
});

async function logSync(admin: ReturnType<typeof createClient>, storeId: string, eventType: string, shopifyId: string, entityType: string, entityId: string | null, status: string, error?: string) {
  await admin.from('shopify_sync_log').insert({ store_id: storeId, event_type: eventType, shopify_id: shopifyId, entity_type: entityType, entity_id: entityId, status, error_message: error ?? null });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}
