// crm-scheduled-tasks — Runs anniversary outreach, overdue task notifications, and holiday automation.
// Called by cron or manual trigger. No JWT.

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, serviceKey);
  const results: Record<string, unknown> = {};

  // 1. Anniversary outreach: find deals with upcoming purchase anniversaries
  const { data: orgs } = await admin
    .from("organizations")
    .select("id")
    .limit(100);

  let totalAnniversaries = 0;
  for (const org of orgs ?? []) {
    const { data: anniversaries } = await admin.rpc("get_anniversary_outreach", {
      p_org_id: org.id,
      p_days_ahead: 14,
    });
    if (!anniversaries?.length) continue;

    for (const ann of anniversaries) {
      // Check if we already created a task for this anniversary this year
      const taskTitle = `${ann.anniversary_number}-year anniversary: ${ann.contact_name}`;
      const { data: existing } = await admin
        .from("crm_tasks")
        .select("id")
        .eq("organization_id", org.id)
        .eq("title", taskTitle)
        .maybeSingle();
      if (existing) continue;

      // Create anniversary follow-up task
      const dueDate = new Date();
      dueDate.setDate(dueDate.getDate() + ann.days_until);
      await admin.from("crm_tasks").insert({
        organization_id: org.id,
        title: taskTitle,
        description: `Purchase anniversary for ${ann.deal_title}. Great time for a check-in, referral ask, or replacement discussion.`,
        deal_id: ann.deal_id,
        contact_id: ann.contact_id,
        due_at: dueDate.toISOString(),
        priority: "normal",
        task_type: "post_sale",
        source: "ai_generated",
        metadata: {
          anniversary_number: ann.anniversary_number,
          purchase_date: ann.purchase_date,
          auto_generated: true,
        },
      });

      // Create notification
      // Find the deal owner
      const { data: deal } = await admin
        .from("crm_deals")
        .select("owner_user_id")
        .eq("id", ann.deal_id)
        .single();
      if (deal?.owner_user_id) {
        await admin.from("crm_notifications").insert({
          organization_id: org.id,
          user_id: deal.owner_user_id,
          title: `🎂 ${ann.anniversary_number}-Year Anniversary: ${ann.contact_name}`,
          body: `${ann.deal_title} was purchased ${ann.anniversary_number} year(s) ago. Perfect time for a check-in or referral ask.`,
          severity: "info",
          category: "anniversary",
          entity_type: "contact",
          entity_id: ann.contact_id,
        });
      }
      totalAnniversaries++;
    }
  }
  results.anniversaries_created = totalAnniversaries;

  // 2. Overdue task notifications
  let totalOverdue = 0;
  for (const org of orgs ?? []) {
    const { data } = await admin.rpc("notify_overdue_tasks", { p_org_id: org.id });
    totalOverdue += data?.notified ?? 0;
  }
  results.overdue_notifications = totalOverdue;

  // 3. Holiday check: create holiday outreach tasks around key dates
  const today = new Date();
  const month = today.getMonth() + 1;
  const day = today.getDate();
  const holidays: Array<{ month: number; day: number; name: string; daysAhead: number }> = [
    { month: 12, day: 10, name: "Holiday Season", daysAhead: 15 },
    { month: 11, day: 15, name: "Black Friday Prep", daysAhead: 10 },
    { month: 5, day: 1, name: "Victoria Day / Mother's Day", daysAhead: 14 },
    { month: 6, day: 1, name: "Father's Day", daysAhead: 14 },
    { month: 9, day: 1, name: "Labour Day / Back to School", daysAhead: 7 },
  ];

  const activeHoliday = holidays.find(
    (h) => h.month === month && day >= h.day && day <= h.day + 3
  );
  let holidayTasks = 0;
  if (activeHoliday) {
    for (const org of orgs ?? []) {
      // Get customers who purchased in the last 2 years (good candidates for holiday outreach)
      const twoYearsAgo = new Date();
      twoYearsAgo.setFullYear(twoYearsAgo.getFullYear() - 2);
      const { data: recentCustomers } = await admin
        .from("crm_deals")
        .select("id,contact_id,title,owner_user_id,contacts(first_name,last_name,email)")
        .eq("organization_id", org.id)
        .gte("purchase_date", twoYearsAgo.toISOString().slice(0, 10))
        .not("contact_id", "is", null)
        .limit(50);

      for (const deal of recentCustomers ?? []) {
        const contact = deal.contacts as { first_name: string; last_name?: string } | null;
        if (!contact) continue;
        const taskTitle = `${activeHoliday.name} outreach: ${contact.first_name} ${contact.last_name ?? ""}`;
        const { data: exists } = await admin
          .from("crm_tasks")
          .select("id")
          .eq("organization_id", org.id)
          .eq("title", taskTitle)
          .maybeSingle();
        if (exists) continue;

        await admin.from("crm_tasks").insert({
          organization_id: org.id,
          title: taskTitle,
          description: `Send a ${activeHoliday.name} greeting. Great opportunity for referral asks and checking if they need anything new.`,
          contact_id: deal.contact_id,
          deal_id: deal.id,
          assignee_user_id: deal.owner_user_id,
          due_at: new Date(Date.now() + activeHoliday.daysAhead * 864e5).toISOString(),
          priority: "low",
          task_type: "post_sale",
          source: "ai_generated",
          metadata: { holiday: activeHoliday.name, auto_generated: true },
        });
        holidayTasks++;
      }
    }
  }
  results.holiday_tasks = holidayTasks;
  results.holiday_active = activeHoliday?.name ?? null;

  return new Response(JSON.stringify({ ok: true, ...results }), {
    headers: { "Content-Type": "application/json" },
  });
});
