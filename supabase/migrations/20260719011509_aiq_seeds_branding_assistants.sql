-- Appliance IQ seeds: organizations w/ brand tokens, retail pipeline, assistants,
-- templates, starter knowledge. Brand primary #0f1f3d verified from applianceiq.ai
-- meta theme-color; derived tokens marked for confirmation with brand owner.

insert into public.organizations (id, name, slug, tenant_type, status, metadata) values
('00000000-0000-0000-0000-000000000001', 'Appliance IQ', 'appliance-iq', 'appliance_iq_internal', 'active',
 jsonb_build_object(
   'brand', jsonb_build_object(
     'primary', '#0f1f3d',
     'primary_source', 'applianceiq.ai meta theme-color (verified)',
     'surface', '#ffffff',
     'surface_alt', '#f4f6fa',
     'accent_verified', '#16a34a',
     'accent_deal', '#e8590c',
     'text', '#0f1f3d',
     'text_muted', '#5b6b85',
     'derived_note', 'surface/accent/text tokens derived from primary; confirm exact values with Natalie or site CSS',
     'font_headline', 'Inter',
     'font_body', 'Inter',
     'font_note', 'font family to be confirmed from site CSS; Inter as working standard',
     'logo_mark', 'IQ badge',
     'voice', jsonb_build_object(
       'tagline', 'The price is real. We checked.',
       'principles', jsonb_build_array('verified over hyped','evidence before claims','spec-by-spec honesty','right appliance, not just cheapest')))
 )),
('00000000-0000-0000-0000-000000000002', 'Demo Retail Store', 'demo-retail', 'demo', 'active',
 '{"demo_tenant": true}'::jsonb)
on conflict (id) do nothing;

-- Retail pipeline for both seed orgs
insert into public.pipeline_stages (organization_id, name, sort_order, is_terminal, is_default, metadata)
select o.id, s.name, s.ord, s.terminal, s.ord = 1, jsonb_build_object('phase', s.phase)
from (values
  ('Lead', 1, false, 'capture'),
  ('Qualified', 2, false, 'discovery'),
  ('Quote Sent', 3, false, 'quote'),
  ('Floor Visit / Demo', 4, false, 'demo'),
  ('Negotiation', 5, false, 'close'),
  ('Closed Won', 6, true, 'close'),
  ('Delivery Scheduled', 7, false, 'fulfil'),
  ('Warranty Follow-up', 8, false, 'retain'),
  ('Closed Lost', 9, true, 'close')
) s(name, ord, terminal, phase)
cross join (select id from public.organizations where id in
  ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002')) o;

-- Platform-default assistants (organization_id null = every tenant gets them)
insert into public.ai_assistants
 (assistant_key, label, category, description, approval_required, retrieval_scopes, safety_controls, response_contract, config) values
('aiq_retail_sales', 'Retail Sales Assistant', 'sales',
 'Floor and inbound sales copilot for appliance and specialty retail. Discovery questions, spec-based recommendations, price-objection handling grounded in verified market data, quote follow-ups, and close sequencing.',
 true, array['crm','products','knowledge'],
 '{"consent": true, "privacy": true, "prohibited_action": true, "cross_organization": true}'::jsonb,
 '{"may_execute": false, "must_cite_canonical_sources": true, "no_fabricated_prices": true}'::jsonb,
 '{"methodology": {"selling_style": "evidence-first, spec-by-spec, verified-price honesty", "objection_framework": "ACRA", "core_principle": "right appliance for the customer, not just the cheapest"}}'::jsonb),
('aiq_product_expert', 'Product Expert', 'product',
 'Deep product knowledge assistant: spec comparisons between models, category guidance (refrigeration, laundry, cooking, ventilation, dishwashers), fit/installation constraints, and honest trade-off explanations.',
 false, array['products','knowledge'],
 '{"privacy": true, "prohibited_action": true, "cross_organization": true}'::jsonb,
 '{"may_execute": false, "no_fabricated_specs": true}'::jsonb,
 '{"methodology": {"style": "spec-by-spec comparison, cite the product record, state unknowns plainly"}}'::jsonb),
('aiq_warranty_upsell_coach', 'Warranty & Attach Coach', 'sales',
 'Coaches warranty, installation, haul-away, and accessory attach conversations. Value-framing scripts that stay honest: real coverage terms only, no scare tactics.',
 true, array['crm','products','knowledge'],
 '{"consent": true, "privacy": true, "prohibited_action": true}'::jsonb,
 '{"may_execute": false, "no_scare_tactics": true}'::jsonb,
 '{"methodology": {"style": "value framing from real coverage terms; disclose limits; never pressure"}}'::jsonb),
('aiq_store_manager', 'Store Performance Assistant', 'management',
 'Pipeline and performance analysis for store managers and independent sellers: stage conversion, quote-to-close rates, follow-up gaps, deal aging, and coaching priorities.',
 true, array['crm','knowledge'],
 '{"privacy": true, "prohibited_action": true, "cross_organization": true}'::jsonb,
 '{"may_execute": false, "must_cite_canonical_sources": true}'::jsonb,
 '{"methodology": {"style": "numbers from grounded context only; name the gap, suggest the drill"}}'::jsonb),
('aiq_partner_outreach', 'Partner Outreach Strategist', 'business_development',
 'B2B outreach copilot for selling Appliance IQ itself to retailers and manufacturers: observation-bracket cold email, Email-Phone-Video-Close sequencing, ACRA objection handling.',
 true, array['crm','knowledge'],
 '{"consent": true, "privacy": true, "prohibited_action": true, "cross_organization": true}'::jsonb,
 '{"may_execute": false}'::jsonb,
 '{"methodology": {"channel_sequence": ["email","phone","video","close"], "objection_framework": "ACRA", "core_principle": "specific observation brackets determine reply rates"}}'::jsonb);

-- Platform-default prompt templates
insert into public.ai_prompt_templates
 (template_key, tool_type, label, system_prompt, user_prompt_template, tone_guidance, output_schema) values
('aiq_quote_followup_v1', 'quote_followup', 'Quote Follow-up',
 'Draft a follow-up on an appliance quote. Reference the specific models quoted, restate the verified value honestly (price position, spec advantages), address the likely hesitation, and propose one clear next step. Never invent prices, discounts, or stock positions not present in the provided context. Under 130 words.',
 'Customer: {{customer_name}}. Models quoted: {{models}}. Quote total: {{quote_total}}. Days since quote: {{days_since}}. Known hesitation: {{hesitation}}. Draft the follow-up.',
 'Helpful expert, zero pressure. The Appliance IQ voice: verified, honest, evidence-first.',
 '{"format": "email", "fields": ["subject", "body", "next_step"]}'::jsonb),
('aiq_floor_demo_prep_v1', 'demo_prep', 'Floor Demo Prep',
 'Prepare a salesperson for an in-store demo visit. From the customer needs and candidate products in context: the 3 spec points that matter most for this customer, one honest trade-off to volunteer proactively, the comparison the customer will likely raise, and the natural close question.',
 'Customer needs: {{needs}}. Candidate products: {{products}}. Budget: {{budget}}. Prepare the demo plan.',
 'Direct coaching voice. Specific, spec-grounded, honest about trade-offs.',
 '{"format": "brief", "fields": ["key_specs", "proactive_tradeoff", "expected_comparison", "close_question"]}'::jsonb),
('aiq_warranty_attach_v1', 'warranty_attach', 'Warranty Attach Framing',
 'Frame the warranty/protection conversation for the product in context. Use only real coverage terms provided. Structure: what the base warranty actually covers, the realistic gap, the honest value case, and a no-pressure ask. Never use fear-based framing or invent failure statistics.',
 'Product: {{product}}. Base warranty: {{base_warranty}}. Protection plan: {{plan_terms}} at {{plan_price}}. Frame the conversation.',
 'Honest advisor, not a pusher. Disclose limits plainly.',
 '{"format": "script", "fields": ["coverage_summary", "gap", "value_case", "ask"]}'::jsonb),
('aiq_partner_outreach_v1', 'outreach_drafting', 'Partner Observation Outreach',
 'Draft B2B outreach to a Canadian appliance retailer or manufacturer about joining Appliance IQ. Open with a specific verifiable observation about their business (assortment, pricing posture, market coverage). Bridge to how verified price intelligence serves them. One low-friction ask. Under 120 words. Follow Email -> Phone -> Video -> Close; this email sets up the next channel.',
 'Target: {{company_name}}. Observation: {{observation_notes}}. Goal: {{goal}}. Sequence step: {{sequence_step}}. Draft the outreach.',
 'Peer-to-peer, commercially sharp, zero filler. The tagline energy: the price is real, we checked.',
 '{"format": "email", "fields": ["subject", "body", "followup_trigger_days", "next_channel"]}'::jsonb);

-- Starter knowledge brain (global): appliance retail sales playbook v1
insert into public.ai_knowledge_sources (source_key, title, source_type, authority_level, visibility, metadata) values
('aiq_retail_playbook_v1', 'Appliance IQ Retail Sales Playbook (Starter)', 'training_content', 'reference', 'global',
 '{"note": "Starter best-practice content; replace/extend with Appliance IQ proprietary training as it is authored."}'::jsonb);

insert into public.ai_knowledge_chunks (source_id, chunk_key, title, content, citation, visibility)
select s.id, c.key, c.title, c.content,
       jsonb_build_object('source', 'Appliance IQ Retail Sales Playbook', 'section', c.title), 'global'
from public.ai_knowledge_sources s,
(values
 ('playbook_discovery', 'Discovery Before Demo',
  'Sell the fit, not the unit. Before showing any model, establish: household size and usage patterns; space and installation constraints (measure twice - counter depth, door swing, venting, gas vs electric, panel-ready needs); what is failing about the current appliance; budget range framed as a range, not a ceiling; and timeline (emergency replacement behaves differently from planned renovation). An emergency buyer needs stock and delivery speed; a renovation buyer needs spec depth and coordination. Match the conversation to the buyer mode.'),
 ('playbook_spec_selling', 'Spec-by-Spec Honest Selling',
  'Appliance IQ voice: verified over hyped. Compare models on the specs that matter for THIS customer, and volunteer one honest trade-off proactively - it builds more trust than any claim. Never invent specs, review scores, or prices. If the customer cites a competitor price, treat it as data to verify, not a threat: verified market position beats defensive discounting. The close follows naturally from agreed fit: "Based on the depth constraint and the gas hookup, this is the one that actually fits your kitchen - want me to check delivery this week?"'),
 ('playbook_price_objection', 'Price Objections the Verified Way',
  'When price objections arrive, apply ACRA (Acknowledge, Clarify, Respond, Advance). Acknowledge the concern as rational. Clarify what the comparison actually is - different model, open-box, delivery excluded, old promo? Respond with verified information: total cost of ownership (delivery, install, haul-away, energy), warranty position, and real market range. Advance with a concrete next step. Discounting is the last lever, not the first; verified value framing wins more margin than reflex matching.'),
 ('playbook_warranty_attach', 'Warranty and Attach Done Honestly',
  'Attach revenue (protection plans, installation, haul-away, accessories, water lines, venting kits) is where retail margin lives - and where trust dies if oversold. The honest structure: state what the manufacturer warranty actually covers and for how long; identify the realistic gap (labour after year one, board failures, cosmetic exclusions); give the value case with real numbers; ask once, no pressure. Bundle install and accessories at quote time - they convert far better in the quote than at pickup.'),
 ('playbook_followup_cadence', 'Quote Follow-up Cadence',
  'Most appliance quotes die of silence, not rejection. Cadence: same-day thank-you with quote recap; day 2-3 value follow-up (one new useful fact - stock movement, verified price position, delivery slot availability - never just "checking in"); day 7 direct ask with an expiry or delivery-slot reason to decide. Every follow-up must add information the customer did not have. Log every touch in the CRM; the pipeline assistant reads gaps in the record as coaching opportunities.'),
 ('playbook_delivery_retention', 'Delivery, Warranty Follow-up, and the Second Sale',
  'The sale ends at installation, not payment. Confirm delivery access (stairs, doors, parking), old-unit removal, and installation requirements before the truck rolls. Post-delivery: 48-hour check-in call catches problems while goodwill is highest. Warranty follow-up stage exists because registered, followed-up customers return for the second appliance - laundry buyers become kitchen buyers. The CRM Warranty Follow-up stage is a revenue stage, not an admin stage.')
) as c(key, title, content)
where s.source_key = 'aiq_retail_playbook_v1';
