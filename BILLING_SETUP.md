# Billing Setup — Stripe Integration

## Pricing tiers (placeholders — adjust as needed)

| Tier | Price | AI Tokens | Recordings | Trial |
|---|---|---|---|---|
| Starter | $29/mo | 100K | 10/mo | 14 days |
| Pro | $99/mo | 1M | 100/mo | 14 days |
| Enterprise | $299/mo | 10M | Unlimited | 14 days |
| Demo | Free | 10K | 2/mo | Permanent |

## One-time Stripe setup

1. **Create a Stripe account** → stripe.com
2. **Create products + prices**:
   - Go to **Billing → Products**
   - Create product "ApplianceIQ Starter" → Price $29/month
   - Create product "ApplianceIQ Pro" → Price $99/month
   - Create product "ApplianceIQ Enterprise" → Price $299/month
3. **Create webhook endpoint**:
   - Go to **Developers → Webhooks → Add endpoint**
   - Endpoint URL: `https://fumwwhyozeouoqscolke.supabase.co/functions/v1/stripe-webhooks`
   - Events: `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`, `invoice.payment_failed`
   - Copy the **Signing secret** (starts with `whsec_`)
4. **Set edge secrets in Supabase**:
   - Go to your ApplianceIQ project → **Edge Functions → Secrets**
   - Add `STRIPE_WEBHOOK_SECRET` = the signing secret from step 3
   - Add `STRIPE_SECRET_KEY` = your Stripe Secret Key (from Developers → API keys)
5. **Enable email receipts** (optional):
   - Stripe → **Settings → Email Receipts** → toggle on

## How it works

1. **User signs up** at crmaiiq.netlify.app/pricing → creates org + user + initializes token limits for their tier
2. **User is on 14-day trial** → Billing tab shows "Trial ends X date"
3. **On day 14**, reps get an email from Stripe asking to add payment method (or upgrade tier)
4. **Payment succeeds** → webhook fires → org marked `subscription_status: active` and tier confirmed
5. **Payment fails** → webhook fires → org marked `subscription_status: past_due` and coaching starts refusing requests
6. **Token limits enforced** → every AI call checks `check_token_budget()`; if over limit, call is rejected with clear message

## Testing the flow

1. In Stripe dashboard **Developers → API Keys**, use the **Publishable Key** in your frontend code (it's already hardcoded to development if needed)
2. Use Stripe test card `4242 4242 4242 4242` with any future expiry and CVC to test payments
3. Stripe automatically sends test emails to your dashboard email — check those
4. Use Stripe's **Event log** to verify webhooks are firing

## Adjusting pricing later

To change a tier's token limit:
1. Go to `ai_token_limits` in Supabase and edit the `monthly_limit` for that tier
2. New organizations created after that get the new limit
3. Existing organizations keep their old limit until they re-subscribe or a webhook updates them

To change a tier's price:
1. In Stripe → **Billing → Products**, edit the price
2. Existing subscriptions stay at old price; new subscriptions get new price

## Production checklist

- [ ] Stripe account created and verified
- [ ] Products + prices set up in Stripe
- [ ] Webhook endpoint added and signing secret saved
- [ ] `STRIPE_WEBHOOK_SECRET` added to Supabase Edge Function secrets
- [ ] `STRIPE_SECRET_KEY` added to Supabase Edge Function secrets (if using direct API calls)
- [ ] Pricing page tested (crmaiiq.netlify.app → no login needed)
- [ ] Signup flow tested (create org, verify token limits initialized)
- [ ] Billing dashboard tested (view usage, see trial expiration)
- [ ] Payment method collection tested (can test with Stripe test card)
- [ ] Token limits enforced (try recording with a test org over its limit)

