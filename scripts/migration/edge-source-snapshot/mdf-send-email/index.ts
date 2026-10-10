import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const FROM_EMAIL = Deno.env.get('EMAIL_FROM') || 'notifications@applianceiq.ca'

serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const { action, data } = await req.json()
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // ─── SEND EMAIL ────────────────────────────
    if (action === 'send') {
      const { to, subject, html, related_entity, related_id } = data
      
      // Queue the email
      const { data: queued, error: qErr } = await supabase.from('mdf_email_queue').insert({
        to_email: to,
        subject,
        body_html: html,
        related_entity,
        related_id,
      }).select().single()

      if (qErr) {
        return new Response(JSON.stringify({ ok: false, error: 'Queue failed: ' + qErr.message }), 
          { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
      }

      // Send via Resend
      if (RESEND_API_KEY) {
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ from: FROM_EMAIL, to: [to], subject, html }),
        })
        const result = await res.json()
        
        if (res.ok) {
          await supabase.from('mdf_email_queue').update({ 
            status: 'sent', sent_at: new Date().toISOString() 
          }).eq('id', queued.id)
          return new Response(JSON.stringify({ ok: true, sent: true, resend_id: result.id }), 
            { headers: { ...cors, 'Content-Type': 'application/json' } })
        } else {
          await supabase.from('mdf_email_queue').update({ 
            status: 'failed', error_message: JSON.stringify(result) 
          }).eq('id', queued.id)
          return new Response(JSON.stringify({ ok: false, error: result }), 
            { headers: { ...cors, 'Content-Type': 'application/json' } })
        }
      } else {
        return new Response(JSON.stringify({ ok: true, queued: true, note: 'No RESEND_API_KEY — queued only' }), 
          { headers: { ...cors, 'Content-Type': 'application/json' } })
      }
    }

    // ─── PROCESS QUEUE ──────────────────────────
    if (action === 'process_queue') {
      const { data: pending } = await supabase.from('mdf_email_queue')
        .select('*').eq('status', 'pending').order('created_at').limit(10)
      let sent = 0, failed = 0
      for (const email of (pending || [])) {
        if (!RESEND_API_KEY) break
        const res = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ from: FROM_EMAIL, to: [email.to_email], subject: email.subject, html: email.body_html }),
        })
        if (res.ok) {
          await supabase.from('mdf_email_queue').update({ 
            status: 'sent', sent_at: new Date().toISOString() 
          }).eq('id', email.id)
          sent++
        } else {
          const err = await res.json()
          await supabase.from('mdf_email_queue').update({ 
            status: 'failed', error_message: JSON.stringify(err) 
          }).eq('id', email.id)
          failed++
        }
      }
      return new Response(JSON.stringify({ ok: true, processed: sent, failed, total: (pending||[]).length }), 
        { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    // ─── CHECK EXPIRY ───────────────────────────
    if (action === 'check_expiry') {
      const { data: mdfCount, error: e1 } = await supabase.rpc('mdf_check_expiring_funds')
      const { data: contractCount, error: e2 } = await supabase.rpc('mdf_check_expiring_contracts')
      return new Response(JSON.stringify({ 
        ok: true, mdf_alerts: mdfCount, contract_alerts: contractCount,
        errors: [e1?.message, e2?.message].filter(Boolean)
      }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    // ─── TEST ───────────────────────────────────
    if (action === 'test') {
      return new Response(JSON.stringify({ 
        ok: true, 
        has_resend_key: !!RESEND_API_KEY,
        from_email: FROM_EMAIL,
        supabase_url: SUPABASE_URL ? 'set' : 'missing',
        service_key: SUPABASE_SERVICE_KEY ? 'set' : 'missing',
      }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    // ─── SEND TEST EMAIL ────────────────────────
    if (action === 'send_test') {
      const { to } = data
      if (!RESEND_API_KEY) {
        return new Response(JSON.stringify({ ok: false, error: 'No RESEND_API_KEY configured' }), 
          { headers: { ...cors, 'Content-Type': 'application/json' } })
      }
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          from: FROM_EMAIL, 
          to: [to], 
          subject: '[ApplianceIQ] Test Email — MDF/Co-op/VR Platform',
          html: '<div style="font-family:Inter,system-ui,sans-serif;max-width:600px;margin:0 auto"><div style="background:linear-gradient(135deg,#0f172a,#1e293b);padding:24px;border-radius:12px 12px 0 0"><h1 style="color:white;margin:0;font-size:18px">ApplianceIQ</h1><p style="color:#94a3b8;margin:4px 0 0;font-size:12px">MDF / Co-op / VR Platform</p></div><div style="padding:24px;background:white;border:1px solid #e2e8f0;border-top:none;border-radius:0 0 12px 12px"><h2 style="color:#0f172a;margin-top:0">✅ Email is working!</h2><p style="color:#64748b">This confirms your notification system is live. You\'ll receive emails when:</p><ul style="color:#64748b;line-height:1.8"><li>Co-op requests are submitted</li><li>Requests are approved or denied</li><li>MDF funds or contracts are expiring</li></ul><p style="margin-top:24px"><a href="https://applianceiq-mdf-coop-vr.netlify.app" style="background:#0f172a;color:white;padding:10px 20px;border-radius:8px;text-decoration:none;font-weight:600">Open Platform</a></p></div></div>'
        }),
      })
      const result = await res.json()
      
      // Log it
      await supabase.from('mdf_email_queue').insert({
        to_email: to, subject: '[ApplianceIQ] Test Email', body_html: 'test',
        status: res.ok ? 'sent' : 'failed', 
        sent_at: res.ok ? new Date().toISOString() : null,
        error_message: res.ok ? null : JSON.stringify(result),
        related_entity: 'test'
      })
      
      return new Response(JSON.stringify({ ok: res.ok, result }), 
        { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({ error: 'Unknown action. Use: test, send_test, send, process_queue, check_expiry' }), 
      { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message, stack: err.stack }), 
      { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
