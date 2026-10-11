// Shared request-auth gate for privileged edge functions.
//
// "Privileged" = the handler uses a service-role Supabase client and/or calls a
// paid/outbound vendor (DataForSEO, Icecat, Resend, arbitrary image fetches).
// Such a function must NEVER perform a write or a vendor call for an
// unauthenticated caller. `verify_jwt` is NOT a real gate for this project: the
// public anon key is itself a validly-signed Supabase JWT, so the platform gate
// cannot tell a public caller from a server one. We provision our own shared
// secret instead.
//
// This factors out the previously copy-pasted `timingSafeEqual` + `isAuthorized`
// checks from ingest-retailer-feed / discover-models / run-price-batch /
// rollup-daily-prices into a single source of truth, so a NEW privileged
// function can't silently ship without a gate (the CI enumeration test asserts
// every service-role/vendor function imports this module).
//
// Usage — the FIRST statement inside Deno.serve, before req.json(), before any
// service-role query, before any vendor fetch:
//
//   Deno.serve(async (req) => {
//     const gate = await requireJobAuth(req, { fn: "enrich-partial" });
//     if (gate instanceof Response) return gate;   // 401 or 405 — return as-is
//     // ...authenticated: safe to parse body / query / call vendor
//   });
//
// Guarantees:
//   - Non-POST  -> 405 (always; every legitimate caller POSTs).
//   - Missing / wrong / (fail-closed) unset secret -> 401.
//   - Constant-time comparison (timingSafeEqual on encoded bytes — never `===`).
//   - Fails CLOSED: if the expected-secret env var is unset or empty, deny.
//   - Emits exactly ONE structured audit line per call — never the secret, never
//     the body: {"tag":"job_auth","fn","outcome","reason","mode","ts"}.
//   - LOG_ONLY is observability metadata only. It NEVER changes authorization:
//     a missing, malformed, wrong, or unavailable secret is always denied.

// `Deno` is a global in the Supabase Edge runtime. Declared locally so this file
// also type-checks (and can be unit-tested with a shim) under the Node/vitest CI.
declare const Deno: { env: { get(key: string): string | undefined } };

const DEFAULT_SECRET_ENV = "INGEST_SECRET";
const DEFAULT_HEADER = "x-ingest-secret";

export interface RequireJobAuthOptions {
  /**
   * Function name for the audit log and for the per-function LOG_ONLY flag.
   * Optional: when omitted it is derived from the request URL path.
   */
  fn?: string;
  /**
   * Env var holding the expected shared secret. Default: INGEST_SECRET.
   * Pass a scoped name (e.g. "ENRICH_JOB_SECRET") for least-privilege isolation.
   */
  secretEnv?: string;
  /** Request header carrying the secret. Default: x-ingest-secret. */
  header?: string;
  /**
   * Optional server-side fallback for functions whose secret is stored in an
   * authorized backend such as Supabase Vault. It is consulted only when the
   * named environment variable is unset/blank. The resolved value is never
   * logged and is compared with the same constant-time routine.
   */
  resolveExpectedSecret?: () => Promise<string | null | undefined>;
}

export type JobAuthResult = { ok: true } | Response;

/** Constant-time byte comparison. Never short-circuits on length or content. */
function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  const len = Math.max(aBytes.length, bBytes.length);
  let diff = aBytes.length ^ bBytes.length;
  for (let i = 0; i < len; i++) {
    diff |= (i < aBytes.length ? aBytes[i] : 0) ^ (i < bBytes.length ? bBytes[i] : 0);
  }
  return diff === 0;
}

/** Best-effort function name from the request URL: /functions/v1/<fn> or /<fn>. */
function deriveFn(req: Request): string {
  try {
    const segments = new URL(req.url).pathname.split("/").filter(Boolean);
    const v1 = segments.indexOf("v1");
    const slug = v1 >= 0 ? segments[v1 + 1] : segments[0];
    return slug || "unknown";
  } catch {
    return "unknown";
  }
}

/**
 * Report LOG_ONLY when the global flag is set OR the per-function flag is set.
 * This changes audit metadata only; it cannot authorize a request. Default (no
 * flag) is ENFORCE. Per-function flag name: JOB_AUTH_LOG_ONLY_<FN> with the
 * function name upper-cased and non-alphanumerics collapsed to underscores
 * (e.g. enrich-partial -> JOB_AUTH_LOG_ONLY_ENRICH_PARTIAL). Per-function flags
 * let operators distinguish one function's audit stream at a time.
 */
function isLogOnly(fn: string): boolean {
  if (Deno.env.get("JOB_AUTH_LOG_ONLY") === "1") return true;
  const scoped = "JOB_AUTH_LOG_ONLY_" + fn.toUpperCase().replace(/[^A-Z0-9]+/g, "_");
  return Deno.env.get(scoped) === "1";
}

/** Bound and sanitize every variable audit field before it reaches the log. */
function auditField(value: string, maxLength: number, fallback: string): string {
  const bounded = value.replace(/[^A-Za-z0-9_.:\-]/g, "_").slice(0, maxLength);
  return bounded || fallback;
}

function audit(
  fn: string,
  outcome: "allow" | "deny",
  reason: string,
  mode: "enforce" | "log_only",
): void {
  // One bounded line. Never includes the secret value or the request body.
  console.log(JSON.stringify({
    tag: "job_auth",
    fn: auditField(fn, 80, "unknown"),
    outcome,
    reason: auditField(reason, 160, "unknown"),
    mode,
    ts: new Date().toISOString(),
  }));
}

function jsonResponse(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Authenticate a privileged edge-function request. Returns `{ ok: true }` when
 * the caller may proceed, or a `Response` (401/405) the handler must return
 * as-is. Async so the contract can accommodate future secret backends without a
 * call-site change.
 */
export async function requireJobAuth(
  req: Request,
  opts: RequireJobAuthOptions = {},
): Promise<JobAuthResult> {
  const fn = opts.fn ?? deriveFn(req);
  const header = opts.header ?? DEFAULT_HEADER;
  const secretEnv = opts.secretEnv ?? DEFAULT_SECRET_ENV;
  const logOnly = isLogOnly(fn);
  const mode = logOnly ? "log_only" : "enforce";

  // 1) Method gate — always enforced. Every legitimate caller POSTs, so this
  //    never affects them, and it keeps the 405 contract deterministic.
  if (req.method !== "POST") {
    audit(fn, "deny", `method_not_allowed:${req.method}`, mode);
    return jsonResponse(405, "POST required");
  }

  // 2) Secret gate — fail CLOSED. Evaluate the reason without leaking which part
  //    failed to the caller (the 401 body is always the same generic message).
  const provided = req.headers.get(header)?.trim();
  if (!provided) {
    audit(fn, "deny", `missing_header:${header}`, mode);
    return jsonResponse(401, "unauthorized");
  }

  let expected = Deno.env.get(secretEnv)?.trim();
  let resolverFailed = false;
  if (!expected && opts.resolveExpectedSecret) {
    try {
      expected = (await opts.resolveExpectedSecret())?.trim() || undefined;
    } catch {
      // Authentication infrastructure errors are deliberately indistinguishable
      // from an unavailable expected secret to the caller and always fail closed.
      resolverFailed = true;
    }
  }
  let reason: string;
  if (!expected) {
    reason = resolverFailed
      ? `secret_resolver_failed:${secretEnv}`
      : `secret_env_unset:${secretEnv}`; // fail closed — never allow
  } else if (!timingSafeEqual(provided, expected)) {
    reason = `bad_secret:${header}`;
  } else {
    audit(fn, "allow", "ok", mode);
    return { ok: true };
  }

  // Not authenticated. LOG_ONLY changes the audit mode field above and nothing
  // else: configuration can never turn a denial into authorization.
  audit(fn, "deny", reason, mode);
  return jsonResponse(401, "unauthorized");
}
