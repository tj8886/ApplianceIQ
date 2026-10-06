import { createHandler as governedProxy } from '../media-discovery-proxy/handler.ts';
export function createHandler(dependencies: Parameters<typeof governedProxy>[0]) {
  return governedProxy({ ...dependencies, workflow: 'scraper_proxy', maxTokensCap: 16000,
    defaultMaxTokens: 8000, defaultTier: 'fast', defaultSearch: false, sharedKey: true });
}
