export function normalizeEmailAddress(value) {
  if (value === null || value === undefined) return null;
  const raw = String(value).trim();
  if (!raw) return null;
  const bracketMatch = raw.match(/<([^>]+)>/);
  const candidate = (bracketMatch?.[1] ?? raw).trim().toLowerCase();
  if (!candidate || !candidate.includes("@")) return null;
  return candidate;
}

export function renderTemplate(template, variables = {}) {
  if (template === null || template === undefined) return "";
  return String(template).replace(/\{\{\s*([\w.-]+)\s*\}\}/g, (_, key) => {
    const value = variables[key];
    if (value === null || value === undefined) return "";
    return String(value);
  });
}

export function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function buildOutreachTemplateContext({ account = null, contact = null, researchSummary = null } = {}) {
  const fullName = [contact?.first_name?.trim() || "", contact?.last_name?.trim() || ""].join(" ").trim();
  return {
    company_name: account?.company_name?.trim() || "",
    contact_first_name: contact?.first_name?.trim() || "",
    contact_full_name: contact?.full_name?.trim() || fullName || "",
    account_category: account?.category?.trim() || "",
    city: account?.city?.trim() || "",
    province: account?.province?.trim() || "",
    channel_product_fit: account?.channel_product_fit?.trim() || "",
    research_summary: researchSummary?.trim?.() || "",
    next_action: account?.next_action?.trim() || ""
  };
}

export function extractMessageEmails(message) {
  const recipients = Array.isArray(message?.recipients) ? message.recipients : [];
  const sender = message?.sender && typeof message.sender === "object" ? message.sender : {};
  return {
    senderEmail: normalizeEmailAddress(sender.email || sender.from || sender.address || null),
    recipientEmails: recipients
      .map((r) => normalizeEmailAddress(r?.email || r?.address || r?.to || null))
      .filter(Boolean)
  };
}

export function resolveStrongEmailAssociation({ existingMessage = null, contactMatches = [], accountMatches = [], reason = null } = {}) {
  if (existingMessage) return { association_type: "message", confidence: 100, reason: reason || "provider_message_match", existing_message: existingMessage };
  if (contactMatches.length === 1) return { association_type: "contact", confidence: 95, reason: reason || "exact_email_contact_match", contact: contactMatches[0], account: contactMatches[0]?.aicrm_accounts ?? null };
  if (accountMatches.length === 1 && contactMatches.length === 0) return { association_type: "account", confidence: 80, reason: reason || "exact_email_account_match", account: accountMatches[0] };
  return { association_type: "unassociated", confidence: 0, reason: reason || "ambiguous_or_missing_exact_match" };
}

export function buildEmailAuditMetadata(message, eventType, extra = {}) {
  return { source_system: "resend", event_type: eventType, subject: message?.subject ?? null, provider_message_id: message?.provider_message_id ?? null, provider_thread_id: message?.provider_thread_id ?? null, ...extra };
}
