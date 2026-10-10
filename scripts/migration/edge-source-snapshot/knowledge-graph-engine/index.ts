import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
type Json=Record<string,any>;

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:CORS});
  if(req.method!=="POST") return reply({ok:false,error:"method_not_allowed"},405);
  const auth=req.headers.get("Authorization")??"";
  if(!auth.startsWith("Bearer ")) return reply({ok:false,error:"authentication_required"},401);
  let body:Json; try{body=await req.json()}catch{return reply({ok:false,error:"invalid_json"},400)}
  const url=Deno.env.get("SUPABASE_URL")??"", anon=Deno.env.get("SUPABASE_ANON_KEY")??"", service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const admin=createClient(url,service);
  const {data:userData,error:userError}=await userClient.auth.getUser();
  if(userError||!userData.user) return reply({ok:false,error:"invalid_session"},401);
  const organizationId=String(body.organization_id??"");
  if(!organizationId) return reply({ok:false,error:"organization_id_required"},400);
  const {data:member}=await admin.from("organization_members").select("organization_id").eq("organization_id",organizationId).eq("user_id",userData.user.id).maybeSingle();
  if(!member) return reply({ok:false,error:"organization_access_denied"},403);

  if(body.sync===true){
    const {data,error}=await admin.rpc("aiq_sync_knowledge_graph",{p_organization_id:organizationId});
    if(error) return reply({ok:false,error:"graph_sync_failed",detail:error.message},500);
    return reply({ok:true,mode:"sync",result:data});
  }

  const productIds=[...(Array.isArray(body.product_ids)?body.product_ids:[])].map(String).filter(Boolean);
  const models=[...(Array.isArray(body.models)?body.models:[])].map(String).filter(Boolean);
  const query=String(body.query??"").trim();
  let nodes:any[]=[];
  if(productIds.length){
    const {data}=await admin.from("aicrm_graph_nodes").select("*").eq("organization_id",organizationId).eq("entity_type","aiq_products").in("entity_id",productIds).limit(25); nodes=data??[];
  }else if(models.length){
    const {data:products}=await admin.from("aiq_products").select("id").eq("organization_id",organizationId).in("model",models).limit(25);
    const ids=(products??[]).map((p:any)=>p.id);
    if(ids.length){const {data}=await admin.from("aicrm_graph_nodes").select("*").eq("organization_id",organizationId).eq("entity_type","aiq_products").in("entity_id",ids);nodes=data??[];}
  }else if(query){
    const safe=query.replace(/[%_]/g," ").slice(0,100);
    const {data}=await admin.from("aicrm_graph_nodes").select("*").eq("organization_id",organizationId).ilike("label",`%${safe}%`).limit(15);nodes=data??[];
  }
  if(!nodes.length) return reply({ok:true,mode:"lookup",nodes:[],relationships:[],message:"No graph nodes matched."});

  const ids=nodes.map((n:any)=>n.id);
  const {data:edges,error:edgeError}=await admin.from("aicrm_graph_edges").select("id,relationship_type,strength,confidence,source,metadata,from_node:aicrm_graph_nodes!aicrm_graph_edges_from_node_id_fkey(id,node_type,entity_id,entity_type,label,description,metadata),to_node:aicrm_graph_nodes!aicrm_graph_edges_to_node_id_fkey(id,node_type,entity_id,entity_type,label,description,metadata)").eq("organization_id",organizationId).or(`from_node_id.in.(${ids.join(",")}),to_node_id.in.(${ids.join(",")})`).limit(Math.max(20,Math.min(Number(body.limit??100),250)));
  if(edgeError) return reply({ok:false,error:"graph_lookup_failed",detail:edgeError.message},500);
  return reply({ok:true,mode:"lookup",node_count:nodes.length,relationship_count:(edges??[]).length,nodes,relationships:edges??[]});
});

function reply(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json"}})}
