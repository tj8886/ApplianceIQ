import {fetchLiveProducts,productEvidenceText} from '../_shared/live-pim-products.ts';
interface LivePimContext {
  matchedBrands: string[];
  text: string;
}

export async function fetchLivePimContext(admin: any, prompt: string): Promise<LivePimContext> {
  const lower = prompt.toLowerCase();

  const { data: brandRows, error: brandRowsError } = await admin
    .from("brand_catalog")
    .select("brand_name")
    .eq("is_active", true).limit(500);

  if(brandRowsError)throw new Error('scoped_catalog_context_failed');
  const allBrandNames: string[] = (brandRows ?? []).map((b: { brand_name: string }) => b.brand_name).filter(Boolean);

  const matched = allBrandNames
    .filter((name) => lower.includes(name.toLowerCase()))
    .sort((a, b) => b.length - a.length)
    .slice(0, 3);

  const products = await fetchLiveProducts(admin,prompt,matched);
  const sections: string[] = ["LIVE APPLIANCE MODEL EVIDENCE (source dates are observation dates; updated_at is an edit date):\n"+productEvidenceText(products)];

  for (const brand of matched) {
    const brandSections: string[] = [];

    const { data: contacts, error: contactsError } = await admin
      .from("aiq_vendor_contacts")
      .select("country,customer_service_phone,customer_service_phone_label,customer_service_hours,service_repair_phone,warranty_phone,trade_distributor_phone,support_email,service_portal_url,owner_account_portal_url,confidence_level,notes")
      .ilike("brand_name", brand).limit(100);

    if(contactsError)throw new Error('scoped_catalog_context_failed');
    for (const c of contacts ?? []) {
      const bits: string[] = [`Country: ${c.country}`];
      if (c.customer_service_phone) bits.push(`${c.customer_service_phone_label ?? "Customer Service"}: ${c.customer_service_phone}${c.customer_service_hours ? " (" + c.customer_service_hours + ")" : ""}`);
      if (c.service_repair_phone && c.service_repair_phone !== c.customer_service_phone) bits.push(`Service/Repair line: ${c.service_repair_phone}`);
      if (c.warranty_phone && c.warranty_phone !== c.customer_service_phone) bits.push(`Warranty line: ${c.warranty_phone}`);
      if (c.trade_distributor_phone) bits.push(`Trade/Distributor line: ${c.trade_distributor_phone}`);
      if (c.support_email) bits.push(`Email: ${c.support_email}`);
      if (c.service_portal_url) bits.push(`Book service online: ${c.service_portal_url}`);
      if (c.owner_account_portal_url) bits.push(`Owner account / warranty lookup: ${c.owner_account_portal_url}`);
      bits.push(`Confidence: ${c.confidence_level}${c.confidence_level !== "official" ? " (verify before relaying to a customer)" : ""}`);
      if (c.notes) bits.push(`Notes: ${c.notes}`);
      brandSections.push(`VENDOR CONTACT (${brand}):\n${bits.join(" | ")}`);
    }

    const { data: recalls, error: recallsError } = await admin
      .from("aiq_recalls")
      .select("title,hazard,recall_date,units_affected,injury_count,remedy,url,model_numbers")
      .ilike("brand_name", brand).limit(100);

    if(recallsError)throw new Error('scoped_catalog_context_failed');
    for (const r of recalls ?? []) {
      brandSections.push(
        `ACTIVE/HISTORICAL RECALL (${brand}): "${r.title}" (${r.recall_date ?? "date unknown"}). ` +
        `Hazard: ${r.hazard ?? "n/a"}. Affected models: ${(r.model_numbers ?? []).join(", ") || "see notice"}. ` +
        `Units: ${r.units_affected ?? "n/a"}, injuries reported: ${r.injury_count ?? "unknown"}. ` +
        `Remedy: ${r.remedy ?? "see official notice"}. Full notice: ${r.url ?? "n/a"}. ` +
        `IMPORTANT: if the customer's model number is in this list, tell them plainly and direct them to the remedy — do not downplay it.`
      );
    }

    const { data: warranties, error: warrantiesError } = await admin
      .from("aiq_warranty_policies")
      .select("category,full_coverage_years,full_coverage_notes,component_warranties,certified_install_bonus_notes,key_exclusions,last_verified_date")
      .ilike("brand_name", brand).limit(100);

    if(warrantiesError)throw new Error('scoped_catalog_context_failed');
    for (const w of warranties ?? []) {
      let compText = "";
      try {
        const comps = typeof w.component_warranties === "string" ? JSON.parse(w.component_warranties) : (w.component_warranties ?? []);
        if (Array.isArray(comps) && comps.length) {
          compText = " Extended component coverage: " + comps.map((c: Record<string, unknown>) =>
            `${c.component} — ${c.years} yr (${c.coverage_type})${c.notes ? ": " + c.notes : ""}`
          ).join("; ") + ".";
        }
      } catch { /* ignore malformed json */ }
      brandSections.push(
        `WARRANTY POLICY (${brand}, category: ${w.category}): ${w.full_coverage_years ?? "unknown"} year(s) full coverage. ` +
        `${w.full_coverage_notes ?? ""}${compText}` +
        `${w.certified_install_bonus_notes ? " Certified-install bonus: " + w.certified_install_bonus_notes : ""}` +
        `${w.key_exclusions ? " Key exclusions: " + w.key_exclusions : ""}` +
        ` (last verified ${w.last_verified_date ?? "unknown"})`
      );
    }

    if (brandSections.length) sections.push(brandSections.join("\n"));
  }

  if (sections.length === 0) {
    return { matchedBrands: matched, text: `No vendor contact, recall, or warranty records on file yet for: ${matched.join(", ")}. Do not fabricate a phone number or warranty term — tell the user to check Product IQ PIM directly or that this brand isn't in the directory yet.` };
  }

  return { matchedBrands: matched, text: sections.join("\n\n") };
}

export function buildSystemPrompt(args: {
  assistant: Record<string, unknown> | null;
  template: { system_prompt?: string; user_prompt_template?: string; tone_guidance?: string; output_schema?: unknown } | null;
  approvalRequired: boolean;
  knowledge: Array<{ title?: string; content?: string; citation?: unknown; chunk_key?: string; score: number }>;
  groundedContext: unknown;
  livePimData: LivePimContext;
}): string {
  const a = args.assistant ?? {};
  const parts: string[] = [];

  parts.push(`You are the ${a["label"] ?? "AI Assistant"}, part of the Appliance IQ CRM AI platform for appliance and specialty retail.`);
  if (a["description"]) parts.push(String(a["description"]));

  const methodology = (a["config"] as Record<string, unknown> | null)?.["methodology"];

  parts.push([
    "GOVERNANCE RULES (non-negotiable):",
    "- You are advisory only. You never execute actions, modify records, send messages, or commit anyone to anything.",
    args.approvalRequired
      ? "- Consequential recommendations are routed to the human approval queue. State clearly that they await human approval."
      : "- This assistant is configured for advisory analysis only.",
    "- Ground answers in the provided tenant context and knowledge base. Never fabricate prices, specs, stock positions, review scores, or records — if the context does not contain it, say so plainly.",
    "- For appliance model descriptions, dimensions, specs, warranty terms, vendor contacts and recalls: the LIVE PRODUCT IQ PIM DATA section below is the current stored evidence — it is fetched fresh from the PIM on every request. If it conflicts with anything in the static knowledge base, the live PIM data wins. If a brand isn't covered in the live data, say so plainly and suggest checking Product IQ PIM directly rather than guessing.",
    "- Stored evidence is not proof of a fresh external check. Never describe old or undated pricing as current, and never use historical chat or static course text to override live model evidence. Preserve market boundaries; ask which market when model records differ.",
    "- Respect tenant scope: never reference or infer data from other organizations.",
    "- Brand voice: verified over hyped. The price is real — we checked. Evidence before claims; honest trade-offs build trust.",
    methodology
      ? `- House methodology for this assistant: ${JSON.stringify(methodology)}`
      : "- Default standards: evidence-first spec-by-spec selling; ACRA objection handling (Acknowledge, Clarify, Respond, Advance).",
  ].join("\n"));

  if (args.template?.system_prompt) parts.push(`TEMPLATE INSTRUCTIONS:\n${args.template.system_prompt}`);
  if (args.template?.tone_guidance) parts.push(`TONE:\n${args.template.tone_guidance}`);
  if (args.template?.output_schema) parts.push(`OUTPUT SCHEMA (follow strictly):\n${JSON.stringify(args.template.output_schema)}`);

  const rc = a["response_contract"];
  if (rc && Object.keys(rc as object).length > 0) parts.push(`RESPONSE CONTRACT:\n${JSON.stringify(rc)}`);
  const sc = a["safety_controls"];
  if (sc && Object.keys(sc as object).length > 0) parts.push(`SAFETY CONTROLS IN EFFECT:\n${JSON.stringify(sc)}`);

  if (args.livePimData.text) {
    parts.push(`LIVE PRODUCT IQ PIM DATA (fetched fresh this request — stored appliance evidence with source dates):\n${args.livePimData.text}`);
  }

  const relevant = args.knowledge.filter((c) => c.score > 0);
  if (relevant.length > 0) {
    parts.push("STATIC KNOWLEDGE BASE — sales technique / playbook content (cite by [chunk_key] when used):\n" +
      relevant.map((c) => `[${c.chunk_key}] ${c.title ?? ""}\n${(c.content ?? "").slice(0, 2000)}`).join("\n---\n"));
  }

  if (args.groundedContext) {
    parts.push(`TENANT CONTEXT SNAPSHOT (permission-checked record counts):\n${JSON.stringify(args.groundedContext).slice(0, 4000)}`);
  }

  return parts.join("\n\n");
}

