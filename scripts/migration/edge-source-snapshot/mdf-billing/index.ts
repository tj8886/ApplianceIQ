import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14.14.0'

const STRIPE_KEY = Deno.env.get('STRIPE_SECRET_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const APP_URL = 'https://applianceiq-mdf-coop-vr.netlify.app'

const stripe = new Stripe(STRIPE_KEY, { apiVersion: '2023-10-16' })

serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { action, data } = await req.json()
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // ── CREATE CHECKOUT SESSION ─────────────────
    if (action === 'create_checkout') {
      const { tier_id, billing_cycle, email, org_id } = data

      // Get tier
      const { data: tier } = await supabase.from('mdf_subscription_tiers')
        .select('*').eq('id', tier_id).single()
      if (!tier) return new Response(JSON.stringify({ error: 'Invalid tier' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })

      // Get or create Stripe customer
      const { data: org } = await supabase.from('mdf_organizations')
        .select('*').eq('id', org_id).single()

      let customerId = org?.stripe_customer_id
      if (!customerId) {
        const customer = await stripe.customers.create({ email, metadata: { org_id } })
        customerId = customer.id
        await supabase.from('mdf_organizations').update({ stripe_customer_id: customerId }).eq('id', org_id)
      }

      // Create or find Stripe Price
      const amount = billing_cycle === 'annual' ? tier.price_annual : tier.price_monthly
      const interval = billing_cycle === 'annual' ? 'year' : 'month'
      const priceField = billing_cycle === 'annual' ? 'stripe_price_annual' : 'stripe_price_monthly'
      
      let priceId = tier[priceField]
      if (!priceId) {
        // Create product + price in Stripe
        const product = await stripe.products.create({
          name: `ApplianceIQ ${tier.name}`,
          description: `MDF/Co-op/VR - ${tier.name} Plan (${billing_cycle})`,
          metadata: { tier_id: tier.id }
        })
        const price = await stripe.prices.create({
          product: product.id,
          unit_amount: amount,
          currency: 'cad',
          recurring: { interval },
        })
        priceId = price.id
        await supabase.from('mdf_subscription_tiers').update({ [priceField]: priceId }).eq('id', tier_id)
      }

      // Create checkout session
      const session = await stripe.checkout.sessions.create({
        customer: customerId,
        mode: 'subscription',
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `${APP_URL}?billing=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${APP_URL}?billing=canceled`,
        subscription_data: {
          trial_period_days: org?.subscription_status === 'trialing' ? undefined : 14,
          metadata: { org_id, tier_id },
        },
        metadata: { org_id, tier_id, billing_cycle },
        allow_promotion_codes: true,
        billing_address_collection: 'required',
        tax_id_collection: { enabled: true },
      })

      return new Response(JSON.stringify({ ok: true, url: session.url, session_id: session.id }), 
        { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    // ── CREATE BILLING PORTAL ────────────────────
    if (action === 'billing_portal') {
      const { org_id } = data
      const { data: org } = await supabase.from('mdf_organizations')
        .select('stripe_customer_id').eq('id', org_id).single()
      
      if (!org?.stripe_customer_id) {
        return new Response(JSON.stringify({ error: 'No billing account' }), 
          { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
      }

      const session = await stripe.billingPortal.sessions.create({
        customer: org.stripe_customer_id,
        return_url: APP_URL,
      })

      return new Response(JSON.stringify({ ok: true, url: session.url }), 
        { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    // ── HANDLE WEBHOOK ──────────────────────────
    if (action === 'webhook') {
      const { type, data: eventData } = data

      if (type === 'checkout.session.completed') {
        const { org_id, tier_id, billing_cycle } = eventData.metadata || {}
        if (org_id) {
          await supabase.from('mdf_organizations').update({
            tier_id,
            billing_cycle,
            stripe_subscription_id: eventData.subscription,
            subscription_status: 'active',
            trial_ends_at: null,
            updated_at: new Date().toISOString(),
          }).eq('id', org_id)
        }
      }

      if (type === 'customer.subscription.updated') {
        const sub = eventData.object || eventData
        const orgId = sub.metadata?.org_id
        if (orgId) {
          await supabase.from('mdf_organizations').update({
            subscription_status: sub.status,
            current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
            updated_at: new Date().toISOString(),
          }).eq('id', orgId)
        }
      }

      if (type === 'customer.subscription.deleted') {
        const sub = eventData.object || eventData
        const orgId = sub.metadata?.org_id
        if (orgId) {
          await supabase.from('mdf_organizations').update({
            subscription_status: 'canceled',
            updated_at: new Date().toISOString(),
          }).eq('id', orgId)
        }
      }

      if (type === 'invoice.payment_failed') {
        const inv = eventData.object || eventData
        const subId = inv.subscription
        if (subId) {
          await supabase.from('mdf_organizations').update({
            subscription_status: 'past_due',
            updated_at: new Date().toISOString(),
          }).eq('stripe_subscription_id', subId)
        }
      }

      return new Response(JSON.stringify({ ok: true }), 
        { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    // ── GET SUBSCRIPTION STATUS ──────────────────
    if (action === 'get_status') {
      const { org_id } = data
      const { data: org } = await supabase.from('mdf_organizations')
        .select('*, mdf_subscription_tiers(*)')
        .eq('id', org_id).single()
      
      const brandCount = (await supabase.from('mdf_brands').select('id', { count: 'exact', head: true }).eq('is_active', true)).count || 0
      const userCount = (await supabase.from('mdf_platform_users').select('id', { count: 'exact', head: true }).eq('org_id', org_id).eq('is_active', true)).count || 0

      return new Response(JSON.stringify({ 
        ok: true, 
        org,
        usage: { brands: brandCount, users: userCount },
        limits: { 
          max_brands: org?.mdf_subscription_tiers?.max_brands, 
          max_users: org?.mdf_subscription_tiers?.max_users 
        },
        is_trial: org?.subscription_status === 'trialing',
        trial_days_left: org?.trial_ends_at ? Math.max(0, Math.ceil((new Date(org.trial_ends_at) - new Date()) / 86400000)) : null,
      }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({ error: 'Unknown action' }), 
      { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), 
      { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
