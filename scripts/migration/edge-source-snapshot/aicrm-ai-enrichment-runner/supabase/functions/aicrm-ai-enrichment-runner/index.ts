import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { callAnthropicMessages } from '../../../packages/elev8-ai-service/index.ts';
import { composeAiPrompt, selectAiPromptTemplate } from '../_shared/ai-prompts.js';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');
const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY');
const ANTHROPIC_MODEL = Deno.env.get('ANTHROPIC_MODEL') || 'claude-3-5-sonnet-latest';
const ANTHROPIC_MAX_TOKENS = Number(Deno.env.get('ANTHROPIC_MAX_TOKENS') || '2400');
const ANTHROPIC_TIMEOUT_MS = Number(Deno.env.get('ANTHROPIC_TIMEOUT_MS') || '30000');
const ANTHROPIC_RETRY_COUNT = Number(Deno.env.get('ANTHROPIC_RETRY_COUNT') || '2');
const ANTHROPIC_INPUT_COST_PER_MILLION_TOKENS = Number(Deno.env.get('ANTHROPIC_INPUT_COST_PER_MILLION_TOKENS') || '0');
const ANTHROPIC_OUTPUT_COST_PER_MILLION_TOKENS = Number(Deno.env.get('ANTHROPIC_OUTPUT_COST_PER_MILLION_TOKENS') || '0');
const AI_RESEARCH_PROMPT_VERSION = Deno.env.get('AICRM_AI_RESEARCH_PROMPT_VERSION') || '2026-06-30.phase11';
const RATE_LIMIT_USER_PER_HOUR = Number(Deno.env.get('AICRM_ENRICHMENT_USER_LIMIT_PER_HOUR') || '25');
const RATE_LIMIT_ORG_PER_HOUR = Number(Deno.env.get('AICRM_ENRICHMENT_ORG_LIMIT_PER_HOUR') || '250');

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  throw new Error('Supabase environment variables are missing.');
}

const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false }
});

const VALID_JOB_TYPES = [
  'company_summary',
  'executive_brief',
  'product_fit',
  'next_action',
  'outreach_recommendation',
  'full_account_intelligence',
  'revenue_estimate',
  'employee_estimate',
  'category_classification',
  'buying_group_detection',
  'contact_role_recommendation',
  'website_discovery',
  'linkedin_discovery',
  'duplicate_detection',
  'score_explanation',
  'next_action_recommendation',
  'campaign_recommendation',
  'full_account_enrichment'
] as const;

const VALID_STATUSES = ['queued', 'running', 'completed', 'failed', 'cancelled', 'mock_completed'] as const;
const VALID_PROVIDERS = ['anthropic', 'mock'] as const;

type EnrichmentJobType = (typeof VALID_JOB_TYPES)[number];
type EnrichmentStatus = (typeof VALID_STATUSES)[number];

type Provider = (typeof VALID_PROVIDERS)[number];

type AccountRow = {
  id: string;
  organization_id: string;
  company_name: string | null;
  legal_name: string | null;
  category: string | null;
  segment: string | null;
  account_type: string | null;
  province: string | null;
  city: string | null;
  website: string | null;
  estimated_revenue: number | null;
  revenue_tier: string | null;
  employee_count: number | null;
  location_count: number | null;
  description: string | null;
  channel_product_fit: string | null;
  spec_channel_influence: string | null;
  next_action: string | null;
  status: string | null;
  updated_at: string | null;
  linkedin_company_url: string | null;
};

type ResearchRecord = {
  id?: string;
  organization_id: string;
  account_id: string;
  revenue_score: number | null;
  influence_score: number | null;
  growth_score: number | null;
  strategic_score: number | null;
  priority_score: number | null;
  score_explanation: string | null;
  confidence: number | null;
  research_summary: string | null;
  mock_generated: boolean | null;
  provider: string | null;
  model: string | null;
  prompt_version: string | null;
  review_status: string | null;
  executive_summary: string | null;
  company_summary: string | null;
  business_model: string | null;
  likely_customer_type: string | null;
  estimated_size: string | null;
  growth_indicators: string | null;
  buying_influence: Record<string, unknown> | null;
  sales_intelligence: string | null;
  recommended_contacts: unknown[] | null;
  recommended_products: unknown[] | null;
  recommended_campaign: string | null;
  recommended_campaign_reasoning: string | null;
  recommended_next_action: string | null;
  recommended_next_action_reasoning: string | null;
  recommended_next_action_confidence: number | null;
  product_fit_scores: Record<string, unknown> | null;
  source_fingerprint: string | null;
  output_payload: Record<string, unknown> | null;
  last_updated: string | null;
};

type AuditPayload = {
  actor_user_id: string;
  organization_id: string;
  account_id: string;
  job_id: string;
  event_type: string;
  job_type: string;
  provider: string;
  mock_mode: boolean;
  before_state: Record<string, unknown> | null;
  after_state: Record<string, unknown> | null;
};

type RunnerInput = {
  account_id?: string;
  job_type?: string;
  provider?: string;
  existing_job_id?: string;
};

type RelatedContactRow = {
  id: string;
  full_name: string | null;
  first_name: string | null;
  last_name: string | null;
  title: string | null;
  role_type: string | null;
  decision_maker: boolean;
  email: string | null;
  phone: string | null;
  direct_phone: string | null;
  linkedin_url: string | null;
  priority: string | null;
  email_status: string | null;
};

type RelatedOpportunityRow = {
  id: string;
  title: string;
  stage: string;
  status: string | null;
  opportunity_value: number | null;
  probability: number | null;
  expected_close_date: string | null;
};

type RelatedActivityRow = {
  id: string;
  activity_type: string;
  direction: string | null;
  activity_date: string;
  outcome: string | null;
  notes: string | null;
};

type RelatedNoteRow = {
  id: string;
  body: string;
  created_at: string;
};

type ProductCatalogRow = {
  id: string;
  name: string;
  brand: string;
  category: string | null;
  description: string | null;
  active: boolean | null;
};

type ExistingProductFitRow = {
  id: string;
  product_id: string;
  fit_score: number | null;
  fit_tier: string | null;
  fit_reason: string | null;
  recommended_sales_motion: string | null;
  recommended_campaign: string | null;
  confidence: number | null;
  source: string | null;
  reviewed_status: string | null;
  reviewed_by: string | null;
  reviewed_at: string | null;
  last_calculated_at: string | null;
};

type IntelligenceProductFit = {
  score: number;
  reasoning: string;
};

type IntelligenceOutput = {
  revenue_score: number;
  influence_score: number;
  growth_score: number;
  strategic_score: number;
  priority_score: number;
  company_summary: string;
  executive_summary: string;
  business_model: string;
  likely_customer_type: string;
  estimated_size: string;
  growth_indicators: string;
  buying_influence: {
    likely_decision_makers: string[];
    likely_purchasing_authority: string[];
    likely_departments: string[];
  };
  sales_intelligence: {
    buying_triggers: string[];
    likely_objections: string[];
    recommended_outreach_angle: string;
  };
  recommended_next_action: {
    recommendation: string;
    reasoning: string;
    confidence: number;
  };
  recommended_campaign: {
    recommendation: string;
    reasoning: string;
    confidence: number;
  };
  recommended_contacts: string[];
  recommended_products: string[];
  product_fit_scores: Record<string, IntelligenceProductFit>;
  research_summary: string;
  confidence: number;
  model?: string;
  prompt_version?: string;
  cached_reused?: boolean;
  source_fingerprint?: string;
};

type AccountIntelligenceContext = {
  account: AccountRow;
  contacts: RelatedContactRow[];
  opportunities: RelatedOpportunityRow[];
  activities: RelatedActivityRow[];
  notes: RelatedNoteRow[];
  sourceFingerprint: string;
};

function nowIso() {
  return new Date().toISOString();
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'Content-Type': 'application/json'
    }
  });
}

function isValidText(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function isValidJobType(value: string): value is EnrichmentJobType {
  return (VALID_JOB_TYPES as readonly string[]).includes(value);
}

function isValidStatus(value: string): value is EnrichmentStatus {
  return (VALID_STATUSES as readonly string[]).includes(value);
}

function isValidProvider(value: string): value is Provider {
  return (VALID_PROVIDERS as readonly string[]).includes(value);
}

function clampPercent(value: number | null | undefined) {
  if (value == null || !Number.isFinite(value)) {
    return null;
  }

  return Math.max(0, Math.min(100, value));
}

function parsePositive(value: unknown, fallback = 0) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return fallback;
  }

  return Math.max(0, value);
}

function computeSeedFromText(value: string) {
  if (!value) {
    return 0.17;
  }

  return (Array.from(value).reduce((acc, character) => (acc + character.charCodeAt(0)) * 13, 17) % 1000) / 1000;
}

function toSeededScore(seed: number, base = 50, variance = 20) {
  const value = (base + seed * variance + 0.25 * variance) % 100;
  return clampPercent(value);
}

function normalizeText(value: unknown) {
  if (typeof value !== 'string') {
    return '';
  }

  return value.trim();
}

function joinOrFallback(values: string[], fallback: string) {
  const filtered = values.map((value) => value.trim()).filter(Boolean);
  return filtered.length > 0 ? filtered.join(' · ') : fallback;
}

function toTopProductFit(productFitScores: Record<string, IntelligenceProductFit>) {
  const entries = Object.entries(productFitScores || {});
  if (entries.length === 0) {
    return [];
  }

  return entries
    .sort((left, right) => (right[1]?.score || 0) - (left[1]?.score || 0))
    .map(([product, payload]) => `${product}: ${Math.round(payload?.score || 0)}`)
    .slice(0, 4);
}

function extractJsonFromAnthropicText(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) {
    return '';
  }

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced?.[1]) {
    return fenced[1].trim();
  }

  const firstBrace = trimmed.indexOf('{');
  const lastBrace = trimmed.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    return trimmed.slice(firstBrace, lastBrace + 1);
  }

  return trimmed;
}

function stableStringify(value: unknown): string {
  if (value === null || value === undefined) {
    return 'null';
  }

  if (typeof value !== 'object') {
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((entry) => stableStringify(entry)).join(',')}]`;
  }

  const entries = Object.entries(value as Record<string, unknown>).sort(([left], [right]) => left.localeCompare(right));
  return `{${entries.map(([key, entry]) => `${JSON.stringify(key)}:${stableStringify(entry)}`).join(',')}}`;
}

function buildSourceFingerprint(payload: {
  account: AccountRow;
  contacts: RelatedContactRow[];
  opportunities: RelatedOpportunityRow[];
  activities: RelatedActivityRow[];
  notes: RelatedNoteRow[];
  jobType: EnrichmentJobType;
}) {
  return stableStringify({
    jobType: payload.jobType,
    account: {
      updated_at: payload.account.updated_at,
      company_name: payload.account.company_name,
      legal_name: payload.account.legal_name,
      category: payload.account.category,
      segment: payload.account.segment,
      account_type: payload.account.account_type,
      province: payload.account.province,
      city: payload.account.city,
      website: payload.account.website,
      estimated_revenue: payload.account.estimated_revenue,
      revenue_tier: payload.account.revenue_tier,
      employee_count: payload.account.employee_count,
      location_count: payload.account.location_count,
      description: payload.account.description,
      channel_product_fit: payload.account.channel_product_fit,
      spec_channel_influence: payload.account.spec_channel_influence,
      next_action: payload.account.next_action,
      status: payload.account.status
    },
    contacts: payload.contacts.map((contact) => ({
      full_name: contact.full_name,
      first_name: contact.first_name,
      last_name: contact.last_name,
      title: contact.title,
      role_type: contact.role_type,
      decision_maker: contact.decision_maker,
      email: contact.email,
      phone: contact.phone,
      direct_phone: contact.direct_phone,
      linkedin_url: contact.linkedin_url,
      priority: contact.priority,
      email_status: contact.email_status
    })),
    opportunities: payload.opportunities.map((opportunity) => ({
      title: opportunity.title,
      stage: opportunity.stage,
      status: opportunity.status,
      opportunity_value: opportunity.opportunity_value,
      probability: opportunity.probability,
      expected_close_date: opportunity.expected_close_date
    })),
    activities: payload.activities.slice(0, 10).map((activity) => ({
      activity_type: activity.activity_type,
      direction: activity.direction,
      activity_date: activity.activity_date,
      outcome: activity.outcome,
      notes: activity.notes
    })),
    notes: payload.notes.slice(0, 5).map((note) => note.body)
  });
}

function computePriorityScore(input: {
  revenueScore: number | null;
  influenceScore: number | null;
  growthScore: number | null;
  strategicScore: number | null;
}) {
  const revenue = clampPercent(input.revenueScore) ?? 0;
  const influence = clampPercent(input.influenceScore) ?? 0;
  const growth = clampPercent(input.growthScore) ?? 0;
  const strategic = clampPercent(input.strategicScore) ?? 0;

  return Number((0.4 * revenue + 0.3 * influence + 0.2 * growth + 0.1 * strategic).toFixed(2));
}

function buildMockOutput(context: AccountIntelligenceContext, jobType: EnrichmentJobType, provider: Provider): IntelligenceOutput {
  const { account } = context;
  const name = account.company_name || account.legal_name || 'Unknown account';
  const seed = computeSeedFromText(name);
  const revenueScore = toSeededScore(seed, 35, 55);
  const influenceScore = toSeededScore(seed + 0.11, 20, 70);
  const growthScore = toSeededScore(seed + 0.23, 25, 60);
  const strategicScore = toSeededScore(seed + 0.37, 30, 60);
  const priorityScore = computePriorityScore({
    revenueScore,
    influenceScore,
    growthScore,
    strategicScore
  });
  const baseEmployees = parsePositive(account.employee_count, 50);
  const revenueTier = account.revenue_tier || 'unavailable';

  const contacts = context.contacts;
  const decisionMakers = contacts.filter((contact) => contact.decision_maker).slice(0, 3);
  const recommendedContacts = (decisionMakers.length > 0 ? decisionMakers : contacts.slice(0, 3))
    .map((contact) => contact.full_name || [contact.first_name, contact.last_name].filter(Boolean).join(' ').trim() || 'Unknown contact')
    .filter(Boolean);

  const topProducts: Record<string, IntelligenceProductFit> = {
    Fotile: { score: revenueScore, reasoning: 'Premium kitchen channel fit inferred from account metadata.' },
    Dreame: { score: influenceScore, reasoning: 'Influence score suggests multi-stakeholder decision path.' },
    Mobila: { score: growthScore, reasoning: 'Growth indicators are consistent with active expansion or spec work.' },
    Nobilia: { score: strategicScore, reasoning: 'Strategic fit is strongest where kitchen/bath specification is present.' }
  };

  const recommendation = topProducts.Fotile.score >= topProducts.Nobilia.score ? 'Fotile' : 'Nobilia';

  return {
    revenue_score: revenueScore,
    influence_score: influenceScore,
    growth_score: growthScore,
    strategic_score: strategicScore,
    priority_score: priorityScore,
    company_summary: `${name} appears to be a ${account.category || 'category-unknown'} account with ${account.location_count || 1} location(s) and a ${revenueTier} revenue profile.`,
    executive_summary: `Mock executive brief for ${name}.`,
    business_model: account.segment || account.account_type || 'Unknown',
    likely_customer_type: account.category || 'Unknown',
    estimated_size: `${Math.max(baseEmployees, Math.round(baseEmployees + seed * 280))} employees (estimate)`,
    growth_indicators: joinOrFallback([
      account.next_action ? `Current next action: ${account.next_action}` : '',
      account.channel_product_fit ? `Product fit: ${account.channel_product_fit}` : '',
      account.spec_channel_influence ? `Specification influence noted.` : ''
    ], 'Limited growth signals present'),
    buying_influence: {
      likely_decision_makers: recommendedContacts.slice(0, 3),
      likely_purchasing_authority: ['operations', 'purchasing', 'finance'],
      likely_departments: ['purchasing', 'operations', 'specification']
    },
    sales_intelligence: {
      buying_triggers: ['new build activity', 'specification refresh', 'retail assortment update'],
      likely_objections: ['pricing', 'availability', 'implementation timing'],
      recommended_outreach_angle: 'Lead with channel fit and reduce adoption risk with a concise account-specific use case.'
    },
    recommended_next_action: {
      recommendation: account.next_action || 'Call the primary decision maker',
      reasoning: 'Mock recommendation generated from account metadata and relationship signals.',
      confidence: Number((65 + seed * 25).toFixed(1))
    },
    recommended_campaign: {
      recommendation: account.category || 'Kitchen & Bath',
      reasoning: 'Best-fit campaign inferred from account category and product/channel signal.',
      confidence: Number((60 + seed * 30).toFixed(1))
    },
    recommended_contacts: recommendedContacts,
    recommended_products: [recommendation],
    product_fit_scores: topProducts,
    research_summary: `Mock enrichment completed for ${name}. Synthetic result generated from available account profile fields.`,
    confidence: Number((68 + seed * 28).toFixed(1)),
    model: 'mock-deterministic',
    prompt_version: AI_RESEARCH_PROMPT_VERSION
  };
}

function normalizeProvider(input: string) {
  const normalized = isValidProvider(input) ? input : 'mock';
  if (normalized !== 'mock' && !ANTHROPIC_API_KEY) {
    return 'mock';
  }

  return normalized;
}

async function getUserFromToken(authHeader: string | null) {
  if (!authHeader?.startsWith('Bearer ')) {
    return null;
  }

  const token = authHeader.substring('Bearer '.length);

  const userClient = SUPABASE_ANON_KEY
    ? createClient(SUPABASE_URL as string, SUPABASE_ANON_KEY, {
        auth: { persistSession: false },
        global: { headers: { Authorization: `Bearer ${token}` } }
      })
    : serviceClient;

  const {
    data: { user },
    error
  } = await userClient.auth.getUser(token);

  if (error || !user) {
    return null;
  }

  return user;
}

async function assertOrgAccess(userId: string, organizationId: string) {
  const { data, error } = await serviceClient
    .from('organization_members')
    .select('id')
    .eq('user_id', userId)
    .eq('organization_id', organizationId)
    .eq('status', 'active')
    .limit(1)
    .maybeSingle();

  return !error && Boolean(data);
}

async function assertManageAccess(userId: string, organizationId: string) {
  const { data, error } = await serviceClient.rpc('user_can_access_organization', {
    p_organization_id: organizationId,
    p_permission_name: 'crm.manage',
    p_user_id: userId
  });

  return !error && Boolean(data);
}

async function writeAuditLog(payload: AuditPayload) {
  try {
    await serviceClient.from('aicrm_audit_log').insert({
      organization_id: payload.organization_id,
      actor_user_id: payload.actor_user_id,
      account_id: payload.account_id,
      job_id: payload.job_id,
      event_type: payload.event_type,
      job_type: payload.job_type,
      provider: payload.provider,
      mock_mode: payload.mock_mode,
      before_state: payload.before_state,
      after_state: payload.after_state
    });
  } catch {
    // Audit logging must never break enrichment processing.
  }
}

async function enforceRateLimit(userId: string, organizationId: string) {
  const windowStart = new Date(Date.now() - 60 * 60 * 1000).toISOString();

  const [userJobs, organizationJobs] = await Promise.all([
    serviceClient
      .from('aicrm_ai_enrichment_jobs')
      .select('id', { count: 'exact', head: true })
      .eq('requested_by', userId)
      .gte('created_at', windowStart),
    serviceClient
      .from('aicrm_ai_enrichment_jobs')
      .select('id', { count: 'exact', head: true })
      .eq('organization_id', organizationId)
      .gte('created_at', windowStart)
  ]);

  const userCount = userJobs.count ?? 0;
  const orgCount = organizationJobs.count ?? 0;

  if (userCount >= RATE_LIMIT_USER_PER_HOUR) {
    return {
      allowed: false,
      reason: `User enrichment rate limit exceeded (${userCount}/${RATE_LIMIT_USER_PER_HOUR} per hour).`
    };
  }

  if (orgCount >= RATE_LIMIT_ORG_PER_HOUR) {
    return {
      allowed: false,
      reason: `Organization enrichment rate limit exceeded (${orgCount}/${RATE_LIMIT_ORG_PER_HOUR} per hour).`
    };
  }

  return {
    allowed: true,
    reason: null
  };
}

async function loadProductCatalog(organizationId: string) {
  const { data, error } = await serviceClient
    .from('aicrm_products')
    .select('id,name,brand,category,description,active')
    .eq('organization_id', organizationId)
    .eq('active', true)
    .order('name', { ascending: true });

  if (error) {
    throw new Error(error.message);
  }

  return (data || []) as ProductCatalogRow[];
}

function normalizeFitTier(score: number, signalCount: number) {
  if (signalCount === 0 && score < 35) {
    return 'unknown';
  }

  if (score >= 80) {
    return 'high';
  }

  if (score >= 60) {
    return 'medium';
  }

  if (score >= 35) {
    return 'low';
  }

  if (score > 0) {
    return 'not_fit';
  }

  return 'unknown';
}

function containsAny(text: string, keywords: string[]) {
  return keywords.some((keyword) => keyword && text.includes(keyword.toLowerCase()));
}

function inferProductCampaign(productName: string, account: AccountRow) {
  const signal = `${String(account.category ?? '')} ${String(account.segment ?? '')} ${String(account.account_type ?? '')} ${String(account.description ?? '')} ${String(account.channel_product_fit ?? '')} ${String(account.spec_channel_influence ?? '')}`.toLowerCase();

  if (productName === 'Dreame') {
    if (containsAny(signal, ['national retailer', 'electronics', 'hardware', 'distribution'])) {
      return 'National Retailer';
    }
    if (containsAny(signal, ['buying group'])) {
      return 'Buying Group';
    }
    return 'Distributor';
  }

  if (productName === 'Fotile') {
    if (containsAny(signal, ['architect'])) {
      return 'Architect';
    }
    if (containsAny(signal, ['designer'])) {
      return 'Interior Designer';
    }
    if (containsAny(signal, ['builder', 'developer'])) {
      return containsAny(signal, ['multi']) ? 'Builder - Multi Family' : 'Builder - Single Family';
    }
    return containsAny(signal, ['showroom', 'dealer']) ? 'Kitchen & Bath' : 'Appliance Dealer';
  }

  if (productName === 'Mobila') {
    if (containsAny(signal, ['multi', 'developer'])) {
      return 'Builder - Multi Family';
    }
    if (containsAny(signal, ['builder'])) {
      return 'Builder - Single Family';
    }
    if (containsAny(signal, ['architect'])) {
      return 'Architect';
    }
    if (containsAny(signal, ['designer'])) {
      return 'Interior Designer';
    }
    return containsAny(signal, ['dealer']) ? 'Cabinet Dealer' : 'Kitchen & Bath';
  }

  if (productName === 'Nobilia') {
    if (containsAny(signal, ['multi', 'developer'])) {
      return 'Builder - Multi Family';
    }
    if (containsAny(signal, ['builder'])) {
      return 'Builder - Single Family';
    }
    if (containsAny(signal, ['architect'])) {
      return 'Architect';
    }
    if (containsAny(signal, ['designer'])) {
      return 'Interior Designer';
    }
    return 'Kitchen & Bath';
  }

  return 'Kitchen & Bath';
}

function computeProductFitRow(
  account: AccountRow,
  product: ProductCatalogRow,
  output: IntelligenceOutput,
  existingFit: ExistingProductFitRow | null
) {
  const context = `${String(account.category ?? '')} ${String(account.segment ?? '')} ${String(account.account_type ?? '')} ${String(account.description ?? '')} ${String(account.channel_product_fit ?? '')} ${String(account.spec_channel_influence ?? '')} ${String(account.next_action ?? '')}`.toLowerCase();
  const productName = product.name;
  const strongSignalsByProduct: Record<string, string[]> = {
    Fotile: ['kitchen', 'bath', 'showroom', 'appliance dealer', 'builder', 'developer', 'architect', 'designer', 'cabinet dealer', 'ventilation', 'design center'],
    Dreame: ['appliance dealer', 'national retailer', 'electronics', 'hardware', 'vacuum', 'robotics', 'smart home', 'retail', 'distribution'],
    Mobila: ['builder', 'developer', 'cabinet dealer', 'kitchen', 'bath', 'showroom', 'designer', 'architect', 'multi-family', 'renovation'],
    Nobilia: ['builder', 'developer', 'cabinet dealer', 'kitchen', 'bath', 'showroom', 'architect', 'designer', 'multi-family', 'design center']
  };

  const strongSignals = strongSignalsByProduct[productName] || [];
  const matchedSignals = strongSignals.filter((signal) => context.includes(signal.toLowerCase()));
  const aiSuggestion = output.product_fit_scores?.[productName];
  const aiScore = aiSuggestion && typeof aiSuggestion.score === 'number' ? clampPercent(aiSuggestion.score) : null;

  let fitScore = 22 + matchedSignals.length * 10;
  if (String(account.channel_product_fit ?? '').toLowerCase().includes(productName.toLowerCase())) {
    fitScore += 8;
  }
  if (String(account.spec_channel_influence ?? '').toLowerCase().includes('high') || String(account.spec_channel_influence ?? '').toLowerCase().includes('strong')) {
    fitScore += 5;
  }
  if ((account.location_count ?? 0) >= 10) {
    fitScore += 8;
  } else if ((account.location_count ?? 0) >= 5) {
    fitScore += 4;
  }
  if ((account.revenue_tier ?? '').toLowerCase().match(/[ab]/)) {
    fitScore += 4;
  }
  if (aiScore != null) {
    fitScore = Math.round(fitScore * 0.7 + aiScore * 0.3);
  }

  fitScore = clampPercent(fitScore) ?? 0;
  const fitTier = normalizeFitTier(fitScore, matchedSignals.length + (aiScore != null ? 1 : 0));
  const confidence = clampPercent(
    40 +
      matchedSignals.length * 10 +
      (String(account.channel_product_fit ?? '').trim() ? 8 : 0) +
      (String(account.website ?? '').trim() ? 6 : 0) +
      (String(account.category ?? '').trim() || String(account.segment ?? '').trim() || String(account.account_type ?? '').trim() ? 8 : 0) +
      (aiScore != null ? 8 : 0)
  ) ?? 0;
  const reasonPieces = [
    ...matchedSignals.slice(0, 3),
    aiSuggestion?.reasoning ? `AI: ${aiSuggestion.reasoning}` : null,
    aiScore != null ? `Anthropic score: ${Math.round(aiScore)}.` : null
  ].filter((value): value is string => Boolean(value));

  const fitReason = reasonPieces.length > 0
    ? `Matched signals for ${productName}: ${reasonPieces.join(', ')}`
    : `No strong ${productName} signals detected; baseline scoring applied.`;

  const recommendedCampaign = inferProductCampaign(productName, account);
  const recommendedSalesMotion =
    productName === 'Dreame'
      ? 'retail and distribution motion'
      : productName === 'Fotile'
        ? 'specifier-led showroom and builder development'
        : productName === 'Mobila'
          ? 'builder and renovation specification motion'
          : 'design-center and builder specification motion';

  return {
    fit_score: fitScore,
    fit_tier: fitTier,
    fit_reason: fitReason,
    recommended_sales_motion: recommendedSalesMotion,
    recommended_campaign: recommendedCampaign,
    confidence,
    source: aiScore != null ? 'ai' : 'system',
    reviewed_status: existingFit?.reviewed_status ?? 'pending'
  };
}

async function persistProductFitRows(context: AccountIntelligenceContext, output: IntelligenceOutput, userId: string, jobId: string) {
  const [productsResult, existingResult] = await Promise.all([
    loadProductCatalog(context.account.organization_id),
    serviceClient
      .from('aicrm_account_product_fit')
      .select('id,product_id,fit_score,fit_tier,fit_reason,recommended_sales_motion,recommended_campaign,confidence,source,reviewed_status,reviewed_by,reviewed_at,last_calculated_at')
      .eq('organization_id', context.account.organization_id)
      .eq('account_id', context.account.id)
  ]);

  const existingFits = (existingResult.data || []) as ExistingProductFitRow[];
  const existingByProductId = new Map(existingFits.map((row) => [row.product_id, row]));
  const beforeState = existingFits;
  const now = nowIso();
  const persistedRows: Array<Record<string, unknown>> = [];

  for (const product of productsResult) {
    const existingFit = existingByProductId.get(product.id) || null;
    if (existingFit?.source === 'manual' && existingFit.reviewed_status !== 'needs_review') {
      persistedRows.push(existingFit as unknown as Record<string, unknown>);
      continue;
    }

    const computed = computeProductFitRow(context.account, product, output, existingFit);
    const payload = {
      organization_id: context.account.organization_id,
      account_id: context.account.id,
      product_id: product.id,
      fit_score: computed.fit_score,
      fit_tier: computed.fit_tier,
      fit_reason: computed.fit_reason,
      recommended_sales_motion: computed.recommended_sales_motion,
      recommended_campaign: computed.recommended_campaign,
      confidence: computed.confidence,
      source: computed.source,
      reviewed_status: existingFit?.reviewed_status || computed.reviewed_status,
      reviewed_by: existingFit?.reviewed_by || null,
      reviewed_at: existingFit?.reviewed_at || null,
      last_calculated_at: now
    };

    const { error } = await serviceClient.from('aicrm_account_product_fit').upsert(payload, {
      onConflict: 'organization_id,account_id,product_id'
    });

    if (error) {
      throw new Error(`Unable to persist product fit for ${product.name}: ${error.message}`);
    }

    persistedRows.push(payload);
  }

  await writeAuditLog({
    actor_user_id: userId,
    organization_id: context.account.organization_id,
    account_id: context.account.id,
    job_id: jobId,
    event_type: 'product_fit_calculated',
    job_type: 'product_fit',
    provider: output.model?.startsWith('mock') ? 'mock' : 'anthropic',
    mock_mode: Boolean(output.model?.startsWith('mock')),
    before_state: { product_fits: beforeState },
    after_state: { product_fits: persistedRows }
  });
}

function normalizeResearchPayload(existing: ResearchRecord | null, output: IntelligenceOutput) {
  const revenue = clampPercent(typeof output.revenue_score === 'number' ? output.revenue_score : null);
  const influence = clampPercent(typeof output.influence_score === 'number' ? output.influence_score : null);
  const growth = clampPercent(typeof output.growth_score === 'number' ? output.growth_score : null);
  const strategic = clampPercent(typeof output.strategic_score === 'number' ? output.strategic_score : null);
  const confidenceValue = typeof output.confidence === 'number' ? output.confidence : null;

  return {
    research_summary: output.research_summary != null ? String(output.research_summary) : (existing?.research_summary ?? null),
    executive_summary: output.executive_summary != null ? String(output.executive_summary) : (existing?.executive_summary ?? null),
    company_summary: output.company_summary != null ? String(output.company_summary) : (existing?.company_summary ?? null),
    business_model: output.business_model != null ? String(output.business_model) : (existing?.business_model ?? null),
    likely_customer_type: output.likely_customer_type != null ? String(output.likely_customer_type) : (existing?.likely_customer_type ?? null),
    estimated_size: output.estimated_size != null ? String(output.estimated_size) : (existing?.estimated_size ?? null),
    growth_indicators: output.growth_indicators != null ? String(output.growth_indicators) : (existing?.growth_indicators ?? null),
    buying_influence: output.buying_influence && typeof output.buying_influence === 'object' ? output.buying_influence : (existing?.buying_influence ?? {}),
    sales_intelligence: output.sales_intelligence != null ? String(output.sales_intelligence) : (existing?.sales_intelligence ?? null),
    recommended_contacts: Array.isArray(output.recommended_contacts) ? output.recommended_contacts : (existing?.recommended_contacts ?? []),
    recommended_products: Array.isArray(output.recommended_products) ? output.recommended_products : (existing?.recommended_products ?? []),
    recommended_campaign:
      output.recommended_campaign && typeof output.recommended_campaign === 'object'
        ? normalizeText((output.recommended_campaign as { recommendation?: unknown }).recommendation)
        : (existing?.recommended_campaign ?? null),
    recommended_campaign_reasoning:
      output.recommended_campaign && typeof output.recommended_campaign === 'object'
        ? normalizeText((output.recommended_campaign as { reasoning?: unknown }).reasoning)
        : (existing?.recommended_campaign_reasoning ?? null),
    recommended_next_action:
      output.recommended_next_action && typeof output.recommended_next_action === 'object'
        ? normalizeText((output.recommended_next_action as { recommendation?: unknown }).recommendation)
        : (existing?.recommended_next_action ?? null),
    recommended_next_action_reasoning:
      output.recommended_next_action && typeof output.recommended_next_action === 'object'
        ? normalizeText((output.recommended_next_action as { reasoning?: unknown }).reasoning)
        : (existing?.recommended_next_action_reasoning ?? null),
    recommended_next_action_confidence:
      output.recommended_next_action && typeof output.recommended_next_action === 'object'
        ? clampPercent((output.recommended_next_action as { confidence?: unknown }).confidence as number | null | undefined)
        : (existing?.recommended_next_action_confidence ?? null),
    product_fit_scores: output.product_fit_scores && typeof output.product_fit_scores === 'object' ? output.product_fit_scores : (existing?.product_fit_scores ?? {}),
    revenue_score: revenue,
    influence_score: influence,
    growth_score: growth,
    strategic_score: strategic,
    priority_score: computePriorityScore({
      revenueScore: revenue,
      influenceScore: influence,
      growthScore: growth,
      strategicScore: strategic
    }),
    score_explanation: output.score_explanation != null ? String(output.score_explanation) : null,
    confidence: typeof confidenceValue === 'number' ? clampPercent(confidenceValue) : (existing?.confidence ?? null),
    provider: String(output.model ? (output.model.startsWith('mock') ? 'mock' : 'anthropic') : (existing?.provider || 'mock')),
    model: output.model ?? existing?.model ?? null,
    prompt_version: output.prompt_version ?? existing?.prompt_version ?? AI_RESEARCH_PROMPT_VERSION,
    review_status: existing?.review_status ?? 'pending',
    source_fingerprint: output.source_fingerprint ?? existing?.source_fingerprint ?? null,
    mock_generated: Boolean(output.cached_reused ? existing?.mock_generated : output.model?.startsWith('mock')),
    output_payload: output as unknown as Record<string, unknown>,
    last_updated: nowIso()
  };
}

async function loadAccountIntelligenceContext(account: AccountRow, jobType: EnrichmentJobType): Promise<AccountIntelligenceContext> {
  const [contactsResult, opportunitiesResult, activitiesResult, notesResult] = await Promise.all([
    serviceClient
      .from('aicrm_contacts')
      .select('id,full_name,first_name,last_name,title,role_type,decision_maker,email,phone,direct_phone,linkedin_url,priority,email_status')
      .eq('organization_id', account.organization_id)
      .eq('account_id', account.id)
      .order('decision_maker', { ascending: false })
      .order('influence_score', { ascending: false, nullsFirst: false }),
    serviceClient
      .from('aicrm_opportunities')
      .select('id,title,stage,status,opportunity_value,probability,expected_close_date')
      .eq('organization_id', account.organization_id)
      .eq('account_id', account.id)
      .order('opportunity_value', { ascending: false, nullsFirst: false }),
    serviceClient
      .from('aicrm_activities')
      .select('id,activity_type,direction,activity_date,outcome,notes')
      .eq('organization_id', account.organization_id)
      .eq('account_id', account.id)
      .order('activity_date', { ascending: false })
      .limit(12),
    serviceClient
      .from('aicrm_notes')
      .select('id,body,created_at')
      .eq('organization_id', account.organization_id)
      .eq('account_id', account.id)
      .order('created_at', { ascending: false })
      .limit(5)
  ]);

  if (contactsResult.error || opportunitiesResult.error || activitiesResult.error || notesResult.error) {
    throw new Error(
      [
        contactsResult.error?.message,
        opportunitiesResult.error?.message,
        activitiesResult.error?.message,
        notesResult.error?.message
      ]
        .filter(Boolean)
        .join(' | ')
    );
  }

  const contacts = (contactsResult.data || []) as RelatedContactRow[];
  const opportunities = (opportunitiesResult.data || []) as RelatedOpportunityRow[];
  const activities = (activitiesResult.data || []) as RelatedActivityRow[];
  const notes = (notesResult.data || []) as RelatedNoteRow[];

  return {
    account,
    contacts,
    opportunities,
    activities,
    notes,
    sourceFingerprint: buildSourceFingerprint({
      account,
      contacts,
      opportunities,
      activities,
      notes,
      jobType
    })
  };
}

function normalizeProductFitScores(raw: unknown, account: AccountRow) {
  const defaultScores: Record<string, IntelligenceProductFit> = {
    Fotile: { score: 50, reasoning: 'Base score until Anthropic output is available.' },
    Dreame: { score: 50, reasoning: 'Base score until Anthropic output is available.' },
    Mobila: { score: 50, reasoning: 'Base score until Anthropic output is available.' },
    Nobilia: { score: 50, reasoning: 'Base score until Anthropic output is available.' }
  };

  if (!raw || typeof raw !== 'object') {
    return defaultScores;
  }

  const source = raw as Record<string, unknown>;
  const normalized: Record<string, IntelligenceProductFit> = { ...defaultScores };

  for (const product of Object.keys(defaultScores)) {
    const entry = source[product];
    if (!entry || typeof entry !== 'object') {
      continue;
    }

    const typed = entry as Record<string, unknown>;
    normalized[product] = {
      score: clampPercent(typeof typed.score === 'number' ? typed.score : Number(typed.score)) ?? defaultScores[product].score,
      reasoning: normalizeText(typed.reasoning) || defaultScores[product].reasoning
    };
  }

  if (!normalizeText(account.channel_product_fit)) {
    normalized.Fotile.reasoning = 'No channel/product fit data present; using baseline fit.';
  }

  return normalized;
}

function normalizeStringArray(value: unknown, fallback: string[]) {
  if (!Array.isArray(value)) {
    return fallback;
  }

  return value.map((entry) => normalizeText(entry)).filter(Boolean);
}

function normalizeAnthropicOutput(raw: Record<string, unknown>, context: AccountIntelligenceContext, jobType: EnrichmentJobType): IntelligenceOutput {
  const revenueScore = clampPercent(typeof raw.revenue_score === 'number' ? raw.revenue_score : Number(raw.revenue_score)) ?? 50;
  const influenceScore = clampPercent(typeof raw.influence_score === 'number' ? raw.influence_score : Number(raw.influence_score)) ?? 50;
  const growthScore = clampPercent(typeof raw.growth_score === 'number' ? raw.growth_score : Number(raw.growth_score)) ?? 50;
  const strategicScore = clampPercent(typeof raw.strategic_score === 'number' ? raw.strategic_score : Number(raw.strategic_score)) ?? 50;
  const priorityScore = clampPercent(typeof raw.priority_score === 'number' ? raw.priority_score : Number(raw.priority_score)) ?? computePriorityScore({
    revenueScore,
    influenceScore,
    growthScore,
    strategicScore
  });

  const productFitScores = normalizeProductFitScores(raw.product_fit_scores, context.account);
  const recommendedProducts = normalizeStringArray(raw.recommended_products, toTopProductFit(productFitScores));

  return {
    revenue_score: revenueScore,
    influence_score: influenceScore,
    growth_score: growthScore,
    strategic_score: strategicScore,
    priority_score: priorityScore,
    company_summary: normalizeText(raw.company_summary) || `${context.account.company_name || context.account.legal_name || 'Unknown account'} intelligence summary.`,
    executive_summary: normalizeText(raw.executive_summary) || normalizeText(raw.company_summary) || '',
    business_model: normalizeText(raw.business_model) || context.account.segment || context.account.account_type || 'Unknown',
    likely_customer_type: normalizeText(raw.likely_customer_type) || context.account.category || 'Unknown',
    estimated_size: normalizeText(raw.estimated_size) || `${context.account.employee_count || 'unknown'} employees`,
    growth_indicators: normalizeText(raw.growth_indicators) || joinOrFallback([context.account.next_action || '', context.account.description || ''], 'Limited growth indicators available'),
    buying_influence: {
      likely_decision_makers: normalizeStringArray(
        (raw.buying_influence as Record<string, unknown> | undefined)?.likely_decision_makers,
        context.contacts.filter((contact) => contact.decision_maker).map((contact) => contact.full_name || contact.title || 'Decision maker').slice(0, 3)
      ),
      likely_purchasing_authority: normalizeStringArray(
        (raw.buying_influence as Record<string, unknown> | undefined)?.likely_purchasing_authority,
        ['purchasing', 'operations', 'finance']
      ),
      likely_departments: normalizeStringArray(
        (raw.buying_influence as Record<string, unknown> | undefined)?.likely_departments,
        ['purchasing', 'operations', 'specification']
      )
    },
    sales_intelligence: {
      buying_triggers: normalizeStringArray(
        (raw.sales_intelligence as Record<string, unknown> | undefined)?.buying_triggers,
        ['new project start', 'specification refresh']
      ),
      likely_objections: normalizeStringArray(
        (raw.sales_intelligence as Record<string, unknown> | undefined)?.likely_objections,
        ['pricing', 'timing']
      ),
      recommended_outreach_angle:
        normalizeText((raw.sales_intelligence as Record<string, unknown> | undefined)?.recommended_outreach_angle) ||
        'Lead with account-specific channel fit and a concise reason to engage.'
    },
    recommended_next_action: {
      recommendation:
        normalizeText((raw.recommended_next_action as Record<string, unknown> | undefined)?.recommendation) ||
        context.account.next_action ||
        'Call the primary contact',
      reasoning:
        normalizeText((raw.recommended_next_action as Record<string, unknown> | undefined)?.reasoning) ||
        'Generated from account and relationship signals.',
      confidence:
        clampPercent((raw.recommended_next_action as Record<string, unknown> | undefined)?.confidence as number | null | undefined) ??
        60
    },
    recommended_campaign: {
      recommendation:
        normalizeText((raw.recommended_campaign as Record<string, unknown> | undefined)?.recommendation) ||
        context.account.category ||
        'Kitchen & Bath',
      reasoning:
        normalizeText((raw.recommended_campaign as Record<string, unknown> | undefined)?.reasoning) ||
        'Campaign aligned to account category and channel signals.',
      confidence:
        clampPercent((raw.recommended_campaign as Record<string, unknown> | undefined)?.confidence as number | null | undefined) ??
        60
    },
    recommended_contacts: normalizeStringArray(raw.recommended_contacts, context.contacts.map((contact) => contact.full_name || contact.title || 'Contact').slice(0, 5)),
    recommended_products: recommendedProducts,
    product_fit_scores: productFitScores,
    research_summary: normalizeText(raw.research_summary) || normalizeText(raw.executive_summary) || 'Account intelligence brief generated.',
    confidence: clampPercent(typeof raw.confidence === 'number' ? raw.confidence : Number(raw.confidence)) ?? 60,
    model: normalizeText(raw.model) || ANTHROPIC_MODEL,
    prompt_version: normalizeText(raw.prompt_version) || AI_RESEARCH_PROMPT_VERSION,
    source_fingerprint: normalizeText(raw.source_fingerprint) || context.sourceFingerprint
  };
}

function buildAccountIntelligencePrompt(context: AccountIntelligenceContext, jobType: EnrichmentJobType) {
  return {
    account: {
      company_name: context.account.company_name,
      legal_name: context.account.legal_name,
      category: context.account.category,
      segment: context.account.segment,
      account_type: context.account.account_type,
      province: context.account.province,
      city: context.account.city,
      website: context.account.website,
      estimated_revenue: context.account.estimated_revenue,
      revenue_tier: context.account.revenue_tier,
      employee_count: context.account.employee_count,
      location_count: context.account.location_count,
      description: context.account.description,
      channel_product_fit: context.account.channel_product_fit,
      spec_channel_influence: context.account.spec_channel_influence,
      next_action: context.account.next_action,
      status: context.account.status
    },
    contacts: context.contacts,
    opportunities: context.opportunities,
    activities: context.activities,
    notes: context.notes,
    requested_job_type: jobType,
    prompt_version: AI_RESEARCH_PROMPT_VERSION,
    required_output: {
      revenue_score: '0-100',
      influence_score: '0-100',
      growth_score: '0-100',
      strategic_score: '0-100',
      priority_score: '0-100',
      company_summary: 'text',
      executive_summary: 'text',
      business_model: 'text',
      likely_customer_type: 'text',
      estimated_size: 'text',
      growth_indicators: 'text',
      buying_influence: {
        likely_decision_makers: ['string'],
        likely_purchasing_authority: ['string'],
        likely_departments: ['string']
      },
      sales_intelligence: {
        buying_triggers: ['string'],
        likely_objections: ['string'],
        recommended_outreach_angle: 'string'
      },
      recommended_next_action: {
        recommendation: 'string',
        reasoning: 'string',
        confidence: '0-100'
      },
      recommended_campaign: {
        recommendation: 'string',
        reasoning: 'string',
        confidence: '0-100'
      },
      recommended_contacts: ['string'],
      recommended_products: ['string'],
      product_fit_scores: {
        Fotile: { score: '0-100', reasoning: 'string' },
        Dreame: { score: '0-100', reasoning: 'string' },
        Mobila: { score: '0-100', reasoning: 'string' },
        Nobilia: { score: '0-100', reasoning: 'string' }
      },
      research_summary: 'text',
      confidence: '0-100'
    }
  };
}

async function loadAccountIntelligencePromptTemplate(organizationId: string) {
  const { data, error } = await serviceClient
    .from('ai_prompt_templates')
    .select('id,organization_id,prompt_key,prompt_version,application,use_case,status,priority,tone_guidance,system_prompt,user_prompt_template,variables,output_schema,version,version_history,source_system,created_at,updated_at')
    .eq('prompt_key', 'account_intelligence')
    .eq('use_case', 'account_intelligence')
    .eq('status', 'active');

  if (error || !data || !Array.isArray(data)) {
    return null;
  }

  return selectAiPromptTemplate(data as Array<Record<string, unknown>>, {
    organizationId,
    promptKey: 'account_intelligence',
    useCase: 'account_intelligence',
    promptVersion: AI_RESEARCH_PROMPT_VERSION,
    application: 'applianceiq'
  });
}

async function fetchAnthropicAccountIntelligence(context: AccountIntelligenceContext, jobType: EnrichmentJobType): Promise<{ output: IntelligenceOutput; usage: { input_tokens: number; output_tokens: number }; model: string }> {
  const prompt = buildAccountIntelligencePrompt(context, jobType);
  const promptTemplate = await loadAccountIntelligencePromptTemplate(context.account.organization_id);
  const promptJson = JSON.stringify(prompt, null, 2);
  const promptText = composeAiPrompt(
    promptTemplate,
    {
      subject: 'Generate account intelligence for this CRM record.',
      job_type: jobType,
      prompt_version: AI_RESEARCH_PROMPT_VERSION,
      account_name: String(context.account.company_name || context.account.legal_name || ''),
      prompt_json: promptJson,
      context_json: promptJson
    },
    `Generate account intelligence for this CRM record. Focus on company intelligence, account prioritization, channel intelligence, product fit, next action recommendations, and outreach recommendations.\n\n${promptJson}`
  );
  const response = await callAnthropicMessages({
    apiKey: ANTHROPIC_API_KEY,
    model: ANTHROPIC_MODEL,
    prompt: promptText,
    maxTokens: ANTHROPIC_MAX_TOKENS,
    timeoutMs: ANTHROPIC_TIMEOUT_MS,
    retryCount: ANTHROPIC_RETRY_COUNT,
    temperature: 0.2
  });

  if (response.provider !== 'anthropic') {
    return {
      output: buildMockOutput(context, jobType, 'mock'),
      usage: {
        input_tokens: response.usage.inputTokens,
        output_tokens: response.usage.outputTokens
      },
      model: response.model
    };
  }

  const jsonText = extractJsonFromAnthropicText(response.text);
  if (!jsonText) {
    return {
      output: buildMockOutput(context, jobType, 'mock'),
      usage: {
        input_tokens: response.usage.inputTokens,
        output_tokens: response.usage.outputTokens
      },
      model: response.model
    };
  }

  const parsed = JSON.parse(jsonText) as Record<string, unknown>;
  return {
    output: normalizeAnthropicOutput(parsed, context, jobType),
    usage: {
      input_tokens: response.usage.inputTokens,
      output_tokens: response.usage.outputTokens
    },
    model: response.model
  };
}

function estimateAnthropicCost(usage: { input_tokens: number; output_tokens: number }) {
  return Number(
    (
      (usage.input_tokens / 1_000_000) * ANTHROPIC_INPUT_COST_PER_MILLION_TOKENS +
      (usage.output_tokens / 1_000_000) * ANTHROPIC_OUTPUT_COST_PER_MILLION_TOKENS
    ).toFixed(6)
  );
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return jsonResponse({ ok: false, error: 'Method not allowed' }, 405);
  }

  const user = await getUserFromToken(req.headers.get('authorization'));
  if (!user) {
    return jsonResponse({ ok: false, error: 'Unauthorized' }, 401);
  }

  let body: RunnerInput;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ ok: false, error: 'Invalid JSON payload' }, 400);
  }

  const requestedJobType = isValidText(body.job_type);
  const requestedProvider = normalizeProvider(isValidText(body.provider) || 'mock');
  const existingJobId = isValidText(body.existing_job_id);
  const requestedAccountId = isValidText(body.account_id);

  if (!requestedProvider) {
    return jsonResponse({ ok: false, error: 'provider is required' }, 400);
  }

  let jobType = requestedJobType;
  let organizationId = '';
  let accountId = requestedAccountId;
  let jobId = '';

  if (existingJobId) {
    const { data: jobRow, error: existingJobError } = await serviceClient
      .from('aicrm_ai_enrichment_jobs')
      .select('id, organization_id, account_id, job_type, provider, status')
      .eq('id', existingJobId)
      .maybeSingle();

    if (existingJobError || !jobRow) {
      return jsonResponse({ ok: false, error: 'Existing job not found' }, 404);
    }

    if (!isValidStatus(String(jobRow.status)) || String(jobRow.status) !== 'failed') {
      return jsonResponse({ ok: false, error: 'Only failed jobs can be retried' }, 409);
    }

    if (!isValidJobType(String(jobRow.job_type))) {
      return jsonResponse({ ok: false, error: `Unsupported job type: ${String(jobRow.job_type)}` }, 400);
    }

    organizationId = String(jobRow.organization_id);
    accountId = String(jobRow.account_id);
    jobType = String(jobRow.job_type);
    jobId = String(jobRow.id);
  } else {
    if (!accountId) {
      return jsonResponse({ ok: false, error: 'account_id is required' }, 400);
    }

    if (!isValidJobType(requestedJobType)) {
      return jsonResponse({ ok: false, error: `Unsupported job type: ${requestedJobType || '(missing)'}` }, 400);
    }

    const { data: accountRow, error: accountError } = await serviceClient
      .from('aicrm_accounts')
      .select('id,organization_id,company_name,legal_name,category,segment,account_type,province,city,website,estimated_revenue,revenue_tier,employee_count,location_count,description,channel_product_fit,spec_channel_influence,next_action,status,updated_at,linkedin_company_url')
      .eq('id', accountId)
      .maybeSingle<AccountRow>();

    if (accountError || !accountRow) {
      return jsonResponse({ ok: false, error: `Account not found` }, 404);
    }

    organizationId = accountRow.organization_id;
  }

  if (!organizationId || !accountId) {
    return jsonResponse({ ok: false, error: 'Unable to resolve account context' }, 400);
  }

  const accountQuery = await serviceClient
    .from('aicrm_accounts')
    .select('id,organization_id,company_name,legal_name,category,segment,account_type,province,city,website,estimated_revenue,revenue_tier,employee_count,location_count,description,channel_product_fit,spec_channel_influence,next_action,status,updated_at,linkedin_company_url')
    .eq('id', accountId)
    .maybeSingle<AccountRow>();

  if (accountQuery.error || !accountQuery.data) {
    return jsonResponse({ ok: false, error: 'Account not found while running job' }, 404);
  }

  const account = accountQuery.data;
  organizationId = account.organization_id;

  const hasMockMode = requestedProvider === 'mock' || !ANTHROPIC_API_KEY;
  const finalProvider: Provider = hasMockMode ? 'mock' : requestedProvider;
  const intelligenceContext = await loadAccountIntelligenceContext(serviceClient, organizationId, accountId);
  const sourceFingerprint = buildSourceFingerprint(account, intelligenceContext);

  const canAccess = await assertOrgAccess(user.id, organizationId);
  if (!canAccess) {
    return jsonResponse({ ok: false, error: 'You do not have access to this organization' }, 403);
  }

  const canManage = await assertManageAccess(user.id, organizationId);
  if (!canManage) {
    await writeAuditLog({
      actor_user_id: user.id,
      organization_id: organizationId,
      account_id: accountId,
      job_id: jobId || null,
      event_type: 'enrichment_forbidden',
      job_type: jobType as EnrichmentJobType,
      provider: requestedProvider,
      mock_mode: true,
      before_state: { reason: 'crm.manage required' },
      after_state: null
    });

    return jsonResponse({ ok: false, error: 'crm.manage permission required for enrichment jobs' }, 403);
  }

  const rateLimit = await enforceRateLimit(user.id, organizationId);
  if (!rateLimit.allowed) {
    await writeAuditLog({
      actor_user_id: user.id,
      organization_id: organizationId,
      account_id: accountId,
      job_id: jobId || null,
      event_type: 'enrichment_rate_limited',
      job_type: jobType as EnrichmentJobType,
      provider: requestedProvider,
      mock_mode: true,
      before_state: { reason: rateLimit.reason },
      after_state: null
    });

    return jsonResponse({ ok: false, error: rateLimit.reason }, 429);
  }

  if (!existingJobId) {
    const { data: newJob, error: createError } = await serviceClient
      .from('aicrm_ai_enrichment_jobs')
      .insert({
        organization_id: organizationId,
        account_id: accountId,
        requested_by: user.id,
        job_type: jobType,
        provider: requestedProvider,
        status: 'queued',
        input_payload: {
          account_id: accountId,
          job_type: jobType,
          provider: requestedProvider,
          requested_by: user.id,
          reason: 'manual_run'
        },
        mock_mode: requestedProvider === 'mock'
      })
      .select('id')
      .single();

    if (createError || !newJob) {
      return jsonResponse({ ok: false, error: `Unable to create enrichment job: ${createError?.message || 'unknown error'}` }, 500);
    }

    jobId = String(newJob.id);
  }

  const startedAt = nowIso();

  const { error: markRunningError } = await serviceClient
    .from('aicrm_ai_enrichment_jobs')
    .update({
      status: 'running',
      provider: finalProvider,
      model: finalProvider === 'anthropic' ? ANTHROPIC_MODEL : 'mock-deterministic',
      prompt_version: AI_RESEARCH_PROMPT_VERSION,
      source_fingerprint: sourceFingerprint,
      mock_mode: hasMockMode,
      started_at: startedAt
    })
    .eq('id', jobId);

  if (markRunningError) {
    return jsonResponse({ ok: false, error: `Unable to mark job running: ${markRunningError.message}` }, 500);
  }

  const beforeRows = await serviceClient
    .from('aicrm_ai_research')
    .select('id,organization_id,account_id,revenue_score,influence_score,growth_score,strategic_score,priority_score,score_explanation,confidence,research_summary,mock_generated,provider,model,prompt_version,review_status,reviewed_by,reviewed_at,output_payload,last_updated,executive_summary,company_summary,business_model,likely_customer_type,estimated_size,growth_indicators,buying_influence,sales_intelligence,recommended_contacts,recommended_products,recommended_campaign,recommended_campaign_reasoning,recommended_next_action,recommended_next_action_reasoning,recommended_next_action_confidence,product_fit_scores,source_fingerprint')
    .eq('organization_id', organizationId)
    .eq('account_id', accountId)
    .maybeSingle<ResearchRecord>();

  const beforeState: Record<string, unknown> = beforeRows.data ? { ...beforeRows.data } : {};

  try {
    const cachedOutput = beforeRows.data?.output_payload;
    const canReuseCachedOutput =
      Boolean(cachedOutput) &&
      beforeRows.data?.source_fingerprint === sourceFingerprint &&
      beforeRows.data?.provider === finalProvider &&
      beforeRows.data?.model === (finalProvider === 'anthropic' ? ANTHROPIC_MODEL : 'mock-deterministic');

    let output: IntelligenceOutput;
    let tokensUsed = 0;
    let costEstimate = 0;
    let rawResponse: Record<string, unknown> | null = null;

    if (canReuseCachedOutput) {
      output = normalizeAnthropicOutput(cachedOutput);
      output.cached_reused = true;
    } else if (finalProvider === 'anthropic') {
      const anthropicResult = await fetchAnthropicAccountIntelligence({
        account,
        context: intelligenceContext,
        jobType: jobType as EnrichmentJobType,
        model: ANTHROPIC_MODEL,
        promptVersion: AI_RESEARCH_PROMPT_VERSION,
        sourceFingerprint
      });
      output = anthropicResult.output;
      tokensUsed = anthropicResult.tokensUsed;
      costEstimate = anthropicResult.costEstimate;
      rawResponse = anthropicResult.rawResponse;
    } else {
      output = buildMockOutput(account, jobType as EnrichmentJobType, finalProvider);
    }

    const normalizedOutput = normalizeAnthropicOutput({
      ...output,
      provider: finalProvider,
      generated_at: nowIso(),
      job_type: jobType,
      mock_mode: hasMockMode,
      source_fingerprint: sourceFingerprint
    });
    const normalized = normalizeResearchPayload(beforeRows.data, normalizedOutput);

    await serviceClient.from('aicrm_ai_research').upsert(
      {
        organization_id: organizationId,
        account_id: account.id,
        research_summary: normalized.research_summary,
        revenue_score: normalized.revenue_score,
        influence_score: normalized.influence_score,
        growth_score: normalized.growth_score,
        strategic_score: normalized.strategic_score,
        priority_score: normalized.priority_score,
        score_explanation: normalized.score_explanation,
        confidence: normalized.confidence,
        provider: normalized.provider,
        model: normalized.model,
        prompt_version: normalized.prompt_version,
        review_status: normalized.review_status,
        reviewed_by: normalized.reviewed_by,
        reviewed_at: normalized.reviewed_at,
        mock_generated: normalized.mock_generated,
        output_payload: normalized.output_payload,
        last_updated: normalized.last_updated,
        executive_summary: normalized.executive_summary,
        company_summary: normalized.company_summary,
        business_model: normalized.business_model,
        likely_customer_type: normalized.likely_customer_type,
        estimated_size: normalized.estimated_size,
        growth_indicators: normalized.growth_indicators,
        buying_influence: normalized.buying_influence,
        sales_intelligence: normalized.sales_intelligence,
        recommended_contacts: normalized.recommended_contacts,
        recommended_products: normalized.recommended_products,
        recommended_campaign: normalized.recommended_campaign,
        recommended_campaign_reasoning: normalized.recommended_campaign_reasoning,
        recommended_next_action: normalized.recommended_next_action,
        recommended_next_action_reasoning: normalized.recommended_next_action_reasoning,
        recommended_next_action_confidence: normalized.recommended_next_action_confidence,
        product_fit_scores: normalized.product_fit_scores,
        source_fingerprint: sourceFingerprint
      },
      { onConflict: 'organization_id,account_id' }
    );

    await persistProductFitRows({
      account,
      contacts: intelligenceContext.contacts,
      opportunities: intelligenceContext.opportunities,
      activities: intelligenceContext.activities,
      notes: intelligenceContext.notes,
      sourceFingerprint: sourceFingerprint
    }, normalized, user.id, jobId);

    const completedAt = nowIso();
    const finalStatus: EnrichmentStatus = hasMockMode ? 'mock_completed' : 'completed';

    const { data: runData } = await serviceClient
      .from('aicrm_enrichment_runs')
      .insert({
        organization_id: organizationId,
        account_id: accountId,
        enrichment_job_id: jobId,
        job_type: jobType,
        provider: finalProvider,
        model: normalized.model,
        prompt_version: normalized.prompt_version,
        source_fingerprint: sourceFingerprint,
        status: finalStatus,
        started_at: startedAt,
        completed_at: completedAt,
        input_payload: {
          account_id: accountId,
          requested_by: user.id,
          provider: finalProvider,
          job_type: jobType
        },
        output_payload: {
          ...normalized.output_payload,
          raw_response: rawResponse
        },
        before_state: beforeRows.data ? beforeRows.data : null,
        after_state: normalized,
        error_message: null,
        cost_estimate: costEstimate,
        tokens_used: tokensUsed,
        mock_mode: hasMockMode
      })
      .select('id')
      .single();

    await serviceClient
      .from('aicrm_ai_enrichment_jobs')
      .update({
        status: finalStatus,
        output_payload: normalized.output_payload,
        completed_at: completedAt,
        cost_estimate: costEstimate,
        tokens_used: tokensUsed,
        provider: finalProvider,
        model: normalized.model,
        prompt_version: normalized.prompt_version,
        source_fingerprint: sourceFingerprint,
        mock_mode: hasMockMode
      })
      .eq('id', jobId);

    await writeAuditLog({
      actor_user_id: user.id,
      organization_id: organizationId,
      account_id: accountId,
      job_id: jobId,
      event_type: 'enrichment_run_completed',
      job_type: jobType,
      provider: finalProvider,
      mock_mode: hasMockMode,
      before_state: beforeState,
      after_state: normalized
    });

    return jsonResponse({
      ok: true,
      job_id: jobId,
      run_id: runData?.id,
      status: finalStatus,
      mock_mode: hasMockMode,
      provider: finalProvider,
      model: normalized.model,
      prompt_version: normalized.prompt_version,
      tokens_used: tokensUsed,
      cost_estimate: costEstimate
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const failedAt = nowIso();

    await serviceClient
      .from('aicrm_ai_enrichment_jobs')
      .update({
        status: 'failed',
        completed_at: failedAt,
        error_message: errorMessage,
        output_payload: { error: errorMessage, provider: finalProvider, mock_mode: hasMockMode }
      })
      .eq('id', jobId);

    await serviceClient.from('aicrm_enrichment_runs').insert({
      organization_id: organizationId,
      account_id: accountId,
      enrichment_job_id: jobId,
      job_type: jobType,
      provider: finalProvider,
      status: 'failed',
      started_at: startedAt,
      completed_at: failedAt,
      input_payload: {
        account_id: accountId,
        requested_by: user.id,
        provider: finalProvider
      },
      error_message: errorMessage,
      mock_mode: hasMockMode
    });

    await writeAuditLog({
      actor_user_id: user.id,
      organization_id: organizationId,
      account_id: accountId,
      job_id: jobId,
      event_type: 'enrichment_run_failed',
      job_type: jobType,
      provider: finalProvider,
      mock_mode: hasMockMode,
      before_state: beforeState,
      after_state: { error: errorMessage }
    });

    return jsonResponse({ ok: false, error: errorMessage }, 500);
  }
});
