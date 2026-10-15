-- LOCAL REVIEW DRAFT. Requires Supabase's existing managed storage schema.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
  values('earvins-product-images','earvins-product-images',false,1048576,array['image/webp']);

-- One fixed object slot per product. Staff can replace bytes, not create slots
-- or point metadata at arbitrary objects. Developer creates a new product/slot.
create function private.guard_image_path() returns trigger language plpgsql set search_path='' as $$
begin
  if new.storage_path <> 'products/'||new.product_id::text||'/main.webp' then
    raise exception 'Image must use its product object slot' using errcode='23514'; end if;
  return new;
end $$;
create trigger image_slot before insert or update on public.product_images for each row execute function private.guard_image_path();
create function private.image_readable(p_name text) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.product_images i join public.products p on p.id=i.product_id
    join public.categories c on c.id=p.category_id where i.storage_path=p_name and
      (private.is_staff() or (not p.is_archived and c.is_active)));
$$;
create function private.image_writable(p_name text) returns boolean language sql stable security definer set search_path='' as $$
  select private.is_staff() and exists(select 1 from public.product_images where storage_path=p_name);
$$;
create function private.image_object_exists(p_name text) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from storage.objects where bucket_id='earvins-product-images' and name=p_name);
$$;
revoke all on function private.guard_image_path(),private.image_readable(text),private.image_writable(text),private.image_object_exists(text)
  from public,anon,authenticated,service_role,earvins_guest_server,earvins_maintenance;
grant execute on function private.image_readable(text) to anon,authenticated;
grant execute on function private.image_writable(text),private.image_object_exists(text) to authenticated;

create policy earvins_image_read on storage.objects for select to anon,authenticated
using(bucket_id='earvins-product-images' and private.image_readable(name));
create policy earvins_image_insert on storage.objects for insert to authenticated
with check(bucket_id='earvins-product-images' and private.is_developer() and private.image_writable(name));
create policy earvins_image_update on storage.objects for update to authenticated
using(bucket_id='earvins-product-images' and private.image_writable(name))
with check(bucket_id='earvins-product-images' and private.image_writable(name) and private.image_object_exists(name));

-- Restrictive guards stop another permissive policy accidentally reopening this
-- bucket. They leave unrelated buckets' policies unchanged.
create policy earvins_image_read_guard on storage.objects as restrictive for select to anon,authenticated
using(bucket_id<>'earvins-product-images' or private.image_readable(name));
create policy earvins_image_insert_guard on storage.objects as restrictive for insert to authenticated
with check(bucket_id<>'earvins-product-images' or (private.is_developer() and private.image_writable(name)));
create policy earvins_image_update_guard on storage.objects as restrictive for update to authenticated
using(bucket_id<>'earvins-product-images' or private.image_writable(name))
with check(bucket_id<>'earvins-product-images' or (private.image_writable(name) and private.image_object_exists(name)));
create policy earvins_image_anon_insert_guard on storage.objects as restrictive for insert to anon with check(bucket_id<>'earvins-product-images');
create policy earvins_image_anon_update_guard on storage.objects as restrictive for update to anon
using(bucket_id<>'earvins-product-images') with check(bucket_id<>'earvins-product-images');
create policy earvins_image_delete_guard on storage.objects as restrictive for delete to anon,authenticated
using(bucket_id<>'earvins-product-images');
-- No object DELETE, bucket mutation, upload tokens, or service-role access is
-- granted by this draft. Use Storage UPDATE, not upsert, for staff replacements.
commit;
