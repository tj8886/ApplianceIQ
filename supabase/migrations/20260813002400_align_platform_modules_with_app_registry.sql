do $$
begin
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','crm') where key='crm';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','command-center') where key='command_center';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','spec-iq') where key='spec_iq';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','academy') where key='academy';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','up-system') where key='up_system';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','iq-field') where key='field';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','product-iq') where key='product_iq';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','pim-scraper'), visibility='private', is_marketplace_listed=false where key='scraper';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','ai-coach') where key='ai_coach';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','field-report-analytics','registry_alias','brand_marketing') where key='brand_marketing';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','applianceiq-platform','surface','platform'), is_marketplace_listed=false where key='integrations';
  update public.platform_modules set manifest = coalesce(manifest,'{}'::jsonb) || jsonb_build_object('registry_key','applianceiq-platform','surface','platform') where key='integration_health';

  if not exists (select 1 from public.platform_modules where key='intelligence_group') then
    insert into public.platform_modules(
      key,name,description,icon,app_url,monthly_price_cents,display_order,is_active,
      publisher_name,publisher_type,marketplace_category,visibility,install_mode,commission_bps,
      current_version,manifest,is_marketplace_listed,updated_at
    ) values (
      'intelligence_group','IQ Intelligence Group',
      'Executive intelligence and cross-platform analytics for specialty retail.',
      '🧠','https://applianceiq-intelligence-group.netlify.app',0,94,true,
      'Appliance IQ','first_party','Analytics','private','first_party',0,
      '1.0.0',jsonb_build_object('registry_key','intelligence-group'),false,now()
    );
  else
    update public.platform_modules
      set app_url='https://applianceiq-intelligence-group.netlify.app',
          manifest=coalesce(manifest,'{}'::jsonb)||jsonb_build_object('registry_key','intelligence-group'),
          updated_at=now()
      where key='intelligence_group';
  end if;
end $$;
