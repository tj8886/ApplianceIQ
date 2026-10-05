import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'No auth' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
    const sb = createClient(supabaseUrl, supabaseKey);

    const { media_id, visit_id, image_base64, image_url } = await req.json();

    if (!visit_id) {
      return new Response(JSON.stringify({ error: 'visit_id required' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Build image content for Claude
    let imageContent: any;
    if (image_base64) {
      imageContent = {
        type: 'image',
        source: { type: 'base64', media_type: 'image/jpeg', data: image_base64 }
      };
    } else if (image_url) {
      // Download from storage
      const { data: fileData } = await sb.storage.from('field-media').download(image_url);
      if (!fileData) {
        return new Response(JSON.stringify({ error: 'Image not found' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
      }
      const buffer = await fileData.arrayBuffer();
      const base64 = btoa(String.fromCharCode(...new Uint8Array(buffer)));
      imageContent = {
        type: 'image',
        source: { type: 'base64', media_type: 'image/jpeg', data: base64 }
      };
    } else {
      return new Response(JSON.stringify({ error: 'image_base64 or image_url required' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (!anthropicKey) {
      // Return mock detections if no API key
      const mockDetections = [
        { detection_type: 'display_condition', description: 'Display appears to need cleaning — visible dust and fingerprints', confidence: 75, suggested_category: 'Dirty display', suggested_severity: 'low' },
        { detection_type: 'signage_check', description: 'Promotional signage not visible for this display area', confidence: 65, suggested_category: 'Missing signage', suggested_severity: 'medium' }
      ];

      const insertData = mockDetections.map(d => ({
        media_id: media_id || null,
        visit_id,
        detection_type: d.detection_type,
        description: d.description,
        confidence: d.confidence,
        suggested_category: d.suggested_category,
        suggested_severity: d.suggested_severity,
        accepted: null
      }));

      const { data: inserted } = await sb.from('field_ai_detections').insert(insertData).select();
      return new Response(JSON.stringify({ detections: inserted, source: 'mock' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // Call Claude Vision
    const claudeRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-6',
        max_tokens: 1500,
        messages: [{
          role: 'user',
          content: [
            imageContent,
            {
              type: 'text',
              text: `You are an appliance retail display auditor. Analyze this photo from a retail store floor and identify any issues with the appliance display(s) visible.

For each issue found, return a JSON array of objects with these fields:
- detection_type: one of "physical_damage", "product_not_functioning", "display_lighting", "missing_signage", "incorrect_signage", "missing_price", "incorrect_price", "dirty_display", "missing_part", "installation_issue", "poor_placement", "competitive_obstruction", "display_condition", "signage_check"
- description: brief description of the issue (1-2 sentences)
- confidence: number 0-100 indicating your confidence
- suggested_category: the issue category matching the detection_type in plain English
- suggested_severity: one of "critical", "high", "medium", "low", "info"
- brand_name: brand visible (if identifiable)
- model_hint: any model number visible (if readable)

If the display looks good with no issues, return an empty array.

Return ONLY the JSON array, no other text.`
            }
          ]
        }]
      })
    });

    const claudeData = await claudeRes.json();
    const responseText = claudeData.content?.[0]?.text || '[]';
    let detections: any[];
    try {
      detections = JSON.parse(responseText.replace(/```json|```/g, '').trim());
    } catch {
      detections = [];
    }

    // Insert detections
    if (detections.length > 0) {
      const insertData = detections.map((d: any) => ({
        media_id: media_id || null,
        visit_id,
        detection_type: d.detection_type || 'display_condition',
        description: d.description || '',
        confidence: d.confidence || 50,
        suggested_category: d.suggested_category || '',
        suggested_severity: d.suggested_severity || 'low',
        bounding_box: d.brand_name ? { brand: d.brand_name, model_hint: d.model_hint } : null,
        accepted: null
      }));

      const { data: inserted } = await sb.from('field_ai_detections').insert(insertData).select();
      return new Response(JSON.stringify({ detections: inserted, source: 'claude' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    return new Response(JSON.stringify({ detections: [], source: 'claude', message: 'No issues detected' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
