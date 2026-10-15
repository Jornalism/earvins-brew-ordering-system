-- LOCAL REVIEW DRAFT ONLY. Never apply remotely without separate approval.
begin;

create function private.is_staff() returns boolean language sql stable security definer set search_path='' as $$
  select coalesce(auth.jwt()->>'aal','aal1')='aal2' and exists (
    select 1 from public.user_roles r join auth.users u on u.id=r.user_id
    where r.user_id=auth.uid() and r.is_active and not coalesce(u.is_anonymous,false)
      and r.role in ('cafe_admin','developer'));
$$;
create function private.is_developer() returns boolean language sql stable security definer set search_path='' as $$
  select private.is_staff() and exists(select 1 from public.user_roles where user_id=auth.uid() and role='developer');
$$;
create function private.can_cancel_paid() returns boolean language sql stable security definer set search_path='' as $$
  select private.is_staff() and exists(select 1 from public.user_roles where user_id=auth.uid() and (role='developer' or can_cancel_paid));
$$;
create function private.can_record_refund() returns boolean language sql stable security definer set search_path='' as $$
  select private.is_staff() and exists(select 1 from public.user_roles where user_id=auth.uid() and (role='developer' or can_record_refund));
$$;
create function private.reject_delete() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Permanent deletion disabled; archive/deactivate instead' using errcode='42501'; end $$;
create function private.immutable_snapshot() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Historical snapshot is immutable' using errcode='42501'; end $$;
create function private.touch_product() returns trigger language plpgsql set search_path='' as $$
begin new.updated_at:=clock_timestamp(); return new; end $$;
create trigger touch_product before update on public.products for each row execute function private.touch_product();
create function private.lock_option_parent() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='UPDATE' and new.product_id<>old.product_id then raise exception 'Cannot reassign option product' using errcode='23514'; end if;
  perform 1 from public.products where id=new.product_id for update;
  return new;
end $$;
create trigger size_parent_lock before insert or update on public.product_sizes for each row execute function private.lock_option_parent();
create trigger sweetness_parent_lock before insert or update on public.product_sweetness_options for each row execute function private.lock_option_parent();

-- Column privileges prevent staff from providing/changing QR identifiers.
-- Rotation alone may change the identifier; no caller-supplied value is accepted.
create function public.rotate_table_qr(p_table_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
  if not private.is_staff() then raise exception 'MFA staff required' using errcode='42501'; end if;
  update public.cafe_tables set qr_identifier=gen_random_uuid() where id=p_table_id returning qr_identifier into v;
  if not found then raise exception 'Unknown table' using errcode='22023'; end if;
  return v;
end $$;

-- Server generates 32 random bytes, keeps only the token in an HttpOnly cookie,
-- hashes with SHA-256, and passes the 32-byte hash over its private DB connection.
create function private.create_guest_session(p_token_hash bytea,p_ip_hash bytea,p_challenge_verified boolean default false)
returns table(session_id uuid,expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare cfg private.security_settings; v_id uuid; v_exp timestamptz;
begin
  if p_token_hash is null or p_ip_hash is null or octet_length(p_token_hash)<>32 or octet_length(p_ip_hash)<>32 then
    raise exception 'Invalid hash length' using errcode='22023'; end if;
  select * into strict cfg from private.security_settings;
  perform pg_advisory_xact_lock(hashtextextended('guest-ip:'||encode(p_ip_hash,'hex'),0));
  if (select count(*) from private.request_events where ip_hash=p_ip_hash and kind='session' and created_at>clock_timestamp()-interval '1 hour')>=cfg.ip_sessions_per_hour
    and not coalesce(p_challenge_verified,false) then raise exception 'CAPTCHA required' using errcode='P0001'; end if;
  v_exp:=clock_timestamp()+cfg.guest_ttl;
  insert into private.guest_sessions(token_hash,expires_at) values(p_token_hash,v_exp) returning id into v_id;
  insert into private.request_events(ip_hash,kind) values(p_ip_hash,'session');
  return query select v_id,v_exp;
end $$;
create function private.require_guest(p_token_hash bytea) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if p_token_hash is null or octet_length(p_token_hash)<>32 then raise exception 'Guest session required' using errcode='42501'; end if;
  select id into v_id from private.guest_sessions where token_hash=p_token_hash and revoked_at is null and expires_at>clock_timestamp() for update;
  if not found then raise exception 'Guest session expired or invalid' using errcode='42501'; end if;
  return v_id;
end $$;

-- Isolated internal clock makes midnight tests possible by replacing ONLY the
-- function in the disposable test transaction. Production never reads a test GUC.
create function private.queue_clock() returns timestamptz language sql volatile set search_path='' as $$ select clock_timestamp() $$;
create function private.allocate_queue() returns table(business_date date,queue_number integer,allocated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare v_time timestamptz; v_date date; v_number integer;
begin
  -- Single protected allocation lock, acquired BEFORE reading Manila date.
  perform pg_advisory_xact_lock(hashtextextended('earvins:queue-allocation',0));
  v_time:=private.queue_clock(); v_date:=(v_time at time zone 'Asia/Manila')::date;
  insert into public.daily_queue_counters as c(business_date,last_number) values(v_date,1)
    on conflict on constraint daily_queue_counters_pkey do update set last_number=c.last_number+1 returning last_number into v_number;
  return query select v_date,v_number,v_time;
end $$;

create function private.guard_order() returns trigger language plpgsql security definer set search_path='' as $$
declare worker boolean:=current_setting('role',true)='earvins_maintenance';
begin
  if tg_op='INSERT' then
    if new.status<>'Pending Payment' or new.payment_confirmed_at is not null or new.payment_confirmed_by is not null
      or new.cancellation_reason is not null or new.cancelled_by is not null or new.cancellation_actor is not null then
      raise exception 'New order must be Pending Payment' using errcode='23514'; end if;
    return new;
  end if;
  if (to_jsonb(new)-array['status','status_updated_at','payment_confirmed_at','payment_confirmed_by','cancellation_reason','cancelled_by','cancellation_actor','payment_hold_until','payment_hold_by'])
    is distinct from (to_jsonb(old)-array['status','status_updated_at','payment_confirmed_at','payment_confirmed_by','cancellation_reason','cancelled_by','cancellation_actor','payment_hold_until','payment_hold_by']) then
    raise exception 'Order identity/prices/queue/expiry immutable' using errcode='42501'; end if;
  if new.status=old.status then
    if not private.is_staff() or old.status<>'Pending Payment' or
      (to_jsonb(new)-array['payment_hold_until','payment_hold_by']) is distinct from (to_jsonb(old)-array['payment_hold_until','payment_hold_by']) then
      raise exception 'Only staff may place an unpaid counter hold' using errcode='42501'; end if;
    new.payment_hold_by:=auth.uid(); return new;
  end if;
  if not private.is_staff() and not (worker and old.status='Pending Payment' and new.status='Cancelled') then
    raise exception 'Authorized staff required' using errcode='42501'; end if;
  if not ((old.status='Pending Payment' and new.status in ('Preparing','Cancelled')) or
    (old.status='Preparing' and new.status in ('Ready for Pickup','Cancelled')) or
    (old.status='Ready for Pickup' and new.status in ('Completed','Cancelled'))) then
    raise exception 'Forbidden transition' using errcode='23514'; end if;
  if new.status='Cancelled' and old.payment_confirmed_at is not null and not private.can_cancel_paid() then
    raise exception 'Additional paid-cancellation authority required' using errcode='42501'; end if;
  if worker and not private.is_staff() then
    if not (select unpaid_expiry_enabled from private.security_settings) or old.unpaid_expires_at>clock_timestamp()
      or coalesce(old.payment_hold_until,'-infinity'::timestamptz)>clock_timestamp() then
      raise exception 'Order not eligible for expiry' using errcode='42501'; end if;
  end if;
  new.status_updated_at:=clock_timestamp();
  if old.status='Pending Payment' and new.status='Preparing' then
    new.payment_confirmed_at:=clock_timestamp(); new.payment_confirmed_by:=auth.uid();
  else new.payment_confirmed_at:=old.payment_confirmed_at;new.payment_confirmed_by:=old.payment_confirmed_by; end if;
  new.payment_hold_until:=old.payment_hold_until;new.payment_hold_by:=old.payment_hold_by;
  if new.status='Cancelled' then
    if new.cancellation_reason is null or length(btrim(new.cancellation_reason)) not between 1 and 500 then
      raise exception 'Cancellation reason required' using errcode='23514'; end if;
    new.cancelled_by:=case when worker and not private.is_staff() then null else auth.uid() end;
    new.cancellation_actor:=case when worker and not private.is_staff() then 'system' else 'staff' end;
  else new.cancellation_reason:=null;new.cancelled_by:=null;new.cancellation_actor:=null; end if;
  return new;
end $$;
create function private.audit_order() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    insert into public.order_status_history(order_id,from_status,to_status,actor_kind,guest_session_id)
      values(new.id,null,new.status,'guest',new.guest_session_id);
  elsif new.status is distinct from old.status then
    insert into public.order_status_history(order_id,from_status,to_status,actor_kind,actor_id,reason)
      values(new.id,old.status,new.status,coalesce(new.cancellation_actor,'staff'),
        case when new.cancellation_actor='system' then null else auth.uid() end,new.cancellation_reason);
    if new.status='Cancelled' and old.payment_confirmed_at is not null then
      insert into public.order_refunds(order_id,required_amount,cancellation_reason,cancelled_by)
        values(new.id,new.total_amount,new.cancellation_reason,new.cancelled_by);
    end if;
  end if;
  return new;
end $$;
create trigger order_guard before insert or update on public.orders for each row execute function private.guard_order();
create trigger order_audit after insert or update on public.orders for each row execute function private.audit_order();
do $$ declare t text; begin
  foreach t in array array['categories','products','product_sizes','product_sweetness_options','product_images','cafe_tables',
    'orders','order_items','order_item_customizations','order_status_history','daily_queue_counters','order_refunds'] loop
    execute format('create trigger no_delete before delete on public.%I for each row execute function private.reject_delete()',t);
  end loop;
  foreach t in array array['order_items','order_item_customizations','order_status_history'] loop
    execute format('create trigger no_update before update on public.%I for each row execute function private.immutable_snapshot()',t);
  end loop;
end $$;

create policy categories_public_read on public.categories for select to anon,authenticated using(is_active);
create policy categories_staff_read on public.categories for select to authenticated using((select private.is_staff()));
create policy categories_developer_insert on public.categories for insert to authenticated with check((select private.is_developer()));
create policy categories_developer_update on public.categories for update to authenticated using((select private.is_developer())) with check((select private.is_developer()));
create policy products_public_read on public.products for select to anon,authenticated using(not is_archived and exists(select 1 from public.categories c where c.id=category_id and c.is_active));
create policy products_staff_read on public.products for select to authenticated using((select private.is_staff()));
create policy products_developer_insert on public.products for insert to authenticated with check((select private.is_developer()));
create policy products_staff_update on public.products for update to authenticated using((select private.is_staff())) with check((select private.is_staff()));
do $$ declare t text; begin
  foreach t in array array['product_sizes','product_sweetness_options','product_images'] loop
    execute format('create policy catalog_read on public.%I for select to anon,authenticated using(%s exists(select 1 from public.products p where p.id=product_id))',t,case when t='product_images' then '' else 'is_active and' end);
    execute format('create policy staff_read on public.%I for select to authenticated using((select private.is_staff()))',t);
    execute format('create policy staff_insert on public.%I for insert to authenticated with check((select private.is_staff()))',t);
    execute format('create policy staff_update on public.%I for update to authenticated using((select private.is_staff())) with check((select private.is_staff()))',t);
  end loop;
end $$;
create policy tables_staff_read on public.cafe_tables for select to authenticated using((select private.is_staff()));
create policy tables_staff_insert on public.cafe_tables for insert to authenticated with check((select private.is_staff()));
create policy tables_staff_update on public.cafe_tables for update to authenticated using((select private.is_staff())) with check((select private.is_staff()));
create policy roles_read on public.user_roles for select to authenticated using(user_id=auth.uid() or (select private.is_developer()));
do $$ declare t text; begin
  foreach t in array array['orders','order_items','order_item_customizations','order_status_history','order_refunds'] loop
    execute format('create policy staff_read on public.%I for select to authenticated using((select private.is_staff()))',t);
  end loop;
end $$;
grant select on public.categories,public.products,public.product_sizes,public.product_sweetness_options,public.product_images to anon,authenticated;
grant select on public.cafe_tables,public.user_roles,public.orders,public.order_items,public.order_item_customizations,public.order_status_history,public.order_refunds to authenticated;
grant insert on public.categories,public.products,public.product_sizes,public.product_sweetness_options to authenticated;
-- First image association is developer-only; staff can replace the existing slot.
drop policy staff_insert on public.product_images;
create policy developer_insert on public.product_images for insert to authenticated with check((select private.is_developer()));
grant insert on public.product_images to authenticated;
grant insert(table_number,is_active) on public.cafe_tables to authenticated;
grant update(table_number,is_active) on public.cafe_tables to authenticated;
grant update(name,sort_order,is_active) on public.categories to authenticated;
grant update(category_id,name,description,base_price,is_available,is_archived) on public.products to authenticated;
grant update(label,price,is_active,sort_order) on public.product_sizes to authenticated;
grant update(label,is_active,sort_order) on public.product_sweetness_options to authenticated;
-- Image paths are fixed at creation; replacements overwrite the authorized object.
grant update(alt_text) on public.product_images to authenticated;

create function public.resolve_table_qr(p_qr_identifier uuid) returns table(table_number integer)
language sql stable security definer set search_path='' as $$
  select t.table_number from public.cafe_tables t where t.qr_identifier=p_qr_identifier and t.is_active;
$$;

-- No public/anonymous RPC for guest creation, submission or order reads.
create function private.place_order(p_token_hash bytea,p_qr_identifier uuid,p_idempotency_key uuid,p_items jsonb,
  p_ip_hash bytea,p_challenge_verified boolean default false) returns public.orders
language plpgsql security definer set search_path='' as $$
declare
  guest uuid; cfg private.security_settings; req jsonb; old_order public.orders; result public.orders;
  tab public.cafe_tables; prod public.products; sz public.product_sizes; sweet public.product_sweetness_options;
  item jsonb; price numeric(12,2); total numeric(14,2):=0; qty integer; line integer:=0; item_id uuid;
  queue record;
begin
  guest:=private.require_guest(p_token_hash); -- Per-guest row lock serializes limits and retries.
  if p_qr_identifier is null or p_idempotency_key is null or p_items is null or jsonb_typeof(p_items)<>'array'
    or p_ip_hash is null or octet_length(p_ip_hash)<>32 then raise exception 'Invalid request' using errcode='22023'; end if;
  if jsonb_array_length(p_items) not between 1 and 50 or octet_length(p_items::text)>32768 then
    raise exception 'Order request too large' using errcode='22023'; end if;
  req:=jsonb_build_object('qr_identifier',p_qr_identifier,'items',p_items);
  select * into old_order from public.orders where guest_session_id=guest and idempotency_key=p_idempotency_key;
  if found then
    if old_order.request_payload<>req then raise exception 'Idempotency conflict' using errcode='22023'; end if;
    return old_order; -- No allowance consumed, no new event/queue, even after QR deactivation.
  end if;
  select * into strict cfg from private.security_settings;
  if (select count(*) from public.orders where guest_session_id=guest and created_at>clock_timestamp()-interval '1 minute')>=cfg.guest_per_minute
    or (select count(*) from public.orders where guest_session_id=guest and created_at>clock_timestamp()-interval '1 hour')>=cfg.guest_per_hour
    or (select count(*) from public.orders where guest_session_id=guest and status='Pending Payment')>=cfg.guest_unpaid_limit then
    raise exception 'Guest order allowance reached; retry later' using errcode='P0001'; end if;
  -- Fixed lock order: guest -> IP -> table -> product(s) -> global allocation.
  perform pg_advisory_xact_lock(hashtextextended('order-ip:'||encode(p_ip_hash,'hex'),0));
  select * into tab from public.cafe_tables where qr_identifier=p_qr_identifier and is_active for update;
  if not found then raise exception 'Inactive or invalid table QR' using errcode='22023'; end if;
  if not coalesce(p_challenge_verified,false) and (
    (select count(*) from private.request_events where kind='order' and ip_hash=p_ip_hash and created_at>clock_timestamp()-interval '1 minute')>=cfg.ip_challenge_per_minute
    or (select count(*) from private.request_events where kind='order' and table_id=tab.id and created_at>clock_timestamp()-interval '1 minute')>=cfg.table_challenge_per_minute) then
    raise exception 'CAPTCHA required for unusual traffic' using errcode='P0001'; end if;
  perform p.id from public.products p where p.id in(select (x->>'product_id')::uuid from jsonb_array_elements(p_items) x) order by p.id for share;
  for item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(item)<>'object' or exists(select 1 from jsonb_object_keys(item) k where k not in('product_id','quantity','size_option_id','sweetness_option_id','note')) then
      raise exception 'Unsupported item fields' using errcode='22023'; end if;
    if jsonb_typeof(item->'quantity') is distinct from 'number' or (item->>'quantity')!~'^[0-9]{1,2}$' then
      raise exception 'Quantity must be 1-99' using errcode='22023'; end if;
    qty:=(item->>'quantity')::integer;
    if qty<1 or (item ? 'note' and jsonb_typeof(item->'note')<>'string') or length(coalesce(item->>'note',''))>500 then
      raise exception 'Invalid quantity or note' using errcode='22023'; end if;
    select p.* into prod from public.products p join public.categories c on c.id=p.category_id
      where p.id=(item->>'product_id')::uuid and p.is_available and not p.is_archived and c.is_active for share of p,c;
    if not found then raise exception 'Unavailable product' using errcode='22023'; end if;
    price:=prod.base_price;
    if exists(select 1 from public.product_sizes where product_id=prod.id and is_active) then
      select * into sz from public.product_sizes where id=(item->>'size_option_id')::uuid and product_id=prod.id and is_active;
      if not found then raise exception 'Valid size required' using errcode='22023'; end if;
      price:=sz.price;
    elsif item->>'size_option_id' is not null then raise exception 'Unexpected size' using errcode='22023'; end if;
    if exists(select 1 from public.product_sweetness_options where product_id=prod.id and is_active) then
      select * into sweet from public.product_sweetness_options where id=(item->>'sweetness_option_id')::uuid and product_id=prod.id and is_active;
      if not found then raise exception 'Valid sweetness required' using errcode='22023'; end if;
    elsif item->>'sweetness_option_id' is not null then raise exception 'Unexpected sweetness' using errcode='22023'; end if;
    total:=total+price*qty;
  end loop;
  select * into queue from private.allocate_queue();
  insert into public.orders(guest_session_id,table_id,table_number_snapshot,business_date,queue_number,idempotency_key,
    request_payload,total_amount,created_at,status_updated_at,unpaid_expires_at)
    values(guest,tab.id,tab.table_number,queue.business_date,queue.queue_number,p_idempotency_key,req,total,
      queue.allocated_at,queue.allocated_at,queue.allocated_at+cfg.unpaid_ttl) returning * into result;
  for item in select value from jsonb_array_elements(p_items) loop
    line:=line+1;select * into strict prod from public.products where id=(item->>'product_id')::uuid;price:=prod.base_price;
    if item->>'size_option_id' is not null then select * into strict sz from public.product_sizes where id=(item->>'size_option_id')::uuid;price:=sz.price;end if;
    insert into public.order_items(order_id,product_id,line_number,product_name_snapshot,quantity,unit_price,customer_note)
      values(result.id,prod.id,line,prod.name,(item->>'quantity')::integer,price,coalesce(item->>'note','')) returning id into item_id;
    if item->>'size_option_id' is not null then
      insert into public.order_item_customizations(order_item_id,kind,size_option_id,label_snapshot,price_snapshot) values(item_id,'size',sz.id,sz.label,sz.price);end if;
    if item->>'sweetness_option_id' is not null then
      select * into strict sweet from public.product_sweetness_options where id=(item->>'sweetness_option_id')::uuid;
      insert into public.order_item_customizations(order_item_id,kind,sweetness_option_id,label_snapshot,price_snapshot) values(item_id,'sweetness',sweet.id,sweet.label,0);end if;
  end loop;
  insert into private.request_events(guest_session_id,ip_hash,table_id,kind) values(guest,p_ip_hash,tab.id,'order');
  return result;
end $$;
create function private.read_guest_order(p_token_hash bytea,p_order_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare guest uuid; ord public.orders; result jsonb;
begin
  guest:=private.require_guest(p_token_hash);
  select * into ord from public.orders where id=p_order_id and guest_session_id=guest;
  if not found then raise exception 'Order not found' using errcode='42501';end if;
  -- Curated response omits hashes, raw request/QR, staff UUIDs and internal session ID.
  select jsonb_build_object('id',ord.id,'queue_number',ord.queue_number,'business_date',ord.business_date,
    'table_number',ord.table_number_snapshot,'status',ord.status,'total',ord.total_amount,'currency',ord.currency,
    'unpaid_expires_at',ord.unpaid_expires_at,'payment_hold_until',ord.payment_hold_until,
    'items',coalesce((select jsonb_agg(jsonb_build_object('name',i.product_name_snapshot,'quantity',i.quantity,
      'unit_price',i.unit_price,'line_total',i.line_total,'note',i.customer_note,'customizations',
      coalesce((select jsonb_agg(jsonb_build_object('kind',c.kind,'label',c.label_snapshot,'price',c.price_snapshot))
        from public.order_item_customizations c where c.order_item_id=i.id),'[]'::jsonb)) order by i.line_number)
      from public.order_items i where i.order_id=ord.id),'[]'::jsonb)) into result;
  return result;
end $$;

create function public.transition_order(p_order_id uuid,p_expected_status public.order_status,p_next_status public.order_status,p_reason text default null)
returns public.orders language plpgsql security definer set search_path='' as $$
declare ord public.orders;
begin
  if not private.is_staff() then raise exception 'MFA staff required' using errcode='42501';end if;
  select * into ord from public.orders where id=p_order_id for update;
  if not found then raise exception 'Unknown order' using errcode='22023';end if;
  if ord.status is distinct from p_expected_status then raise exception 'Stale order state' using errcode='40001';end if;
  update public.orders set status=p_next_status,cancellation_reason=case when p_next_status='Cancelled' then p_reason else null end
    where id=p_order_id returning * into ord;return ord;
end $$;
create function public.hold_counter_payment(p_order_id uuid,p_minutes integer default 10) returns timestamptz
language plpgsql security definer set search_path='' as $$
declare v timestamptz;
begin
  if not private.is_staff() then raise exception 'MFA staff required' using errcode='42501';end if;
  if p_minutes is null or p_minutes not between 1 and 15 then raise exception 'Hold must be 1-15 minutes' using errcode='22023';end if;
  update public.orders set payment_hold_until=greatest(coalesce(payment_hold_until,'-infinity'::timestamptz),clock_timestamp()+make_interval(mins=>p_minutes)),payment_hold_by=auth.uid()
    where id=p_order_id and status='Pending Payment' returning payment_hold_until into v;
  if not found then raise exception 'Unpaid order required' using errcode='22023';end if;return v;
end $$;
create function public.record_manual_refund(p_order_id uuid,p_amount numeric,p_reason text,p_waive boolean default false)
returns public.order_refunds language plpgsql security definer set search_path='' as $$
declare r public.order_refunds;
begin
  if not private.can_record_refund() or (coalesce(p_waive,false) and not private.is_developer()) then
    raise exception 'Additional refund authority required' using errcode='42501';end if;
  if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'Refund reason required' using errcode='22023';end if;
  select * into r from public.order_refunds where order_id=p_order_id for update;
  if not found or r.status<>'Pending' then raise exception 'Pending refund required' using errcode='22023';end if;
  if p_amount is null or p_amount<>(case when coalesce(p_waive,false) then 0 else r.required_amount end) then
    raise exception 'Record full refund amount; waiver requires developer' using errcode='22023';end if;
  update public.order_refunds set status=case when coalesce(p_waive,false) then 'Waived' else 'Recorded' end,
    recorded_amount=p_amount,resolved_by=auth.uid(),resolution_reason=p_reason,resolved_at=clock_timestamp()
    where order_id=p_order_id returning * into r;return r;
end $$;
create function private.expire_unpaid_orders(p_limit integer default 100) returns integer
language plpgsql security definer set search_path='' as $$
declare ord record; n integer:=0;
begin
  if current_setting('role',true)<>'earvins_maintenance' then raise exception 'Maintenance role required' using errcode='42501';end if;
  if not (select unpaid_expiry_enabled from private.security_settings) then return 0;end if;
  if p_limit is null or p_limit not between 1 and 1000 then raise exception 'Invalid batch size' using errcode='22023';end if;
  for ord in select id from public.orders where status='Pending Payment' and unpaid_expires_at<=clock_timestamp()
    and coalesce(payment_hold_until,'-infinity'::timestamptz)<=clock_timestamp()
    order by unpaid_expires_at for update skip locked limit p_limit loop
    update public.orders set status='Cancelled',cancellation_reason='Unpaid order expired; please place a new order at the counter if needed' where id=ord.id;
    n:=n+1;
  end loop;return n;
end $$;
create function private.clean_expired_guest_tokens() returns integer
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
  update private.guest_sessions set token_hash=null where token_hash is not null and
    expires_at<clock_timestamp()-(select expired_token_retention from private.security_settings);
  get diagnostics n=row_count;
  delete from private.request_events where created_at<clock_timestamp()-(select request_event_retention from private.security_settings);
  return n; -- No guest/order/history/refund rows are deleted.
end $$;

-- Expose invoker wrappers; privileged implementations stay outside API schemas.
alter function public.rotate_table_qr(uuid) set schema private;
alter function public.resolve_table_qr(uuid) set schema private;
alter function public.transition_order(uuid,public.order_status,public.order_status,text) set schema private;
alter function public.hold_counter_payment(uuid,integer) set schema private;
alter function public.record_manual_refund(uuid,numeric,text,boolean) set schema private;
create function public.rotate_table_qr(p_table_id uuid) returns uuid language sql volatile security invoker set search_path='' as $$select private.rotate_table_qr(p_table_id)$$;
create function public.resolve_table_qr(p_qr_identifier uuid) returns table(table_number integer) language sql stable security invoker set search_path='' as $$select * from private.resolve_table_qr(p_qr_identifier)$$;
create function public.transition_order(p_order_id uuid,p_expected_status public.order_status,p_next_status public.order_status,p_reason text default null)
returns public.orders language sql volatile security invoker set search_path='' as $$select private.transition_order(p_order_id,p_expected_status,p_next_status,p_reason)$$;
create function public.hold_counter_payment(p_order_id uuid,p_minutes integer default 10) returns timestamptz language sql volatile security invoker set search_path='' as $$select private.hold_counter_payment(p_order_id,p_minutes)$$;
create function public.record_manual_refund(p_order_id uuid,p_amount numeric,p_reason text,p_waive boolean default false) returns public.order_refunds language sql volatile security invoker set search_path='' as $$select private.record_manual_refund(p_order_id,p_amount,p_reason,p_waive)$$;

-- Explicit execution whitelist. Fresh private schema is a precondition.
do $$ declare f record; begin
  for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' or (n.nspname='public' and p.proname in('rotate_table_qr','resolve_table_qr',
      'transition_order','hold_counter_payment','record_manual_refund')) loop
    execute format('revoke all on function %s from public,anon,authenticated,service_role,earvins_guest_server,earvins_maintenance',f.signature);
  end loop;
end $$;
grant usage on schema private to anon,authenticated,earvins_guest_server,earvins_maintenance;
grant usage on schema public to earvins_guest_server,earvins_maintenance;
grant execute on function private.is_staff(),private.is_developer() to authenticated;
grant execute on function public.resolve_table_qr(uuid),private.resolve_table_qr(uuid) to anon,authenticated;
grant execute on function public.rotate_table_qr(uuid),public.transition_order(uuid,public.order_status,public.order_status,text),
  public.hold_counter_payment(uuid,integer),public.record_manual_refund(uuid,numeric,text,boolean) to authenticated;
grant execute on function private.rotate_table_qr(uuid),private.transition_order(uuid,public.order_status,public.order_status,text),
  private.hold_counter_payment(uuid,integer),private.record_manual_refund(uuid,numeric,text,boolean) to authenticated;
grant execute on function private.create_guest_session(bytea,bytea,boolean),private.place_order(bytea,uuid,uuid,jsonb,bytea,boolean),
  private.read_guest_order(bytea,uuid) to earvins_guest_server;
grant execute on function private.expire_unpaid_orders(integer),private.clean_expired_guest_tokens() to earvins_maintenance;
-- No runtime table access for server roles; their functions enforce every check.
commit;
