import { createClient } from 'npm:@supabase/supabase-js@2.117.2';
import { createHandoffHandler } from './handler.ts';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

// Redeem requires a module-bound single-use ticket; issue also requires a user JWT.
Deno.serve(createHandoffHandler({
  async authenticatedUser(token) {
    const { data, error } = await admin.auth.getUser(token);
    return error ? null : data.user?.id ?? null;
  },
  async issue(userId, ticketHash, targetModule, context) {
    const { data, error } = await admin.rpc('issue_tj_platform_handoff', {
      p_user_id: userId, p_ticket_hash: ticketHash,
      p_target_module_key: targetModule, p_context: context,
    });
    return !error && data === true;
  },
  async consume(ticketHash, targetModule) {
    const { data, error } = await admin.rpc('consume_tj_platform_handoff', {
      p_ticket_hash: ticketHash, p_target_module_key: targetModule,
    });
    return error ? null : data;
  },
  async sessionLink(userId) {
    const { data: account, error } = await admin.auth.admin.getUserById(userId);
    if (error || !account.user?.email || !account.user.email_confirmed_at) return null;
    const { data: link, error: linkError } = await admin.auth.admin.generateLink({
      type: 'magiclink', email: account.user.email,
    });
    // generateLink creates a token; it does not send an email.
    if (linkError || link.user?.id !== userId) return null;
    return link.properties?.hashed_token ?? null;
  },
}));
