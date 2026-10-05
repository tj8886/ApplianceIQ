// ai-roleplay v4 — adds Service IQ scenarios for customer service training.
// v3: persona-aware roleplay, handoff coaching, live PIM data grounding.
// v4: adds 8 service-focused scenario types (de_escalation, complaint_handling,
//     warranty_call, return_exchange, difficult_news, phone_etiquette,
//     post_sale_followup, review_response) with rich customer personas.
//     Service scenarios auto-suggest Katrina as coach. All 13 Service IQ
//     chapters (125-137) now loadable as knowledge context.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = Deno.env.get("AI_MODEL") ?? "claude-sonnet-4-6";
const MAX_MATCHED_BRANDS = 3;

// deno-lint-ignore no-explicit-any
type SB = any;

// Service scenarios default to Katrina
const SERVICE_SCENARIOS = new Set([
  "service_issue", "de_escalation", "complaint_handling", "warranty_call",
  "return_exchange", "difficult_news", "phone_etiquette", "post_sale_followup",
  "review_response"
]);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const sb = createClient(url, anonKey, { global: { headers: { authorization: auth } } });
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  // deno-lint-ignore no-explicit-any
  const body = await req.json() as any;
  const { session_id, action, rep_message, persona_name } = body;

  const { data: { user }, error: userErr } = await sb.auth.getUser();
  if (userErr || !user) return json({ error: "auth_failed" }, 401);

  // ---------- START ----------
  if (action === "start") {
    const { scenario_type, organization_id } = body;
    if (!scenario_type || !organization_id) return json({ error: "scenario_type_and_organization_id_required" }, 400);

    const { data: member } = await sb.from("organization_members").select("id").eq("organization_id", organization_id).maybeSingle();
    if (!member) return json({ error: "not_a_member" }, 403);

    // For service scenarios, suggest Katrina unless user picked someone else
    const effectivePersona = persona_name ?? (SERVICE_SCENARIOS.has(scenario_type) ? "Katrina" : "TJ");
    const persona = await loadPersona(admin, organization_id, effectivePersona);
    const knowledge = await loadKnowledge(admin, organization_id, scenario_type);
    const serviceKnowledge = SERVICE_SCENARIOS.has(scenario_type) ? await loadServiceIQChapters(admin, scenario_type) : "";
    const livePimData = await fetchLivePimContext(admin, scenario_type);

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (!anthropicKey) return json({ error: "anthropic_key_not_configured" }, 503);

    const combinedKnowledge = [knowledge, serviceKnowledge].filter(Boolean).join("\n\n");
    const openingSystem = buildCustomerSystem(scenario_type, combinedKnowledge, livePimData.text);
    const openingResp = await callClaude(anthropicKey, MODEL, openingSystem, `Start a ${scenario_type.replace(/_/g, " ")} scenario. Say your opening line as the customer. 1-3 sentences, conversational, realistic.`);
    const customerOpening = typeof openingResp === "string" ? openingResp : "Hi, I need some help.";

    const transcript = [{ role: "customer", content: customerOpening, timestamp: new Date().toISOString() }];

    const { data: sess, error: sessErr } = await admin.from("ai_roleplay_sessions").insert({
      organization_id,
      user_id: user.id,
      scenario_type,
      transcript,
      kpi_scores: {},
      status: "active",
    }).select("id").single();
    if (sessErr || !sess) return json({ error: "session_creation_failed", detail: sessErr?.message }, 500);

    return json({
      ok: true,
      session_id: sess.id,
      customer_response: customerOpening,
      coaching_persona: persona ? { name: persona.persona_name, emoji: persona.avatar_emoji, role: persona.persona_role } : null,
      suggested_coach: SERVICE_SCENARIOS.has(scenario_type) ? "Katrina" : "TJ",
    });
  }

  // ---------- MESSAGE ----------
  if (action === "message" && session_id) {
    if (!rep_message?.trim()) return json({ error: "rep_message_required" }, 400);

    const { data: sess, error: sessErr } = await sb.from("ai_roleplay_sessions").select("*").eq("id", session_id).single();
    if (sessErr || !sess) return json({ error: "session_not_found" }, 404);
    if (sess.status !== "active") return json({ error: "session_already_ended" }, 400);

    const orgId = sess.organization_id;
    const transcript = sess.transcript || [];
    transcript.push({ role: "rep", content: rep_message, timestamp: new Date().toISOString() });

    const knowledgeQuery = `${sess.scenario_type} ${rep_message}`;
    const [kpis, persona, protocols, knowledge] = await Promise.all([
      loadKpis(admin, orgId, sess.scenario_type),
      loadPersona(admin, orgId, persona_name ?? (SERVICE_SCENARIOS.has(sess.scenario_type) ? "Katrina" : "TJ")),
      loadProtocols(admin, orgId),
      loadKnowledge(admin, orgId, knowledgeQuery),
    ]);
    const serviceKnowledge = SERVICE_SCENARIOS.has(sess.scenario_type) ? await loadServiceIQChapters(admin, sess.scenario_type) : "";
    const livePimData = await fetchLivePimContext(admin, knowledgeQuery);
    const allPersonas = await loadAllPersonas(admin, orgId);

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (!anthropicKey) return json({ error: "anthropic_key_not_configured" }, 503);

    // deno-lint-ignore no-explicit-any
    const convMessages = transcript.map((t: any) => ({
      role: t.role === "rep" ? "user" : "assistant",
      content: t.content,
    }));

    const combinedKnowledge = [knowledge, serviceKnowledge].filter(Boolean).join("\n\n");
    const customerSystem = buildCustomerSystem(sess.scenario_type, combinedKnowledge, livePimData.text);
    const customerResp = await callClaude(anthropicKey, MODEL, customerSystem, null, convMessages);
    const customerText = typeof customerResp === "string" ? customerResp : "That's interesting, tell me more.";
    transcript.push({ role: "customer", content: customerText, timestamp: new Date().toISOString() });

    const coachingResult = await getPersonaCoaching(
      anthropicKey, rep_message, customerText, persona, allPersonas, protocols, kpis, transcript, combinedKnowledge, livePimData.text, sess.scenario_type
    );

    const mergedKpis = { ...(sess.kpi_scores || {}), ...(coachingResult.kpi_scores || {}) };
    await admin.from("ai_roleplay_sessions").update({
      total_turns: (sess.total_turns || 0) + 1,
      transcript,
      kpi_scores: mergedKpis,
    }).eq("id", session_id);

    return json({
      ok: true,
      customer_response: customerText,
      kpi_scores: coachingResult.kpi_scores,
      coaching_tip: coachingResult.coaching_tip,
      primary_coach: coachingResult.primary_coach,
      handoff_insight: coachingResult.handoff_insight,
      live_pim_brands_matched: livePimData.matchedBrands,
    });
  }

  // ---------- END ----------
  if (action === "end" && session_id) {
    const { data: sess } = await sb.from("ai_roleplay_sessions").select("kpi_scores, organization_id, transcript, scenario_type").eq("id", session_id).single();
    if (!sess) return json({ error: "session_not_found" }, 404);

    const kpiScores = sess.kpi_scores || {};
    const scores = Object.values(kpiScores).filter((v): v is number => typeof v === "number");
    const avgScore = scores.length ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;

    const persona = await loadPersona(admin, sess.organization_id, persona_name ?? (SERVICE_SCENARIOS.has(sess.scenario_type) ? "Katrina" : "TJ"));
    let finalFeedback = "";
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (anthropicKey && persona) {
      const isService = SERVICE_SCENARIOS.has(sess.scenario_type);
      const fbSystem = `${persona.prompt_prefix}\n\nGive a 2-3 sentence final coaching summary for a ${isService ? 'customer service' : 'sales'} roleplay that just ended. Scenario: ${sess.scenario_type.replace(/_/g, ' ')}. Overall score: ${avgScore.toFixed(1)}/10. KPI scores: ${JSON.stringify(kpiScores)}. Be encouraging but honest. Use your persona voice (${persona.tone}).${isService ? ' Focus feedback on empathy, de-escalation technique, accuracy of information given, and resolution quality.' : ''}`;
      const fbResp = await callClaude(anthropicKey, MODEL, fbSystem, "Give me the final coaching summary.");
      finalFeedback = typeof fbResp === "string" ? fbResp : "";
    }

    await admin.from("ai_roleplay_sessions").update({
      status: "completed",
      session_score: parseFloat(avgScore.toFixed(2)),
      feedback: finalFeedback,
      completed_at: new Date().toISOString(),
    }).eq("id", session_id);

    await admin.from("ai_audit_events").insert({
      organization_id: sess.organization_id,
      event_type: "crm.roleplay.completed",
      event_payload: { session_id, session_score: avgScore, kpi_scores: kpiScores, turns: (sess.transcript || []).length, scenario_type: sess.scenario_type },
    });

    return json({ ok: true, session_score: avgScore, feedback: finalFeedback, kpi_scores: kpiScores });
  }

  return json({ error: "invalid_action" }, 400);
});

// ---- Scenario Definitions ----

function buildCustomerSystem(scenarioType: string, knowledge: string, livePimData: string): string {
  const scenarios: Record<string, string> = {
    // --- Sales scenarios ---
    cold_call: "You are a homeowner who received a cold call about kitchen appliances. You're mildly interested but skeptical. Ask about pricing early. Be realistic.",
    follow_up: "You visited a store last week and looked at refrigerators but didn't buy. A sales rep is calling to follow up. You liked one model but thought it was expensive.",
    objection_handling: "You're interested in a dishwasher but think the price is too high and you saw a cheaper one at a competitor. Push back on price and features.",
    product_demo: "You're in a store looking at ranges. You cook a lot and care about reliability and BTU output. Ask detailed questions.",

    // --- Service IQ scenarios ---
    service_issue: "You own an appliance that's having a problem and you're frustrated. Describe a believable symptom (won't cool, won't drain, makes noise, etc.) for a real brand if one is provided in your knowledge context. You've already tried basic troubleshooting. Ask what the rep is going to do about it and whether it's covered under warranty.",

    de_escalation: "You are FURIOUS. Your brand new refrigerator was delivered yesterday with a massive dent on the front door, and when you called this morning someone put you on hold for 15 minutes and then hung up on you. You are now calling back. Start angry — raised voice energy, short sentences, demanding. You want this fixed TODAY. If the rep stays calm, listens, and shows genuine empathy, you will gradually calm down. If they get defensive, interrupt you, or blame someone else, escalate further. You are a reasonable person underneath the anger — you just need to feel heard first.",

    complaint_handling: "You had your new washer delivered 3 days ago. The delivery crew scratched your hardwood floor, didn't level the machine properly (it vibrates badly), and left packaging materials all over your laundry room. You took photos. You're not screaming angry but you are very disappointed — you spent good money and expected a professional experience. You want the floor fixed, the machine leveled properly, and some kind of acknowledgment that this wasn't acceptable.",

    warranty_call: "Your 2-year-old dishwasher stopped draining mid-cycle. There's standing water in the bottom. You think it should be covered under warranty but you're not sure. You don't have your receipt handy. You want to know: is this covered, how long will it take, who comes to fix it, and will you have to pay anything. You're calm but anxious — you have a dinner party this weekend.",

    return_exchange: "You bought a counter-depth refrigerator 10 days ago. It was delivered and installed, but it sticks out further than you expected and doesn't match the flush look you saw in the showroom. You want to return it but you're also open to hearing about alternatives. You're worried about the restocking fee. You're not angry, just frustrated that it doesn't look like what you imagined.",

    difficult_news: "You ordered a slide-in range 6 weeks ago for your kitchen renovation. The contractor is almost done and your countertops go in next week. You're calling to confirm your delivery date. The rep needs to tell you the range is backordered another 4-6 weeks. You will NOT take this well. Your whole renovation timeline depends on this. Ask about alternatives, loaners, cancellation. You need solutions, not apologies.",

    phone_etiquette: "You're calling the store to check on the status of a dishwasher you ordered 2 weeks ago. You have your order number ready. You're pleasant and patient at first, but you've called twice before and gotten different answers each time. If the rep is professional, clear, and follows through, you'll stay happy. If they fumble, put you on hold without asking, or seem unsure, you'll express mild frustration. Test whether they know proper phone protocol.",

    post_sale_followup: "You had a full kitchen suite delivered last week — fridge, range, dishwasher, and microwave. A sales rep is calling to check in. Everything is mostly fine, but the fridge makes a clicking noise that concerns you (it's probably just the compressor settling, but you don't know that). You're generally happy with your purchase but want reassurance. If the rep handles it well, mention you have a neighbor who is also renovating.",

    review_response: "You are a store manager looking at a 1-star Google review that says: 'Worst experience ever. Delivery was 4 hours late, the installer tracked mud through my kitchen, and when I called to complain nobody called me back for 3 days. I will never buy here again.' You need to draft a professional public response. The rep playing this scenario is practicing writing the response — you are the manager reviewing their draft and giving feedback on tone, accountability, and whether it would make a future customer trust you.",
  };

  let system = scenarios[scenarioType] ?? scenarios.cold_call;
  system += "\n\nRespond as the customer ONLY. 1-3 sentences, conversational, realistic. Don't break character. Don't give coaching.";
  if (knowledge) system += `\n\n[Training knowledge for context]\n${knowledge}`;
  if (livePimData) system += `\n\n[Real current vendor/warranty/recall data — use to make your character more realistic]\n${livePimData}`;
  return system;
}

// ---- Service IQ Chapter Knowledge Loader ----

async function loadServiceIQChapters(admin: SB, scenarioType: string): Promise<string> {
  // Map scenarios to relevant chapter numbers
  const chapterMap: Record<string, number[]> = {
    service_issue:       [128, 129, 130, 133],
    de_escalation:       [128, 129, 130, 131],
    complaint_handling:  [128, 129, 130, 135],
    warranty_call:       [128, 133, 130],
    return_exchange:     [128, 131, 132],
    difficult_news:      [128, 131, 130],
    phone_etiquette:     [125, 126, 128],
    post_sale_followup:  [125, 134, 136],
    review_response:     [127, 136, 130],
  };

  const chapterNums = chapterMap[scenarioType] ?? [125, 128, 129];

  const { data } = await admin
    .from("academy_chapters")
    .select("chapter_number, title, intro")
    .in("chapter_number", chapterNums)
    .order("chapter_number");

  if (!data || data.length === 0) return "";

  // deno-lint-ignore no-explicit-any
  return "SERVICE IQ TRAINING CONTEXT (from AI Academy):\n" + data.map((ch: any) =>
    `${ch.title}:\n${ch.intro}`
  ).join("\n\n");
}

// ---- KPI Loader (service-aware) ----

async function loadKpis(admin: SB, orgId: string, scenarioType?: string): Promise<string[]> {
  const { data } = await admin.from("org_kpis").select("kpi_name").eq("organization_id", orgId).eq("active", true);
  // deno-lint-ignore no-explicit-any
  if (data && data.length > 0) return data.map((k: any) => k.kpi_name);

  // Default KPIs based on scenario type
  if (scenarioType && SERVICE_SCENARIOS.has(scenarioType)) {
    return ["Empathy & Tone", "Active Listening", "De-escalation", "Accuracy", "Resolution Quality"];
  }
  return ["Discovery", "Objection Handling", "Product Knowledge", "Closing", "Follow-up"];
}

// ---- Coaching ----

async function getPersonaCoaching(
  apiKey: string, repMsg: string, customerMsg: string,
  // deno-lint-ignore no-explicit-any
  primaryPersona: any, allPersonas: any[], protocols: any[],
  // deno-lint-ignore no-explicit-any
  kpis: string[], transcript: any[], knowledge: string, livePimData: string, scenarioType?: string
): Promise<{ kpi_scores: Record<string, number>; coaching_tip: string; primary_coach: unknown; handoff_insight: string | null }> {
  if (!primaryPersona) {
    return { kpi_scores: {}, coaching_tip: "Keep going!", primary_coach: null, handoff_insight: null };
  }

  const isService = scenarioType ? SERVICE_SCENARIOS.has(scenarioType) : false;
  const lower = repMsg.toLowerCase() + " " + customerMsg.toLowerCase();
  // deno-lint-ignore no-explicit-any
  let handoffPersona: any = null;
  for (const p of allPersonas) {
    if (p.persona_name === primaryPersona.persona_name) continue;
    // deno-lint-ignore no-explicit-any
    const proto = protocols.find((pr: any) => pr.persona_name === p.persona_name);
    if (proto) {
      for (const trigger of proto.handoff_triggers || []) {
        if (lower.includes(trigger.toLowerCase())) {
          handoffPersona = p;
          break;
        }
      }
    }
    if (handoffPersona) break;
  }

  let coachSystem = `${primaryPersona.prompt_prefix}\n\n`;
  coachSystem += `VOICE: ${primaryPersona.tone}. Keep it brief — one coaching tip in 1-2 sentences.\n`;
  if (isService) {
    coachSystem += `\nThis is a SERVICE IQ training scenario (${scenarioType?.replace(/_/g, ' ')}). Focus your coaching on:\n`;
    coachSystem += `- Did the rep acknowledge the customer's feelings before jumping to solutions?\n`;
    coachSystem += `- Did the rep stay calm and avoid getting defensive?\n`;
    coachSystem += `- Was the information given accurate (check against live PIM data if available)?\n`;
    coachSystem += `- Did the rep offer a clear path to resolution?\n`;
    coachSystem += `- Did the rep use proper phone/email etiquette if applicable?\n`;
  }
  if (knowledge) coachSystem += `\nTRAINING CONTEXT:\n${knowledge}\n`;
  coachSystem += `Score the rep's last message on these KPIs (1-10): ${kpis.join(", ")}.\n`;
  coachSystem += `If the rep stated a warranty term, phone number, or recall status that conflicts with the LIVE PRODUCT IQ PIM DATA below, call it out specifically in your coaching tip — accuracy matters.\n`;
  if (handoffPersona) {
    // deno-lint-ignore no-explicit-any
    const handoffProto = protocols.find((pr: any) => pr.persona_name === handoffPersona.persona_name);
    coachSystem += `\nHANDOFF: The conversation touches ${handoffPersona.persona_name}'s area (${handoffPersona.persona_role}). `;
    coachSystem += `Include a one-sentence insight from ${handoffPersona.persona_name} in their voice (${handoffPersona.tone}). `;
    coachSystem += `Use their handoff style: "${handoffProto?.handoff_template ?? ''}"\n`;
  }
  if (livePimData) coachSystem += `\nLIVE PRODUCT IQ PIM DATA:\n${livePimData}\n`;
  coachSystem += `\nRespond ONLY with JSON (no fences): {"kpi_scores":{${kpis.map(k => `"${k}":<1-10>`).join(",")}},"coaching_tip":"<your tip in persona voice>","handoff_insight":${handoffPersona ? '"<one sentence from ' + handoffPersona.persona_name + '>"' : 'null'}}`;

  // deno-lint-ignore no-explicit-any
  const coachInput = `Recent transcript (last 4 turns):\n${transcript.slice(-4).map((t: any) => `${t.role}: ${t.content}`).join("\n")}\n\nRep just said: "${repMsg}"\nCustomer responded: "${customerMsg}"`;

  const resp = await callClaude(apiKey, MODEL, coachSystem, coachInput);
  if (typeof resp === "string") {
    try {
      const parsed = JSON.parse(resp.replace(/```json|```/g, "").trim());
      return {
        kpi_scores: parsed.kpi_scores ?? {},
        coaching_tip: parsed.coaching_tip ?? "Keep it up!",
        primary_coach: { name: primaryPersona.persona_name, emoji: primaryPersona.avatar_emoji, role: primaryPersona.persona_role },
        handoff_insight: parsed.handoff_insight ?? null,
      };
    } catch {
      return { kpi_scores: {}, coaching_tip: resp.slice(0, 200), primary_coach: { name: primaryPersona.persona_name, emoji: primaryPersona.avatar_emoji, role: primaryPersona.persona_role }, handoff_insight: null };
    }
  }
  return { kpi_scores: {}, coaching_tip: "Keep going!", primary_coach: { name: primaryPersona.persona_name, emoji: primaryPersona.avatar_emoji, role: primaryPersona.persona_role }, handoff_insight: null };
}

// ---- Data Loaders ----

async function loadPersona(admin: SB, orgId: string, name: string) {
  const { data } = await admin.from("ai_personas").select("persona_name, persona_role, avatar_emoji, tone, specialization, prompt_prefix").eq("organization_id", orgId).eq("persona_name", name).eq("active", true).maybeSingle();
  if (data) return data;
  const { data: tj } = await admin.from("ai_personas").select("persona_name, persona_role, avatar_emoji, tone, specialization, prompt_prefix").eq("organization_id", orgId).eq("persona_name", "TJ").eq("active", true).maybeSingle();
  return tj;
}

async function loadAllPersonas(admin: SB, orgId: string) {
  const { data } = await admin.from("ai_personas").select("persona_name, persona_role, avatar_emoji, tone, specialization, prompt_prefix").eq("organization_id", orgId).eq("active", true);
  return data ?? [];
}

async function loadProtocols(admin: SB, orgId: string) {
  const { data } = await admin.from("persona_communication_protocol").select("persona_name, handoff_triggers, handoff_style, handoff_template, debate_approach, defer_pattern, max_response_length").eq("organization_id", orgId);
  return data ?? [];
}

async function loadKnowledge(admin: SB, orgId: string, query: string): Promise<string> {
  const { data } = await admin
    .from("ai_knowledge_chunks")
    .select("chunk_key,title,content,organization_id")
    .eq("status", "active")
    .or(`organization_id.eq.${orgId},organization_id.is.null`)
    .limit(120);

  const terms = new Set(query.toLowerCase().split(/[^a-z0-9]+/).filter((t: string) => t.length > 3));
  const ranked = (data ?? [])
    // deno-lint-ignore no-explicit-any
    .map((c: any) => {
      const text = `${c.title ?? ""} ${c.content ?? ""}`.toLowerCase();
      let score = 0;
      for (const t of terms) if (text.includes(t)) score++;
      return { ...c, score };
    })
    // deno-lint-ignore no-explicit-any
    .sort((a: any, b: any) => b.score - a.score)
    .slice(0, 5);

  // deno-lint-ignore no-explicit-any
  return ranked.map((k: any) => k.content).join("\n");
}

interface LivePimContext { matchedBrands: string[]; text: string; }

async function fetchLivePimContext(admin: SB, textToScan: string): Promise<LivePimContext> {
  const lower = (textToScan || "").toLowerCase();
  const { data: brandRows } = await admin.from("brand_catalog").select("brand_name").eq("is_active", true);
  const allBrandNames: string[] = (brandRows ?? []).map((b: { brand_name: string }) => b.brand_name).filter(Boolean);
  const matched = allBrandNames.filter((n) => lower.includes(n.toLowerCase())).sort((a, b) => b.length - a.length).slice(0, MAX_MATCHED_BRANDS);
  if (matched.length === 0) return { matchedBrands: [], text: "" };

  const sections: string[] = [];
  for (const brand of matched) {
    const brandSections: string[] = [];

    const { data: contacts } = await admin.from("aiq_vendor_contacts")
      .select("country,customer_service_phone,customer_service_phone_label,customer_service_hours,service_repair_phone,warranty_phone,trade_distributor_phone,support_email,service_portal_url,owner_account_portal_url,confidence_level,notes")
      .ilike("brand_name", brand);
    for (const c of contacts ?? []) {
      const bits: string[] = [`Country: ${c.country}`];
      if (c.customer_service_phone) bits.push(`${c.customer_service_phone_label ?? "Customer Service"}: ${c.customer_service_phone}${c.customer_service_hours ? " (" + c.customer_service_hours + ")" : ""}`);
      if (c.service_repair_phone && c.service_repair_phone !== c.customer_service_phone) bits.push(`Service/Repair line: ${c.service_repair_phone}`);
      if (c.warranty_phone && c.warranty_phone !== c.customer_service_phone) bits.push(`Warranty line: ${c.warranty_phone}`);
      if (c.trade_distributor_phone) bits.push(`Trade/Distributor line: ${c.trade_distributor_phone}`);
      if (c.support_email) bits.push(`Email: ${c.support_email}`);
      if (c.service_portal_url) bits.push(`Book service online: ${c.service_portal_url}`);
      if (c.owner_account_portal_url) bits.push(`Owner account/warranty lookup: ${c.owner_account_portal_url}`);
      bits.push(`Confidence: ${c.confidence_level}`);
      if (c.notes) bits.push(`Notes: ${c.notes}`);
      brandSections.push(`VENDOR CONTACT (${brand}):\n${bits.join(" | ")}`);
    }

    const { data: recalls } = await admin.from("aiq_recalls")
      .select("title,hazard,recall_date,units_affected,injury_count,remedy,url,model_numbers")
      .ilike("brand_name", brand);
    for (const r of recalls ?? []) {
      brandSections.push(`ACTIVE/HISTORICAL RECALL (${brand}): "${r.title}" (${r.recall_date ?? "date unknown"}). Hazard: ${r.hazard ?? "n/a"}. Affected models: ${(r.model_numbers ?? []).join(", ") || "see notice"}. Units: ${r.units_affected ?? "n/a"}, injuries: ${r.injury_count ?? 0}. Remedy: ${r.remedy ?? "see notice"}. Notice: ${r.url ?? "n/a"}.`);
    }

    const { data: warranties } = await admin.from("aiq_warranty_policies")
      .select("category,full_coverage_years,full_coverage_notes,component_warranties,certified_install_bonus_notes,key_exclusions,last_verified_date")
      .ilike("brand_name", brand);
    for (const w of warranties ?? []) {
      let compText = "";
      try {
        const comps = typeof w.component_warranties === "string" ? JSON.parse(w.component_warranties) : (w.component_warranties ?? []);
        if (Array.isArray(comps) && comps.length) {
          // deno-lint-ignore no-explicit-any
          compText = " Extended coverage: " + comps.map((c: any) => `${c.component} — ${c.years} yr (${c.coverage_type})`).join("; ") + ".";
        }
      } catch { /* ignore */ }
      brandSections.push(`WARRANTY (${brand}, ${w.category}): ${w.full_coverage_years} yr full coverage. ${w.full_coverage_notes ?? ""}${compText} (verified ${w.last_verified_date ?? "unknown"})`);
    }

    if (brandSections.length) sections.push(brandSections.join("\n"));
  }

  if (sections.length === 0) {
    return { matchedBrands: matched, text: `No vendor contact, recall, or warranty records on file yet for: ${matched.join(", ")}. Do not fabricate — this brand isn't in Product IQ PIM yet.` };
  }
  return { matchedBrands: matched, text: sections.join("\n\n") };
}

async function callClaude(apiKey: string, model: string, system: string, userContent: string | null, messages?: Array<{ role: string; content: string }>): Promise<string> {
  const msgs = messages ?? (userContent ? [{ role: "user", content: userContent }] : [{ role: "user", content: "Go." }]);
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model, max_tokens: 800, system, messages: msgs }),
  });
  if (!resp.ok) return "";
  const data = await resp.json();
  return (data.content ?? []).filter((b: { type: string }) => b.type === "text").map((b: { text: string }) => b.text).join("");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
