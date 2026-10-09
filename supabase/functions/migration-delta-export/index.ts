import {createDeltaHandler} from "../_shared/delta-transfer.ts";
import {windowConfig} from "../_shared/delta-window.ts";
Deno.serve(createDeltaHandler({role: "export",...windowConfig}, key=>Deno.env.get(key)));
