import registry from './pim-approved-hosts.json' with {type:'json'};
const HOSTS=new Set(registry.hosts.flatMap(h=>[h,h.startsWith('www.')?h.slice(4):'www.'+h]));
HOSTS.add('lite.duckduckgo.com');
export function approvedPimUrl(value:string){
 if(typeof value!=='string'||value.length>2048)throw new Error('url_not_allowed');
 const u=new URL(value);if(u.protocol!=='https:'||u.port&&u.port!=='443'||u.username||u.password||u.hash||!HOSTS.has(u.hostname.toLowerCase()))throw new Error('url_not_allowed');return u;
}
export function createPublicPimFetch(fetchImpl:typeof fetch=fetch){
 let calls=0;const deadline=Date.now()+30000;
 return async(value:string|URL|Request,options:RequestInit={}):Promise<Response>=>{
  if(++calls>24||Date.now()>deadline)throw new Error('fetch_budget_exceeded');
  let url=approvedPimUrl(String(value));let method=String(options.method??'GET').toUpperCase();if(!['GET','HEAD'].includes(method))throw new Error('fetch_method_not_allowed');
  for(let redirects=0;redirects<=3;redirects++){
   const r=await fetchImpl(url.toString(),{method,redirect:'manual',headers:{'User-Agent':'ApplianceIQ-Catalog/1.0','Accept':'text/html,application/xml,text/xml,application/json','Accept-Language':'en-US,en;q=0.9'},signal:AbortSignal.timeout(Math.min(10000,Math.max(1,deadline-Date.now())))});
   if([301,302,303,307,308].includes(r.status)){await r.body?.cancel();const location=r.headers.get('location');if(!location)throw new Error('invalid_redirect');url=approvedPimUrl(new URL(location,url).toString());continue;}
   if(method==='HEAD')return new Response(null,{status:r.status,headers:r.headers});
   const max=4*1024*1024;if(Number(r.headers.get('content-length'))>max){await r.body?.cancel();throw new Error('upstream_too_large');}
   const reader=r.body?.getReader();let size=0;const chunks:Uint8Array[]=[];
   if(reader){try{for(;;){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>max)throw new Error('upstream_too_large');chunks.push(value);}}catch(e){await reader.cancel();throw e;}}
   const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
   return new Response([204,205,304].includes(r.status)?null:bytes,{status:r.status,headers:r.headers});
  }throw new Error('redirect_limit');
 };
}
