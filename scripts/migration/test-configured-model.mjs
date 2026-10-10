import assert from 'node:assert/strict';
import {configuredModel,callConfiguredModel} from '../../supabase/functions/_shared/configured-model.ts';
for(const [model,provider,keyName,data] of [['claude-configured-test','anthropic','ANTHROPIC_API_KEY',{content:[{type:'text',text:'answer'}],usage:{input_tokens:1,output_tokens:2}}],['gpt-configured-test','openai','OPENAI_API_KEY',{choices:[{message:{content:'answer'}}],usage:{prompt_tokens:1,completion_tokens:2}}],['gemini-configured-test','gemini','GOOGLE_API_KEY',{candidates:[{content:{parts:[{text:'answer'}]}}],usageMetadata:{promptTokenCount:1,candidatesTokenCount:2,thoughtsTokenCount:3}}]]){
 const config=configuredModel(n=>n==='AI_MODEL_FAST'?model:n===keyName?'synthetic-key':undefined,'fast');assert.equal(config.provider,provider);
 const result=await callConfiguredModel(config,'system',[{role:'user',content:'question'}],800,async(url,opts)=>{const body=JSON.parse(opts.body);assert.equal(opts.headers.apikey,undefined);assert.equal(url.includes('synthetic-key'),false);if(provider==='openai'){assert.equal(body.max_completion_tokens,800);assert.equal(body.store,false);}if(provider==='gemini')assert.equal(body.generationConfig.maxOutputTokens,800);return new Response(JSON.stringify(data));});assert.equal(result.answer,'answer');assert.equal(result.tokens,provider==='gemini'?6:3);
}
assert.equal(configuredModel(()=>undefined,'strong'),null);
assert.equal(configuredModel(n=>n==='AI_MODEL_FAST'?'../../malicious':'synthetic','fast'),null);
console.log('Configured model checks passed: source configuration only, three provider contracts, usage, bounded tokens and no key in URL.');
