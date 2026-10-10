import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { createFloorHandler } from "./handler.ts";
import { migratedEnvironment } from "../_shared/migrated-environment.ts";
Deno.serve(async (req: Request) => {
  try {
    const env = req.method === "OPTIONS" ? (name: string) => Deno.env.get(name) : await migratedEnvironment((name) => Deno.env.get(name));
    return createFloorHandler({ createClient, env })(req);
  } catch {
    return new Response(JSON.stringify({ error: "runtime_configuration_unavailable" }), { status: 503, headers: { "Content-Type": "application/json" } });
  }
});
