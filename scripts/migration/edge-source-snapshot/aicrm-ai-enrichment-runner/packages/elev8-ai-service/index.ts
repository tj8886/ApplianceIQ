export type AiProvider = "anthropic" | "mock" | "unconfigured";

export type AiContextRecord = {
  type?: string | null;
  id?: string | null;
  label?: string | null;
};

export type AiRelationshipContext = {
  type: string;
  target?: string | null;
  label?: string | null;
  strength?: number | null;
  confidence?: number | null;
};

export type AiKnowledgeGraphContext = {
  nodes?: number | null;
  edges?: number | null;
  summary?: string | null;
};

export type AiSharedContext = {
  organizationId?: string | null;
  organizationName?: string | null;
  businessUnitId?: string | null;
  businessUnitName?: string | null;
  role?: string | null;
  currentModule?: string | null;
  currentRecord?: AiContextRecord | null;
  products?: Array<Record<string, unknown>> | null;
  relationships?: AiRelationshipContext[] | null;
  knowledgeGraph?: AiKnowledgeGraphContext | null;
  preferences?: Record<string, unknown> | null;
  metadata?: Record<string, unknown> | null;
};

export type AiPromptDefinition = {
  promptName: string;
  promptVersion: string;
  application: string;
  useCase: string;
  variables: string[];
  outputSchema: Record<string, unknown>;
  versionHistory: Array<{ version: string; changes: string }>;
  promptTemplate: string;
  active: boolean;
};

export type AiRequest = {
  application?: string;
  useCase?: string;
  subject: string;
  tone?: "executive" | "analyst" | "brief" | "direct";
  context?: AiSharedContext;
  promptName?: string;
  promptVersion?: string;
  variables?: Record<string, unknown>;
  provider?: Exclude<AiProvider, "unconfigured">;
  model?: string;
  maxTokens?: number;
  timeoutMs?: number;
  retryCount?: number;
};

export type AiResponse = {
  provider: AiProvider;
  model: string;
  promptName: string;
  promptVersion: string;
  prompt: string;
  text: string;
  summary: string;
  usage: { inputTokens: number; outputTokens: number; totalTokens: number };
  latencyMs: number;
  costEstimate: number;
  cacheHit: boolean;
  context: AiSharedContext;
};

export type AnthropicMessageRequest = {
  prompt: string;
  apiKey?: string;
  model?: string;
  maxTokens?: number;
  temperature?: number;
  timeoutMs?: number;
  retryCount?: number;
};

export type AnthropicMessageResponse = {
  provider: AiProvider;
  model: string;
  text: string;
  usage: { inputTokens: number; outputTokens: number; totalTokens: number };
  latencyMs: number;
  costEstimate: number;
  cacheHit: boolean;
};

export type AiToolDefinition = {
  toolKey: string;
  name: string;
  application: string;
  useCase: string;
  description: string;
  inputSchema: Record<string, unknown>;
  outputSchema: Record<string, unknown>;
  active: boolean;
  version: string;
};

const DEFAULT_INSIGHT_PROMPT: AiPromptDefinition = {
  promptName: "unified_insight_brief",
  promptVersion: "2026-07-18.v1",
  application: "shared",
  useCase: "executive_brief",
  variables: ["subject", "tone", "context"],
  outputSchema: {
    summary: "string",
    signals: ["string"],
    risks: ["string"],
    recommendedNextSteps: ["string"]
  },
  versionHistory: [{ version: "2026-07-18.v1", changes: "Initial Elev8 unified AI prompt." }],
  promptTemplate: [
    "You are the Elev8 Unified AI Operating System.",
    "Use direct, structured, executive language. Avoid hype and unsupported claims.",
    "Organize the response as concise findings with practical next actions.",
    "Provide clear reasoning, context-sensitive recommendations, and measurable signals.",
    "Return a short, useful answer that can power dashboards and workflow automation."
  ].join("\n"),
  active: true
};

export const DEFAULT_PROMPT_LIBRARY: AiPromptDefinition[] = [
  DEFAULT_INSIGHT_PROMPT,
  {
    promptName: "account_intelligence",
    promptVersion: "2026-07-18.v1",
    application: "elev8-aicrm",
    useCase: "account_intelligence",
    variables: ["subject", "tone", "context"],
    outputSchema: { summary: "string", buyingSignals: ["string"], recommendedActions: ["string"] },
    versionHistory: [{ version: "2026-07-18.v1", changes: "ApplianceIQ / Channel Intelligence account intelligence baseline." }],
    promptTemplate: "Summarize the account, identify buying signals, and recommend the next best action.",
    active: true
  },
  {
    promptName: "product_brief",
    promptVersion: "2026-07-18.v1",
    application: "applianceiq",
    useCase: "product_brief",
    variables: ["subject", "tone", "context"],
    outputSchema: { summary: "string", advantages: ["string"], objections: ["string"] },
    versionHistory: [{ version: "2026-07-18.v1", changes: "ApplianceIQ product expert baseline." }],
    promptTemplate: "Summarize the product, ideal customer, competitive position, and cross-sell opportunities.",
    active: true
  },
  {
    promptName: "relationship_insight",
    promptVersion: "2026-07-18.v1",
    application: "shared",
    useCase: "relationship_insight",
    variables: ["subject", "tone", "context"],
    outputSchema: { summary: "string", introductions: ["string"], influence: ["string"] },
    versionHistory: [{ version: "2026-07-18.v1", changes: "Relationship intelligence baseline." }],
    promptTemplate: "Analyze people, companies, and warm introduction paths.",
    active: true
  },
  {
    promptName: "market_brief",
    promptVersion: "2026-07-18.v1",
    application: "shared",
    useCase: "market_brief",
    variables: ["subject", "tone", "context"],
    outputSchema: { summary: "string", marketChanges: ["string"], opportunities: ["string"] },
    versionHistory: [{ version: "2026-07-18.v1", changes: "Market intelligence baseline." }],
    promptTemplate: "Summarize market changes and discovery opportunities.",
    active: true
  },
  {
    promptName: "forecast_brief",
    promptVersion: "2026-07-18.v1",
    application: "shared",
    useCase: "forecast_brief",
    variables: ["subject", "tone", "context"],
    outputSchema: { summary: "string", risks: ["string"], upside: ["string"] },
    versionHistory: [{ version: "2026-07-18.v1", changes: "Forecast intelligence baseline." }],
    promptTemplate: "Summarize forecast drivers, risks, and upside opportunities.",
    active: true
  },
  {
    promptName: "execution_coach",
    promptVersion: "2026-07-18.v1",
    application: "shared",
    useCase: "execution_coach",
    variables: ["subject", "tone", "context"],
    outputSchema: { summary: "string", nextSteps: ["string"], objections: ["string"] },
    versionHistory: [{ version: "2026-07-18.v1", changes: "Execution intelligence baseline." }],
    promptTemplate: "Coach the user on what to do next with practical actions.",
    active: true
  },
  {
    promptName: "cross_application_search",
    promptVersion: "2026-07-18.v1",
    application: "shared",
    useCase: "cross_application_search",
    variables: ["subject", "tone", "context"],
    outputSchema: { summary: "string", results: ["string"], followUpQuestions: ["string"] },
    versionHistory: [{ version: "2026-07-18.v1", changes: "Cross-application retrieval baseline." }],
    promptTemplate: "Search across apps, knowledge graph, and records to answer the question.",
    active: true
  }
];

export const DEFAULT_TOOL_REGISTRY: AiToolDefinition[] = [
  {
    toolKey: "crm",
    name: "CRM",
    application: "elev8-aicrm",
    useCase: "crm",
    description: "Access accounts, contacts, opportunities, tasks, notes, outreach, and AI intelligence.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "knowledge_graph",
    name: "Knowledge Graph",
    application: "shared",
    useCase: "knowledge_graph",
    description: "Traverse companies, people, products, projects, territories, and relationships.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "forecasting",
    name: "Forecasting",
    application: "shared",
    useCase: "forecasting",
    description: "Read revenue, pipeline, territory, channel, and product forecasts.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "relationship_search",
    name: "Relationship Search",
    application: "shared",
    useCase: "relationship_search",
    description: "Find warm introductions, people, employers, and influence paths.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "product_search",
    name: "Product Search",
    application: "applianceiq",
    useCase: "product_search",
    description: "Search products, specifications, documents, training, and comparisons.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "training",
    name: "Training",
    application: "applianceiq",
    useCase: "training",
    description: "Look up product training, certification, tips, FAQs, and troubleshooting.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "market_intelligence",
    name: "Market Intelligence",
    application: "shared",
    useCase: "market_intelligence",
    description: "Summarize discovery, market events, and research refresh opportunities.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "graph_search",
    name: "Graph Search",
    application: "shared",
    useCase: "graph_search",
    description: "Search the industry knowledge graph across the ecosystem.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  },
  {
    toolKey: "execution_engine",
    name: "Execution Engine",
    application: "shared",
    useCase: "execution_engine",
    description: "Prioritize daily actions, meetings, opportunities, and next steps.",
    inputSchema: { type: "object" },
    outputSchema: { type: "object" },
    active: true,
    version: "2026-07-18.v1"
  }
];

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getEnv(name: string): string | undefined {
  const globalAny = globalThis as typeof globalThis & { process?: { env?: Record<string, string | undefined> }; Deno?: { env?: { get(key: string): string | undefined } } };
  return globalAny.Deno?.env?.get(name) || globalAny.process?.env?.[name];
}

function compact(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string") return value.trim();
  if (Array.isArray(value)) return value.map((item) => compact(item)).filter(Boolean).join(", ");
  if (isObject(value)) return Object.entries(value).map(([key, item]) => `${key}: ${compact(item)}`).filter(Boolean).join("; ");
  return String(value);
}

function buildContextSummary(context: AiSharedContext | undefined): AiSharedContext {
  if (!context) return {};
  return {
    organizationId: context.organizationId ?? null,
    organizationName: context.organizationName ?? null,
    businessUnitId: context.businessUnitId ?? null,
    businessUnitName: context.businessUnitName ?? null,
    role: context.role ?? null,
    currentModule: context.currentModule ?? null,
    currentRecord: context.currentRecord ?? null,
    products: context.products ?? [],
    relationships: context.relationships ?? [],
    knowledgeGraph: context.knowledgeGraph ?? null,
    preferences: context.preferences ?? {},
    metadata: context.metadata ?? {}
  };
}

export function buildInsightPrompt(request: AiRequest) {
  const prompt = resolvePromptDefinition(request);
  const context = buildContextSummary(request.context);
  const variables = request.variables ?? {};

  return [
    prompt.promptTemplate,
    `Application: ${request.application}`,
    `Use case: ${prompt.useCase}`,
    `Tone: ${request.tone || "executive"}`,
    `Subject: ${request.subject}`,
    `Prompt version: ${prompt.promptVersion}`,
    "Context JSON:",
    JSON.stringify(context, null, 2),
    "Variables JSON:",
    JSON.stringify(variables, null, 2),
    "Output schema:",
    JSON.stringify(prompt.outputSchema, null, 2),
    "Return a concise, structured response with practical next actions."
  ].join("\n");
}

export function resolvePromptDefinition(request: Pick<AiRequest, "application" | "useCase" | "promptName" | "promptVersion">): AiPromptDefinition {
  const promptName = request.promptName?.trim();
  const promptVersion = request.promptVersion?.trim();
  const byName = promptName ? DEFAULT_PROMPT_LIBRARY.find((entry) => entry.promptName === promptName && (!promptVersion || entry.promptVersion === promptVersion)) : undefined;
  const byUseCase = DEFAULT_PROMPT_LIBRARY.find((entry) => entry.application === (request.application || "shared") && entry.useCase === (request.useCase || "executive_brief"));
  return byName || byUseCase || DEFAULT_INSIGHT_PROMPT;
}

export function buildSharedContext(context: AiSharedContext | Record<string, unknown> | null | undefined): AiSharedContext {
  if (!context || !isObject(context)) return {};
  const source = context as Record<string, unknown>;
  const organization = isObject(source.organization) ? source.organization : {};
  const businessUnit = isObject(source.businessUnit) ? source.businessUnit : {};
  return {
    organizationId: (source.organizationId as string | undefined) ?? (organization.id as string | undefined) ?? null,
    organizationName: (source.organizationName as string | undefined) ?? (organization.name as string | undefined) ?? null,
    businessUnitId: (source.businessUnitId as string | undefined) ?? (businessUnit.id as string | undefined) ?? null,
    businessUnitName: (source.businessUnitName as string | undefined) ?? (businessUnit.name as string | undefined) ?? null,
    role: (source.role as string | undefined) ?? null,
    currentModule: (source.currentModule as string | undefined) ?? (source.module as string | undefined) ?? null,
    currentRecord: isObject(source.currentRecord) ? {
      type: (source.currentRecord.type as string | undefined) ?? null,
      id: (source.currentRecord.id as string | undefined) ?? null,
      label: (source.currentRecord.label as string | undefined) ?? null
    } : null,
    products: Array.isArray(source.products) ? source.products as Array<Record<string, unknown>> : [],
    relationships: Array.isArray(source.relationships) ? source.relationships as AiRelationshipContext[] : [],
    knowledgeGraph: isObject(source.knowledgeGraph) ? {
      nodes: (source.knowledgeGraph.nodes as number | undefined) ?? null,
      edges: (source.knowledgeGraph.edges as number | undefined) ?? null,
      summary: (source.knowledgeGraph.summary as string | undefined) ?? null
    } : null,
    preferences: isObject(source.preferences) ? source.preferences : {},
    metadata: isObject(source.metadata) ? source.metadata : {}
  };
}

export function estimateCost(inputTokens: number, outputTokens: number, inputCostPerMillion = 0, outputCostPerMillion = 0) {
  return (inputTokens / 1_000_000) * inputCostPerMillion + (outputTokens / 1_000_000) * outputCostPerMillion;
}

function countTokens(text: string) {
  return Math.max(1, Math.ceil(text.trim().split(/\s+/).length * 1.3));
}

function buildMockText(prompt: string, context: AiSharedContext, request?: AiRequest) {
  const subject = request?.subject || "the requested subject";
  const record = context.currentRecord?.label || context.currentRecord?.type || "the current record";
  return [
    `Mock AI response for ${subject}.`,
    `Context: ${context.organizationName || context.organizationId || "unknown organization"}, ${request?.application || "shared"}, ${request?.useCase || "general"}.`,
    `Record: ${record}.`,
    `Key prompt cues: ${prompt.slice(0, 140).replace(/\s+/g, " ")}${prompt.length > 140 ? "…" : ""}`,
    `Recommended next step: review the structured data, then execute the next best action.`
  ].join(" ");
}

export async function callAnthropicMessages(request: AnthropicMessageRequest): Promise<AnthropicMessageResponse> {
  const apiKey = request.apiKey || getEnv("ANTHROPIC_API_KEY");
  const model = request.model || getEnv("ANTHROPIC_MODEL") || "claude-3-5-sonnet-latest";
  const maxTokens = request.maxTokens ?? Number(getEnv("ANTHROPIC_MAX_TOKENS") || "2400");
  const timeoutMs = request.timeoutMs ?? Number(getEnv("ANTHROPIC_TIMEOUT_MS") || "30000");
  const retryCount = request.retryCount ?? Number(getEnv("ANTHROPIC_RETRY_COUNT") || "2");
  const start = Date.now();

  if (!apiKey) {
    const text = buildMockText(request.prompt, {}, undefined);
    return {
      provider: "mock",
      model: "mock-deterministic",
      text,
      usage: { inputTokens: countTokens(request.prompt), outputTokens: countTokens(text), totalTokens: countTokens(request.prompt) + countTokens(text) },
      latencyMs: Date.now() - start,
      costEstimate: 0,
      cacheHit: false
    };
  }

  let lastError: unknown;
  for (let attempt = 0; attempt <= retryCount; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model,
          max_tokens: maxTokens,
          temperature: request.temperature ?? 0.2,
          messages: [{ role: "user", content: request.prompt }]
        }),
        signal: controller.signal
      });

      if (!response.ok) {
        const message = await response.text().catch(() => "");
        throw new Error(message ? `Anthropic request failed (${response.status}): ${message}` : `Anthropic request failed (${response.status}).`);
      }

      const data = await response.json() as { content?: Array<{ text?: string }>; usage?: { input_tokens?: number; output_tokens?: number } };
      const text = data.content?.[0]?.text || "No insight returned.";
      const inputTokens = data.usage?.input_tokens || countTokens(request.prompt);
      const outputTokens = data.usage?.output_tokens || countTokens(text);
      clearTimeout(timeout);
      return {
        provider: "anthropic",
        model,
        text,
        usage: { inputTokens, outputTokens, totalTokens: inputTokens + outputTokens },
        latencyMs: Date.now() - start,
        costEstimate: estimateCost(inputTokens, outputTokens),
        cacheHit: false
      };
    } catch (error) {
      clearTimeout(timeout);
      lastError = error;
      if (attempt >= retryCount) break;
      await new Promise((resolve) => setTimeout(resolve, 250 * (attempt + 1)));
    }
  }

  const fallbackText = buildMockText(request.prompt, {}, undefined);
  return {
    provider: "mock",
    model: "mock-deterministic",
    text: fallbackText,
    usage: { inputTokens: countTokens(request.prompt), outputTokens: countTokens(fallbackText), totalTokens: countTokens(request.prompt) + countTokens(fallbackText) },
    latencyMs: Date.now() - start,
    costEstimate: 0,
    cacheHit: false
  };
}

export function createElev8AiService(defaults: Partial<Pick<AiRequest, "application" | "useCase" | "promptName" | "promptVersion" | "provider" | "model" | "maxTokens" | "timeoutMs" | "retryCount">> = {}) {
  return {
    promptLibrary: DEFAULT_PROMPT_LIBRARY,
    toolRegistry: DEFAULT_TOOL_REGISTRY,
    buildPrompt(request: AiRequest) {
      return buildInsightPrompt({
        application: defaults.application || request.application,
        useCase: defaults.useCase || request.useCase,
        promptName: defaults.promptName || request.promptName,
        promptVersion: defaults.promptVersion || request.promptVersion,
        subject: request.subject,
        tone: request.tone,
        context: request.context,
        variables: request.variables,
        provider: request.provider,
        model: request.model,
        maxTokens: request.maxTokens,
        timeoutMs: request.timeoutMs,
        retryCount: request.retryCount
      });
    },
    async generateInsight(request: AiRequest): Promise<AiResponse> {
      const promptDefinition = resolvePromptDefinition({
        application: defaults.application || request.application,
        useCase: defaults.useCase || request.useCase,
        promptName: defaults.promptName || request.promptName,
        promptVersion: defaults.promptVersion || request.promptVersion
      });
      const prompt = buildInsightPrompt({
        application: defaults.application || request.application,
        useCase: defaults.useCase || request.useCase,
        promptName: promptDefinition.promptName,
        promptVersion: promptDefinition.promptVersion,
        subject: request.subject,
        tone: request.tone,
        context: request.context,
        variables: request.variables,
        provider: defaults.provider || request.provider,
        model: defaults.model || request.model,
        maxTokens: defaults.maxTokens || request.maxTokens,
        timeoutMs: defaults.timeoutMs || request.timeoutMs,
        retryCount: defaults.retryCount || request.retryCount
      });
      const response = await callAnthropicMessages({
        prompt,
        apiKey: getEnv("ANTHROPIC_API_KEY"),
        model: defaults.model || request.model,
        maxTokens: defaults.maxTokens || request.maxTokens,
        timeoutMs: defaults.timeoutMs || request.timeoutMs,
        retryCount: defaults.retryCount || request.retryCount
      });
      return {
        provider: response.provider,
        model: response.model,
        promptName: promptDefinition.promptName,
        promptVersion: promptDefinition.promptVersion,
        prompt,
        text: response.text,
        summary: response.text,
        usage: response.usage,
        latencyMs: response.latencyMs,
        costEstimate: response.costEstimate,
        cacheHit: response.cacheHit,
        context: buildSharedContext(request.context)
      };
    }
  };
}

export function createAiServiceCallRecord(input: {
  organizationId?: string | null;
  businessUnitId?: string | null;
  userId?: string | null;
  application: string;
  moduleName?: string | null;
  recordType?: string | null;
  recordId?: string | null;
  promptName?: string | null;
  promptVersion?: string | null;
  provider: AiProvider | string;
  model: string;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  costEstimate: number;
  cacheHit: boolean;
  success: boolean;
  errorMessage?: string | null;
  recommendationAccuracy?: number | null;
  context?: Record<string, unknown> | null;
  requestPayload?: Record<string, unknown> | null;
  responsePayload?: Record<string, unknown> | null;
}) {
  return {
    organization_id: input.organizationId ?? null,
    business_unit_id: input.businessUnitId ?? null,
    user_id: input.userId ?? null,
    application: input.application,
    module_name: input.moduleName ?? null,
    record_type: input.recordType ?? null,
    record_id: input.recordId ?? null,
    prompt_name: input.promptName ?? null,
    prompt_version: input.promptVersion ?? null,
    provider: input.provider,
    model: input.model,
    latency_ms: input.latencyMs,
    input_tokens: input.inputTokens,
    output_tokens: input.outputTokens,
    total_tokens: input.totalTokens,
    cost_estimate: input.costEstimate,
    cache_hit: input.cacheHit,
    success: input.success,
    error_message: input.errorMessage ?? null,
    recommendation_accuracy: input.recommendationAccuracy ?? null,
    context_json: input.context ?? {},
    request_payload: input.requestPayload ?? {},
    response_payload: input.responsePayload ?? {},
    created_at: new Date().toISOString()
  };
}

export function createAiMemoryRecord(input: {
  organizationId: string;
  businessUnitId?: string | null;
  userId?: string | null;
  memoryType: "conversation" | "recommendation" | "learning" | "prompt" | "user_preference" | "organization_preference";
  application: string;
  moduleName?: string | null;
  recordType?: string | null;
  recordId?: string | null;
  title: string;
  summary?: string | null;
  content?: Record<string, unknown> | null;
  metadata?: Record<string, unknown> | null;
}) {
  return {
    organization_id: input.organizationId,
    business_unit_id: input.businessUnitId ?? null,
    user_id: input.userId ?? null,
    memory_type: input.memoryType,
    application: input.application,
    module_name: input.moduleName ?? null,
    record_type: input.recordType ?? null,
    record_id: input.recordId ?? null,
    title: input.title,
    summary: input.summary ?? null,
    content_json: input.content ?? {},
    metadata_json: input.metadata ?? {},
    vector_ready: false,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };
}

export function createAiToolRunRecord(input: {
  organizationId: string;
  businessUnitId?: string | null;
  userId?: string | null;
  toolKey: string;
  application: string;
  inputPayload?: Record<string, unknown> | null;
  outputPayload?: Record<string, unknown> | null;
  status: "queued" | "running" | "completed" | "failed" | "cancelled";
  errorMessage?: string | null;
  latencyMs?: number | null;
}) {
  return {
    organization_id: input.organizationId,
    business_unit_id: input.businessUnitId ?? null,
    user_id: input.userId ?? null,
    tool_key: input.toolKey,
    application: input.application,
    input_payload: input.inputPayload ?? {},
    output_payload: input.outputPayload ?? {},
    status: input.status,
    error_message: input.errorMessage ?? null,
    latency_ms: input.latencyMs ?? null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  };
}
