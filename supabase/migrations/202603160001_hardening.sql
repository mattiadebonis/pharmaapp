-- Hardening migration: default cabinet, performance indexes, service_role grants

-- 1. Extend handle_new_user() to create a default cabinet + membership
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  given_name text;
  family_name text;
  full_name text;
  new_cabinet_id uuid;
begin
  given_name := nullif(new.raw_user_meta_data ->> 'given_name', '');
  family_name := nullif(new.raw_user_meta_data ->> 'family_name', '');
  full_name := nullif(new.raw_user_meta_data ->> 'full_name', '');

  insert into public.profiles (id, display_name)
  values (new.id, coalesce(full_name, new.email))
  on conflict (id) do nothing;

  insert into public.user_settings (user_id, catalog_country, business_country)
  values (new.id, 'it', 'it')
  on conflict (user_id) do nothing;

  insert into public.people (owner_user_id, name, surname, is_account)
  values (
    new.id,
    coalesce(given_name, split_part(coalesce(full_name, ''), ' ', 1)),
    coalesce(family_name, nullif(trim(substr(coalesce(full_name, ''), length(split_part(coalesce(full_name, ''), ' ', 1)) + 1)), '')),
    true
  )
  on conflict do nothing;

  -- Create default cabinet
  insert into public.cabinets (id, owner_user_id, name, is_shared)
  values (gen_random_uuid(), new.id, 'Armadietto', false)
  on conflict do nothing
  returning id into new_cabinet_id;

  -- Create owner membership for the default cabinet
  if new_cabinet_id is not null then
    insert into public.cabinet_memberships (cabinet_id, user_id, role, status)
    values (new_cabinet_id, new.id, 'owner', 'active')
    on conflict (cabinet_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

-- 2. Performance indexes
create index if not exists activity_logs_owner_timestamp_idx
  on public.activity_logs(owner_user_id, timestamp desc);

create index if not exists dose_events_therapy_due_at_idx
  on public.dose_events(therapy_id, due_at);

-- 3. Explicit service_role grants on catalog views
grant select on public.catalog_search_v1 to service_role;
grant select on public.catalog_it_search_v1 to service_role;
grant select on public.catalog_us_search_v1 to service_role;
grant execute on function public.fetch_catalog_product_v1(text, text) to service_role;
grant execute on function public.fetch_catalog_package_v1(text, text) to service_role;
