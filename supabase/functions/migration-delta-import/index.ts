import {createDeltaHandler} from "../_shared/delta-transfer.ts";
Deno.serve(createDeltaHandler({role: "import",tokenHash: "",expiresAt: "1970-01-01T00:00:00Z"}, key=>Deno.env.get(key)));
