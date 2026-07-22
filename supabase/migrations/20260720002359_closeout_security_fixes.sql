-- Closeout security fix: match_products was SECURITY DEFINER without a caller
-- membership check, allowing cross-tenant vector queries by any authenticated
-- user who guessed/knew another org's UUID. Guard added; service_role unaffected.
create or replace function public.match_products(p_organization_id uuid, p_query_embedding vector, p_limit integer default 10)
 returns table(product_id uuid, brand text, model text, name text, category text, msrp numeric, similarity double precision)
 language sql
 stable security definer
 set search_path to ''
as $function$
  select p.id, p.brand, p.model, p.name, p.category, p.msrp,
         1 - (p.embedding operator(public.<=>) p_query_embedding) as similarity
    from public.products p
   where p.organization_id = p_organization_id
     and p.embedding is not null
     and (
       (select auth.role()) = 'service_role'
       or public.is_org_member(p_organization_id)
     )
   order by p.embedding operator(public.<=>) p_query_embedding
   limit p_limit;
$function$;
