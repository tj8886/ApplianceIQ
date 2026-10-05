export type Message={role:'user'|'assistant';content:string|Array<{type:'text';text:string}|{type:'image';source:{type:'base64';media_type:string;data:string}}>};
export function configuredModel(env:(name:string)=>string|undefined,tier:string){
 const model=tier==='fast'?env('AI_MODEL_FAST')??env('AI_MODEL_LIGHT'):tier==='light'?env('AI_MODEL_LIGHT')??env('AI_MODEL_FAST'):tier==='strong'?env('AI_MODEL_HEAVY')??env('AI_TEAM_MODEL_STRONG'):tier==='heavy'?env('AI_MODEL_HEAVY')??env('AI_REQUEST_MODEL_HEAVY'):tier==='standard'?env('AI_MODEL_STANDARD')??env('AI_MODEL'):undefined;
 if(!model||!/^[a-zA-Z0-9._-]{1,120}$/.test(model))return null;
 const provider=model.startsWith('claude')?'anthropic':/^(gpt-|o[134]-)/.test(model)?'openai':model.startsWith('gemini')?'gemini':null;
 const key=provider?env(provider==='anthropic'?'ANTHROPIC_API_KEY':provider==='openai'?'OPENAI_API_KEY':'GOOGLE_API_KEY'):undefined;
 return provider&&key?{model,provider,key}:null;
}
export function configuredUtilityModels(env:(name:string)=>string|undefined){
 let values:unknown;try{values=JSON.parse(env('AI_UTILITY_MODELS')??'[]');}catch{return [];}
 if(!Array.isArray(values)||values.length>20)return [];
 return values.filter((v):v is string=>typeof v==='string').map(model=>configuredModel(n=>n==='AI_MODEL_STANDARD'?model:env(n),'standard')).filter((v):v is NonNullable<typeof v>=>!!v);
}
export async function callConfiguredModel(config:{model:string;provider:string;key:string},system:string,messages:Message[],maxTokens:number,fetchImpl:typeof fetch=fetch){
 let url:string;let body:any;let headers:Record<string,string>={'Content-Type':'application/json'};
 if(config.provider==='anthropic'){
  url='https://api.anthropic.com/v1/messages';headers['x-api-key']=config.key;headers['anthropic-version']='2023-06-01';body={model:config.model,max_tokens:maxTokens,system,messages};
 }else if(config.provider==='openai'){
  url='https://api.openai.com/v1/chat/completions';headers.Authorization='Bearer '+config.key;body={model:config.model,messages:[{role:'system',content:system},...messages.map(m=>({role:m.role,content:typeof m.content==='string'?m.content:m.content.map(b=>b.type==='text'?{type:'text',text:b.text}:{type:'image_url',image_url:{url:'data:'+b.source.media_type+';base64,'+b.source.data}})}))],max_completion_tokens:maxTokens,store:false};
 }else{
  url='https://generativelanguage.googleapis.com/v1beta/models/'+encodeURIComponent(config.model)+':generateContent';headers['x-goog-api-key']=config.key;
  body={systemInstruction:{parts:[{text:system}]},contents:messages.map(m=>({role:m.role==='assistant'?'model':'user',parts:typeof m.content==='string'?[{text:m.content}]:m.content.map(b=>b.type==='text'?{text:b.text}:{inlineData:{mimeType:b.source.media_type,data:b.source.data}})})),generationConfig:{maxOutputTokens:maxTokens}};
 }
 const r=await fetchImpl(url,{method:'POST',headers,body:JSON.stringify(body),signal:AbortSignal.timeout(45000)});if(!r.ok)throw new Error('model_call_failed');
 const data=await r.json();
 const answer=config.provider==='anthropic'?(data.content??[]).filter((b:any)=>b.type==='text').map((b:any)=>b.text).join('\n'):config.provider==='openai'?data.choices?.[0]?.message?.content:(data.candidates?.[0]?.content?.parts??[]).map((b:any)=>b.text??'').join('\n');
 const input=Number(config.provider==='anthropic'?data.usage?.input_tokens??0:config.provider==='openai'?data.usage?.prompt_tokens??0:data.usageMetadata?.promptTokenCount??0);
 const output=Number(config.provider==='anthropic'?data.usage?.output_tokens??0:config.provider==='openai'?data.usage?.completion_tokens??0:Number(data.usageMetadata?.candidatesTokenCount??0)+Number(data.usageMetadata?.thoughtsTokenCount??0));
 if(typeof answer!=='string'||!answer||answer.length>100000||!Number.isInteger(input)||!Number.isInteger(output)||input<0||output<0||input+output>1000000)throw new Error('invalid_provider_response');
 return {answer,usage:{input_tokens:input,output_tokens:output},tokens:input+output};
}
