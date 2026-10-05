import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const secret = url.searchParams.get('key');
  if (secret !== 'aiq-schema-dump-2026') {
    return new Response('Unauthorized', { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );

  const header = `-- ============================================================\n-- ApplianceIQ Intelligence Group — Full Schema Backup\n-- Generated: ${new Date().toISOString()}\n-- Supabase Project: fumwwhyozeouoqscolke (ca-central-1)\n-- Tables: 340 | RLS Policies: 638 | Functions: 148 | Triggers: 156 | Indexes: 584\n-- Purpose: Complete reproducible schema for disaster recovery\n-- ============================================================\n\n`;

  const sectionOrder = [
    'sequences',
    'batch_01','batch_02a','batch_02b','batch_03','batch_04','batch_05',
    'batch_06','batch_07a','batch_07b','batch_08','batch_09a','batch_09b','batch_10',
    'indexes',
    'functions',
    'triggers',
    'rls_01','rls_02','rls_03','rls_04','rls_05','rls_06','rls_07','rls_08'
  ];

  const sectionLabels: Record<string,string> = {
    sequences: 'SEQUENCES',
    batch_01: 'TABLES: academy_*',
    batch_02a: 'TABLES: ai_* through aicrm_f*',
    batch_02b: 'TABLES: aicrm_g* through aicrm_z*',
    batch_03: 'TABLES: aiq_* through az*',
    batch_04: 'TABLES: b* through c*',
    batch_05: 'TABLES: d* through field_l*',
    batch_06: 'TABLES: field_m* through h*',
    batch_07a: 'TABLES: i* through iq_k*',
    batch_07b: 'TABLES: iq_l* through iz*',
    batch_08: 'TABLES: k* through o*',
    batch_09a: 'TABLES: p* through pih*',
    batch_09b: 'TABLES: piq* through q*',
    batch_10: 'TABLES: r* through z*',
    indexes: 'INDEXES',
    functions: 'FUNCTIONS',
    triggers: 'TRIGGERS',
    rls_01: 'RLS POLICIES: academy_*',
    rls_02: 'RLS POLICIES: ai_* through aicrm_n*',
    rls_03: 'RLS POLICIES: aicrm_o* through b*',
    rls_04: 'RLS POLICIES: c* through e*',
    rls_05: 'RLS POLICIES: f* through ip*',
    rls_06: 'RLS POLICIES: iq* through n*',
    rls_07: 'RLS POLICIES: o* through r*',
    rls_08: 'RLS POLICIES: s* through z*'
  };

  let output = header;

  for (const sec of sectionOrder) {
    const { data, error } = await supabase
      .from('_schema_dump')
      .select('ddl')
      .eq('section', sec)
      .order('id');

    if (error) {
      output += `-- ERROR loading section ${sec}: ${error.message}\n\n`;
      continue;
    }
    if (!data || data.length === 0) continue;

    const label = sectionLabels[sec] || sec.toUpperCase();
    output += `-- =========================\n-- ${label}\n-- =========================\n\n`;
    output += data.map((r: any) => r.ddl).join('\n\n');
    output += '\n\n';
  }

  return new Response(output, {
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Content-Disposition': 'attachment; filename="applianceiq_full_schema.sql"',
      'Connection': 'keep-alive'
    }
  });
});
