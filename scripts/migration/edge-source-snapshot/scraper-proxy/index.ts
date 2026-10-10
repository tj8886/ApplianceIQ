import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// scraper-proxy v4 — JWT-protected (was public with shared secret only)
// Now requires BOTH JWT auth AND x-proxy-key header
const ANTHROPIC_KEY = Deno.env.get('ANTHROPIC_API_KEY');
const PROXY_KEY = Deno.env.get('SCRAPER_PROXY_KEY');

const ALLOWED_MODELS = [
  'claude-haiku-4-5-20251001',
  'claude-sonnet-4-6',
  'claude-opus-4-6',
];
const MAX_TOKENS_CAP = 16000;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-proxy-key, x-client-info, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  const clientKey = req.headers.get('x-proxy-key');
  if (!PROXY_KEY || !clientKey || clientKey !== PROXY_KEY) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  if (!ANTHROPIC_KEY) {
    return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured' }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  let body: any;
  try { body = await req.json(); } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  const model = body.model || 'claude-haiku-4-5-20251001';
  if (!ALLOWED_MODELS.includes(model)) {
    return new Response(JSON.stringify({ error: `Model not allowed: ${model}` }), {
      status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  const maxTokens = Math.min(body.max_tokens || 8000, MAX_TOKENS_CAP);
  const anthropicBody: any = { model, max_tokens: maxTokens, messages: body.messages || [] };
  if (body.system) anthropicBody.system = body.system;
  if (body.tools) anthropicBody.tools = body.tools;

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': ANTHROPIC_KEY, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify(anthropicBody),
    });
    const data = await res.text();
    return new Response(data, { status: res.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: 'Proxy error: ' + e.message }), {
      status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
