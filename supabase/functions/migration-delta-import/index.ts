import {createDeltaHandler} from "../_shared/delta-transfer.ts";
import {windowConfig} from "../_shared/delta-window.ts";
Deno.serve(createDeltaHandler({role: "import",...windowConfig}, key=>Deno.env.get(key)));
