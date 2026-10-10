import type { Config } from './handler.ts';
// Safe default. A short-lived, exact-manifest configuration is supplied only at deployment.
export const config: Config = { role: 'source', expiresAt: 0, capabilityHash: '', buckets: [], objects: [] };
