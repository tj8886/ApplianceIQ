// FU-6 stage 1 — the completion row an edge function writes about itself.
//
// THE DEFECT THIS EXISTS FOR. `cron.job_run_details.status` on the nine pg_net
// jobs reports whether `net.http_post` ENQUEUED, not whether the edge function
// ran. A job can read `succeeded` forever while its function has never once
// been reached. The obvious repair — read `net._http_response.status_code` —
// does not work either: that table is pruned after roughly an hour, so any
// reader that samples it inherits a race and reports whatever survived as
// coverage. Same class of error, one layer down.
//
// So the record is written by the thing whose success is in question. A row
// exists in `edge_invocation_log` if and only if the function reached its own
// completion path. That is exactly the claim `job_run_details` cannot make.
//
// THREE STATES, AND THE ONE THAT MATTERS MOST.
//   completed  — a row with outcome='completed'. Confirmed success.
//   failed     — a row with outcome='failed'. The function caught its own error
//                and said so. Confirmed failure.
//   started    — a row with started_at set and completed_at NULL. The function
//                was REACHED. If it stays open past the function's plausible
//                runtime it died mid-run, which is a fact the log could not
//                state before: harvest 504'd for days at ~150s and left nothing
//                at all, so absence was read as "never dispatched" three
//                separate times. A start row makes reached-but-died its own
//                observation instead of a guess.
//   (absent)   — cron fired, no row. UNCONFIRMED, and NOT failure. This is what
//                a 5000 ms pg_net timeout produces: the request may well have
//                been delivered and the function may have finished fine — pg_net
//                simply stopped waiting. Absence cannot distinguish
//                never-delivered from still-running from ran-and-died-before-
//                logging. The checker must never render absence as failure.
//
// FAILURE-TOLERANT BY CONSTRUCTION. If the log insert itself fails, the
// function's real work must not fail with it. Every write here is wrapped and
// swallowed, with a structured console line so the loss is visible in the
// function logs. An observability layer that can take down the thing it
// observes is a worse defect than the blindness it was built to fix.

declare const Deno: { env: { get(key: string): string | undefined } };

/** Minimal shape of the service-role client each function already constructs. */
interface InsertableClient {
  from(table: string): {
    insert(rows: Record<string, unknown>): Promise<{ error: { message: string } | null }>;
    update(values: Record<string, unknown>): {
      eq(column: string, value: unknown): Promise<{ error: { message: string } | null }>;
    };
  };
}

export interface Invocation {
  functionName: string;
  invokedBy: string;
  cronJobId: number | null;
  startedAt: string;
  /**
   * Client-minted id for this invocation's row. Generated here rather than read
   * back from the insert so no `.select()` round trip is needed and the sync
   * call shape at all nine handlers is preserved.
   */
  rowId: string;
  /**
   * Resolves true when the start row landed. `finishInvocation` awaits it to
   * decide UPDATE (row exists) vs INSERT (it never landed). Never rejects.
   * Undefined when `beginInvocation` was called without a client — the
   * pre-start-row shape, which still works and still writes on completion.
   */
  startWrite?: Promise<boolean>;
}

/**
 * Write the start row. Fire-and-forget by design: the returned promise is
 * stored on the Invocation and awaited only at completion time, so the
 * handler's real work is never behind this insert.
 *
 * Failure-tolerant like everything else here — resolves false rather than
 * rejecting, and `finishInvocation` then falls back to a plain insert. The
 * function must not fail because its diary did.
 */
function writeStartRow(client: InsertableClient, inv: Invocation): Promise<boolean> {
  return (async () => {
    try {
      const { error } = await client.from("edge_invocation_log").insert({
        id: inv.rowId,
        function_name: inv.functionName,
        invoked_by: inv.invokedBy,
        cron_jobid: inv.cronJobId,
        started_at: inv.startedAt,
        completed_at: null,
        outcome: null,
        detail: {},
      });
      if (error) {
        console.log(JSON.stringify({
          tag: "edge_invocation_log", fn: inv.functionName,
          outcome: "start_write_failed", reason: error.message.slice(0, 200),
          ts: new Date().toISOString(),
        }));
        return false;
      }
      return true;
    } catch (e) {
      console.log(JSON.stringify({
        tag: "edge_invocation_log", fn: inv.functionName,
        outcome: "start_write_threw", reason: String(e).slice(0, 200),
        ts: new Date().toISOString(),
      }));
      return false;
    }
  })();
}

/**
 * Open an invocation record immediately after authentication and before the
 * privileged work, so `started_at` measures the authenticated job's own span
 * rather than the tail of it. Never call this on an untrusted request.
 *
 * `invoked_by` and `cron_jobid` are read from OPTIONAL request headers
 * (`x-invoked-by`, `x-cron-jobid`). They are optional on purpose: populating
 * them would mean editing all nine `cron.job` command strings, and a change to
 * a cron command is exactly the kind of edit that silently re-binds arguments.
 * The checker does not need them — it matches on function_name and a time
 * window against `cron.job_run_details`. When absent, `invoked_by` records
 * 'unknown', which is honest rather than guessed.
 */
export function beginInvocation(
  req: Request,
  functionName: string,
  client?: InsertableClient,
): Invocation {
  let invokedBy = "unknown";
  let cronJobId: number | null = null;
  try {
    invokedBy = req.headers.get("x-invoked-by")?.trim() || "unknown";
    const raw = req.headers.get("x-cron-jobid")?.trim();
    const parsed = raw ? Number(raw) : Number.NaN;
    cronJobId = Number.isFinite(parsed) ? parsed : null;
  } catch {
    // Header access cannot realistically throw, but this function must never be
    // the reason a handler fails before doing any work.
  }
  const invocation: Invocation = {
    functionName,
    invokedBy,
    cronJobId,
    startedAt: new Date().toISOString(),
    rowId: crypto.randomUUID(),
  };
  // Passing a client opts this invocation into a START row. Without one the
  // behaviour is exactly what it was: nothing until completion.
  if (client) invocation.startWrite = writeStartRow(client, invocation);
  return invocation;
}

/**
 * Close an invocation record. Never throws, never rejects: a logging failure is
 * logged, not propagated.
 *
 * `detail` is the function's OWN summary of what it did — the per-job shape
 * agreed in the design (rows written, cost, counts). It is the part that makes
 * the row worth more than a heartbeat: "ran" and "ran and wrote nothing" are
 * different facts, and only the function can tell them apart.
 */
export async function finishInvocation(
  client: InsertableClient,
  invocation: Invocation,
  outcome: "completed" | "failed",
  detail: Record<string, unknown> = {},
): Promise<void> {
  try {
    // If the start row landed, CLOSE it. If it did not — or this invocation
    // predates start rows — insert a complete row, which is exactly the old
    // behaviour. Either way the log ends with one row per invocation, never two.
    const started = invocation.startWrite ? await invocation.startWrite : false;
    const { error } = started
      ? await client.from("edge_invocation_log").update({
          completed_at: new Date().toISOString(),
          outcome,
          detail,
        }).eq("id", invocation.rowId)
      : await client.from("edge_invocation_log").insert({
          id: invocation.rowId,
          function_name: invocation.functionName,
          invoked_by: invocation.invokedBy,
          cron_jobid: invocation.cronJobId,
          started_at: invocation.startedAt,
          completed_at: new Date().toISOString(),
          outcome,
          detail,
        });
    if (error) {
      console.log(
        JSON.stringify({
          tag: "edge_invocation_log",
          fn: invocation.functionName,
          outcome: "log_write_failed",
          reason: error.message.slice(0, 200),
          ts: new Date().toISOString(),
        }),
      );
    }
  } catch (e) {
    console.log(
      JSON.stringify({
        tag: "edge_invocation_log",
        fn: invocation.functionName,
        outcome: "log_write_threw",
        reason: String(e).slice(0, 200),
        ts: new Date().toISOString(),
      }),
    );
  }
}

/**
 * Convenience wrapper for the common shape: run the work, record completed or
 * failed, re-raise whatever the work threw. The `failed` row is written BEFORE
 * the re-raise so a throwing handler still leaves a confirmed-failure record
 * rather than an ambiguous absence.
 */
export async function withInvocationLog<T>(
  client: InsertableClient,
  req: Request,
  functionName: string,
  work: () => Promise<{ result: T; detail?: Record<string, unknown> }>,
): Promise<T> {
  const invocation = beginInvocation(req, functionName, client);
  try {
    const { result, detail } = await work();
    await finishInvocation(client, invocation, "completed", detail ?? {});
    return result;
  } catch (e) {
    await finishInvocation(client, invocation, "failed", { error: String(e).slice(0, 500) });
    throw e;
  }
}
