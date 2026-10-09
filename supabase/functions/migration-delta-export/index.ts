import {createDeltaHandler} from "../_shared/delta-transfer.ts";
// Closed by default. A short-lived hash-only config is deployed for a reviewed transfer window.
Deno.serve(createDeltaHandler({role: "export",tokenHash: "",expiresAt: "1970-01-01T00:00:00Z"}, key=>Deno.env.get(key)));
