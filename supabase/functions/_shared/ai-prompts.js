const PLACEHOLDER_PATTERN = /\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g;

function coerceString(value) { return value == null ? "" : String(value); }
function coerceJsonText(value) {
  if (typeof value === "string") return value;
  if (value == null) return "";
  try { return JSON.stringify(value, null, 2); } catch { return ""; }
}
function isTruthy(value) { return value !== null && value !== undefined && value !== ""; }

export function normalizeAiPromptTemplate(row) {
  if (!row || typeof row !== "object") return null;
  const normalized = {
    id: coerceString(row.id),
    organization_id: row.organization_id == null ? null : coerceString(row.organization_id),
    prompt_key: coerceString(row.prompt_key || row.template_key).trim(),
    prompt_version: coerceString(row.prompt_version || row.version || "").trim(),
    application: coerceString(row.application || "shared").trim() || "shared",
    use_case: coerceString(row.use_case || row.tool_type).trim(),
    status: coerceString(row.status || "active").trim() || "active",
    priority: Number.isFinite(Number(row.priority)) ? Number(row.priority) : 100,
    tone_guidance: coerceString(row.tone_guidance || "Direct, composed, professional, non-hype.").trim() || "Direct, composed, professional, non-hype.",
    system_prompt: coerceString(row.system_prompt).trim(),
    user_prompt_template: coerceString(row.user_prompt_template).trim(),
    variables: Array.isArray(row.variables) ? row.variables.map((i) => coerceString(i)).filter(Boolean) : [],
    output_schema: row.output_schema && typeof row.output_schema === "object" ? row.output_schema : {},
    version: Number.isFinite(Number(row.version)) ? Number(row.version) : 1,
    version_history: Array.isArray(row.version_history) ? row.version_history : [],
    source_system: coerceString(row.source_system || "applianceiq").trim() || "applianceiq",
    created_at: row.created_at ? coerceString(row.created_at) : null,
    updated_at: row.updated_at ? coerceString(row.updated_at) : null
  };
  if (!normalized.prompt_key || !normalized.prompt_version || !normalized.use_case) return null;
  return normalized;
}

export function selectAiPromptTemplate(rows, options = {}) {
  const normalizedRows = (Array.isArray(rows) ? rows : []).map(normalizeAiPromptTemplate).filter(Boolean).filter((r) => r.status === "active");
  if (!normalizedRows.length) return null;
  const promptKey = coerceString(options.promptKey).trim();
  const promptVersion = coerceString(options.promptVersion).trim();
  const application = coerceString(options.application || "shared").trim() || "shared";
  const useCase = coerceString(options.useCase).trim();
  const organizationId = options.organizationId ? coerceString(options.organizationId) : null;
  const candidates = normalizedRows.filter((r) => {
    if (promptKey && r.prompt_key !== promptKey) return false;
    if (useCase && r.use_case !== useCase) return false;
    if (application && r.application !== application && r.application !== "shared") return false;
    return true;
  });
  if (!candidates.length) return null;
  const exactVersionCandidates = promptVersion ? candidates.filter((r) => r.prompt_version === promptVersion) : candidates;
  const scored = (exactVersionCandidates.length ? exactVersionCandidates : candidates).map((row) => ({
    row,
    score: (organizationId && row.organization_id === organizationId ? 1000 : 0) + (row.organization_id == null ? 100 : 0) + (row.application === application ? 25 : row.application === "shared" ? 10 : 0) + (promptVersion && row.prompt_version === promptVersion ? 50 : 0) + row.priority + (row.version || 0)
  }));
  scored.sort((a, b) => { if (b.score !== a.score) return b.score - a.score; if (b.row.version !== a.row.version) return b.row.version - a.row.version; return b.row.prompt_version.localeCompare(a.row.prompt_version); });
  return scored[0]?.row || null;
}

export function renderAiPromptTemplate(template, variables = {}, fallbackPrompt = "") {
  if (!template) return fallbackPrompt;
  const context = { ...variables, context_json: coerceJsonText(variables.context_json ?? variables.context ?? variables.prompt_json ?? variables), prompt_json: coerceJsonText(variables.prompt_json ?? variables.context_json ?? variables.context ?? variables), organization_name: coerceString(variables.organization_name), account_name: coerceString(variables.account_name), job_type: coerceString(variables.job_type), prompt_version: coerceString(variables.prompt_version), subject: coerceString(variables.subject) };
  const replace = (v) => coerceString(v).replace(PLACEHOLDER_PATTERN, (_, key) => { const r = context[key]; return isTruthy(r) ? coerceString(r) : ""; });
  const systemPrompt = replace(template.system_prompt || "");
  const toneGuidance = replace(template.tone_guidance || "");
  const userPrompt = replace(template.user_prompt_template || "");
  return [systemPrompt, toneGuidance ? `Tone guidance: ${toneGuidance}` : "", userPrompt].map((s) => s.trim()).filter(Boolean).join("\n\n").trim() || fallbackPrompt;
}

export function composeAiPrompt(template, variables = {}, fallbackPrompt = "") {
  if (!template) return fallbackPrompt;
  return renderAiPromptTemplate(template, variables, fallbackPrompt) || fallbackPrompt;
}
