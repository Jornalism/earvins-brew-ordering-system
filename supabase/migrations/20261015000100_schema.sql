-- REVIEW DRAFT. Local preparation only; do not apply to the hosted project yet.
begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- Provision login credentials/membership separately after approval. No login or
-- password is created here, and these roles are never granted to browser roles.
create role earvins_guest_server nologin noinherit nobypassrls;
create role earvins_maintenance nologin noinherit nobypassrls;

create table private.security_settings (
  singleton boolean primary key default true check(singleton),
  guest_ttl interval not null default interval '7 days' check(guest_ttl between interval '1 hour' and interval '30 days'),
  expired_token_retention interval not null default interval '30 days' check(expired_token_retention >= interval '0 days'),
  order_retention interval default null check(order_retention is null or order_retention >= interval '365 days'),
  guest_per_minute integer not null default 3 check(guest_per_minute between 1 and 1000),
  guest_per_hour integer not null default 10 check(guest_per_hour between 1 and 10000),
  guest_unpaid_limit integer not null default 2 check(guest_unpaid_limit between 1 and 100),
  ip_challenge_per_minute integer not null default 30 check(ip_challenge_per_minute > 0),
  table_challenge_per_minute integer not null default 15 check(table_challenge_per_minute > 0),
  ip_sessions_per_hour integer not null default 120 check(ip_sessions_per_hour > 0),
  request_event_retention interval not null default interval '2 hours' check(request_event_retention between interval '2 hours' and interval '24 hours'),
  unpaid_expiry_enabled boolean not null default false,
  unpaid_ttl interval not null default interval '30 minutes' check(unpaid_ttl between interval '10 minutes' and interval '2 hours')
);
insert into private.security_settings default values;
create table private.guest_sessions (
  id uuid primary key default gen_random_uuid(),
  token_hash bytea unique check(token_hash is null or octet_length(token_hash)=32),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  check(expires_at > created_at)
);
create index guest_expiry_idx on private.guest_sessions(expires_at);
create table private.request_events (
  id bigint generated always as identity primary key,
  guest_session_id uuid references private.guest_sessions(id) on delete restrict,
  ip_hash bytea not null check(octet_length(ip_hash)=32),
  table_id uuid,
  kind text not null check(kind in ('session','order')),
  created_at timestamptz not null default clock_timestamp()
);

create type public.order_status as enum (
  'Pending Payment', 'Preparing', 'Ready for Pickup', 'Completed', 'Cancelled'
);
create type public.app_role as enum ('cafe_admin', 'developer');

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name text not null unique check (length(btrim(name)) between 1 and 80),
  sort_order integer not null default 0,
  is_active boolean not null default true
);
create table public.products (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null check (length(btrim(name)) between 1 and 160),
  description text not null default '' check (length(description) <= 2000),
  base_price numeric(12,2) not null check (base_price between 0 and 1000000),
  is_available boolean not null default true,
  is_archived boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index products_category_idx on public.products(category_id);
create table public.product_sizes (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  label text not null check (length(btrim(label)) between 1 and 80),
  price numeric(12,2) not null check (price between 0 and 1000000),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  unique(product_id, label)
);
create table public.product_sweetness_options (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  label text not null check (length(btrim(label)) between 1 and 80),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  unique(product_id, label)
);
create table public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null unique references public.products(id) on delete restrict,
  -- Relative path in a future dedicated Storage bucket; never a signed URL.
  storage_path text not null check (
    length(storage_path) between 1 and 500 and storage_path !~ '(^/|\.\.|://)'
  ),
  alt_text text not null default '' check (length(alt_text) <= 200),
  updated_at timestamptz not null default clock_timestamp()
);
create table public.cafe_tables (
  id uuid primary key default gen_random_uuid(),
  table_number integer not null unique check (table_number between 1 and 9999),
  -- Random bearer identifier, not a sequential table number. Rotate when needed.
  qr_identifier uuid not null unique default gen_random_uuid(),
  is_active boolean not null default true,
  created_at timestamptz not null default clock_timestamp()
);
alter table private.request_events add foreign key(table_id) references public.cafe_tables(id) on delete restrict;
create index request_guest_time_idx on private.request_events(guest_session_id,created_at);
create index request_ip_time_idx on private.request_events(ip_hash,created_at);
create index request_table_time_idx on private.request_events(table_id,created_at);
create index request_time_idx on private.request_events(created_at);
create table public.user_roles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  role public.app_role not null,
  is_active boolean not null default true,
  can_cancel_paid boolean not null default false,
  can_record_refund boolean not null default false,
  granted_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp()
);
create table public.daily_queue_counters (
  business_date date primary key,
  last_number integer not null check (last_number > 0)
);
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  guest_session_id uuid not null references private.guest_sessions(id) on delete restrict,
  table_id uuid not null references public.cafe_tables(id) on delete restrict,
  table_number_snapshot integer not null check (table_number_snapshot > 0),
  business_date date not null,
  queue_number integer not null check (queue_number > 0),
  idempotency_key uuid not null,
  -- Canonical submitted IDs/quantities/notes; no browser price or total fields.
  request_payload jsonb not null check (jsonb_typeof(request_payload) = 'object'),
  status public.order_status not null default 'Pending Payment',
  currency text not null default 'PHP' check (currency = 'PHP'),
  total_amount numeric(14,2) not null check (total_amount >= 0),
  payment_confirmed_at timestamptz,
  payment_confirmed_by uuid references auth.users(id) on delete restrict,
  cancellation_reason text check (length(btrim(cancellation_reason)) between 1 and 500),
  cancelled_by uuid references auth.users(id) on delete restrict,
  cancellation_actor text check(cancellation_actor in ('staff','system')),
  unpaid_expires_at timestamptz not null,
  payment_hold_until timestamptz,
  payment_hold_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  status_updated_at timestamptz not null default clock_timestamp(),
  unique(business_date, queue_number),
  unique(guest_session_id, idempotency_key),
  check (business_date = (created_at at time zone 'Asia/Manila')::date),
  check ((payment_confirmed_at is null) = (payment_confirmed_by is null)),
  check (status not in ('Preparing', 'Ready for Pickup', 'Completed') or payment_confirmed_at is not null),
  check ((status = 'Cancelled') = (cancellation_reason is not null)),
  check ((status = 'Cancelled') = (cancellation_actor is not null)),
  check (cancellation_actor is distinct from 'staff' or cancelled_by is not null)
);
create index orders_guest_created_idx on public.orders(guest_session_id, created_at desc);
create index orders_cancelled_by_idx on public.orders(cancelled_by);
create index orders_hold_by_idx on public.orders(payment_hold_by);
create index orders_unpaid_expiry_idx on public.orders(unpaid_expires_at) where status='Pending Payment';
create index orders_table_idx on public.orders(table_id);
create index orders_payment_actor_idx on public.orders(payment_confirmed_by);
create index orders_active_queue_idx on public.orders(business_date, queue_number)
  where status in ('Pending Payment', 'Preparing', 'Ready for Pickup');
create index orders_history_idx on public.orders(business_date, created_at desc)
  where status in ('Completed', 'Cancelled');
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  line_number integer not null check (line_number > 0),
  product_name_snapshot text not null check (length(btrim(product_name_snapshot)) between 1 and 160),
  quantity integer not null check (quantity between 1 and 99),
  unit_price numeric(12,2) not null check (unit_price between 0 and 1000000),
  line_total numeric(14,2) generated always as (quantity * unit_price) stored,
  customer_note text not null default '' check (length(customer_note) <= 500),
  unique(order_id, line_number)
);
create index order_items_product_idx on public.order_items(product_id);
create table public.order_item_customizations (
  id uuid primary key default gen_random_uuid(),
  order_item_id uuid not null references public.order_items(id) on delete restrict,
  kind text not null check (kind in ('size', 'sweetness')),
  size_option_id uuid references public.product_sizes(id) on delete restrict,
  sweetness_option_id uuid references public.product_sweetness_options(id) on delete restrict,
  label_snapshot text not null check (length(btrim(label_snapshot)) between 1 and 80),
  -- Sizes are full replacement prices, not surcharges. Sweetness is free.
  price_snapshot numeric(12,2) not null check (price_snapshot >= 0),
  unique(order_item_id, kind),
  check ((kind = 'size' and size_option_id is not null and sweetness_option_id is null)
      or (kind = 'sweetness' and sweetness_option_id is not null and size_option_id is null))
);
create index order_customizations_size_idx on public.order_item_customizations(size_option_id);
create index order_customizations_sweetness_idx on public.order_item_customizations(sweetness_option_id);
create table public.order_status_history (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete restrict,
  from_status public.order_status,
  to_status public.order_status not null,
  actor_id uuid references auth.users(id) on delete restrict,
  actor_kind text not null check(actor_kind in ('guest','staff','system')),
  guest_session_id uuid references private.guest_sessions(id) on delete restrict,
  reason text check (length(reason) <= 500),
  changed_at timestamptz not null default clock_timestamp(),
  check ((actor_kind='staff' and actor_id is not null and guest_session_id is null)
    or (actor_kind='guest' and actor_id is null and guest_session_id is not null)
    or (actor_kind='system' and actor_id is null and guest_session_id is null))
);
create index order_history_order_idx on public.order_status_history(order_id, id);
create index order_history_actor_idx on public.order_status_history(actor_id);
create index order_history_guest_idx on public.order_status_history(guest_session_id);
create index user_roles_grantor_idx on public.user_roles(granted_by);

create table public.order_refunds (
  order_id uuid primary key references public.orders(id) on delete restrict,
  required_amount numeric(14,2) not null check(required_amount >= 0),
  status text not null default 'Pending' check(status in ('Pending','Recorded','Waived')),
  recorded_amount numeric(14,2) check(recorded_amount >= 0),
  cancellation_reason text not null,
  cancelled_by uuid not null references auth.users(id) on delete restrict,
  resolved_by uuid references auth.users(id) on delete restrict,
  resolution_reason text check(length(btrim(resolution_reason)) between 1 and 500),
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  check ((status='Pending' and recorded_amount is null and resolved_by is null and resolved_at is null and resolution_reason is null)
    or (status='Recorded' and recorded_amount=required_amount and resolved_by is not null and resolved_at is not null and resolution_reason is not null)
    or (status='Waived' and recorded_amount=0 and resolved_by is not null and resolved_at is not null and resolution_reason is not null))
);
create index refund_cancelled_by_idx on public.order_refunds(cancelled_by);
create index refund_resolved_by_idx on public.order_refunds(resolved_by);

-- Revoke Supabase public-schema defaults explicitly, then whitelist later.
do $$ declare t text; begin
  foreach t in array array['categories','products','product_sizes','product_sweetness_options',
    'product_images','cafe_tables','user_roles','daily_queue_counters','orders',
    'order_items','order_item_customizations','order_status_history','order_refunds'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated, service_role', t);
  end loop;
end $$;
revoke all on sequence public.order_status_history_id_seq from public, anon, authenticated, service_role;
alter table private.security_settings enable row level security;
alter table private.guest_sessions enable row level security;
alter table private.request_events enable row level security;
revoke all on all tables in schema private from public, anon, authenticated, service_role, earvins_guest_server, earvins_maintenance;
revoke all on all sequences in schema private from public, anon, authenticated, service_role, earvins_guest_server, earvins_maintenance;
commit;
