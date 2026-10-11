# US UP rotation workflows

US project: `jdxslqmgjsuzoisuhvlc`. UP app: https://applianceiq-iq-up-system.netlify.app.

This patch routes clock-in/out, break/status changes, queue ordering, accept-UP, timeout handling and greeter duty through the authenticated `up_rotation` runtime API. Organization membership, mapped identity, store access, active shifts and staff permissions are checked in the database. Store-level transaction locks serialize queue changes. Members control their own shifts; queue bumping and other staff controls require owner/admin/manager membership.

The generated client maps native login IDs to source user IDs for membership and to profile IDs for floor records. Staff pickers use profile IDs. Imported source files and historical walk-ins remain intact. The US build transforms the source rather than removing it.

Unavailable or busy staff are skipped when selecting current/next UP. Recalculation preserves an accepted offer. Timeout decisions use server time and the exact offered timestamp; stale retries cannot add a second missed-UP metric. Clock-in retries reuse the active shift. Clock-out requires ending/reassigning an active visit first.

Assignment and reassignment keep floor interactions, rep availability and CRM ownership in one transaction with the existing CRM/Spec IQ handoff. End Visit records the reported outcome, updates CRM and returns the rep to the end of the available rotation. Waiting rows receive the new terminal `completed` state. Repeated completion cannot increment sales twice. No price is inferred from a sale outcome.

The imported realtime subscription watched `public` tables, while the US data is in `tj` and is not in a realtime publication. This patch uses a five-second read refresh with one in-flight poll, pauses while forms are open or the document is hidden, and updates after user actions. It does not claim realtime delivery.

Validation: rollback-only SQL fixtures cover authenticated profile reads, clock-in idempotency, queue flags, unavailable skipping, offer acceptance retention, premature/stale timeout denial, one-time missed metrics, reassignment and CRM ownership, terminal completion, one-time closed-sales metrics, greeter return, member restrictions, foreign-organization denial and unmapped identity denial. Generated-client tests cover RPC-only actions, source/profile identity mapping, dated timeout requests, visible failures and script syntax. The eleven-app US build and runtime route tests also pass.

The signed-in browser click-through is still pending. This patch does not certify the separate legacy dispute, settings, onboarding or Command Center snapshot write paths.
