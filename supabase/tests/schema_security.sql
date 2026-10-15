-- DISPOSABLE LOCAL DATABASE ONLY. Synthetic Auth rows are not real accounts.
begin;
create function pg_temp.assert_ok(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %',label;end if;end $$;
create function pg_temp.expect_error(statement text,expected_state text) returns void language plpgsql as $$
declare caught boolean:=false;
begin begin execute statement;exception when others then
  if sqlstate<>expected_state then raise exception 'Expected %, got %: %',expected_state,sqlstate,sqlerrm;end if;caught:=true;end;
  if not caught then raise exception 'Expected rejection: %',statement;end if;
end $$;
insert into auth.users(id,is_anonymous) values
 ('00000000-0000-0000-0000-000000000003',false),('00000000-0000-0000-0000-000000000004',false);
insert into public.user_roles(user_id,role) values
 ('00000000-0000-0000-0000-000000000003','cafe_admin'),('00000000-0000-0000-0000-000000000004','developer');
insert into public.categories(id,slug,name) values('10000000-0000-0000-0000-000000000001','coffee','Coffee');
insert into public.products(id,slug,category_id,name,base_price) values
 ('20000000-0000-0000-0000-000000000001','coffee','10000000-0000-0000-0000-000000000001','Test Coffee',120),
 ('20000000-0000-0000-0000-000000000002','bread','10000000-0000-0000-0000-000000000001','Test Bread',90);
insert into public.product_sizes(id,product_id,label,price) values('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','16oz',120);
insert into public.product_sweetness_options(id,product_id,label) values('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Original');
insert into public.cafe_tables(id,table_number) values('50000000-0000-0000-0000-000000000001',5);
-- Deterministic access helpers keep test credentials and generated IDs out of output.
create function pg_temp.submit(key_suffix integer,guest_name text default 'guest-a',extra jsonb default null) returns public.orders language plpgsql as $$
declare q uuid; body jsonb;
begin
  -- Test-only QR fixture accessor is granted below. Production callers cannot enumerate.
  q:=pg_temp.qr(); body:=coalesce(extra,'[{"product_id":"20000000-0000-0000-0000-000000000002","quantity":1}]'::jsonb);
  return private.place_order(sha256(convert_to(guest_name,'UTF8')),q,('70000000-0000-0000-0000-'||lpad(key_suffix::text,12,'0'))::uuid,body,sha256('test-ip'::bytea));
end $$;
create function pg_temp.qr() returns uuid language sql security definer set search_path='' as $$select qr_identifier from public.cafe_tables where table_number=5$$;
create function pg_temp.order_id(n integer) returns uuid language sql security definer set search_path='' as $$select id from public.orders where queue_number=n order by created_at limit 1$$;
create function pg_temp.guest_hash(n text) returns bytea language sql as $$select sha256(convert_to(n,'UTF8'))$$;

select pg_temp.assert_ok((select count(*)=16 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','private') and c.relkind='r' and c.relrowsecurity),'all 16 application tables RLS');
select pg_temp.assert_ok((select enum_range(null::public.order_status)::text='{"Pending Payment",Preparing,"Ready for Pickup",Completed,Cancelled}'),'exact five order statuses');
select pg_temp.assert_ok(not has_function_privilege('anon','private.place_order(bytea,uuid,uuid,jsonb,bytea,boolean)','EXECUTE'),'anon cannot create orders');
select pg_temp.assert_ok(not has_function_privilege('authenticated','private.place_order(bytea,uuid,uuid,jsonb,bytea,boolean)','EXECUTE'),'authenticated browser cannot create orders');
select pg_temp.assert_ok(not has_table_privilege('earvins_guest_server','public.orders','SELECT'),'guest server has no raw order table grant');
select pg_temp.assert_ok(not has_table_privilege('authenticated','public.orders','UPDATE'),'no direct order updates');
select pg_temp.assert_ok(not has_table_privilege('authenticated','public.user_roles','INSERT'),'no self-promotion');
select pg_temp.assert_ok(not has_table_privilege('authenticated','public.products','DELETE'),'no product deletion');
select pg_temp.assert_ok((select count(*)=0 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef),'no privileged public RPC implementation');

set local role anon;
select pg_temp.assert_ok((select count(*)=2 from public.products),'public menu readable');
select pg_temp.expect_error('select * from public.orders','42501');
select pg_temp.expect_error('select private.read_guest_order(sha256(''x''::bytea),null)','42501');
select pg_temp.expect_error('select private.create_guest_session(sha256(''x''::bytea),sha256(''ip''::bytea))','42501');
reset role;
set local role earvins_guest_server;
select private.create_guest_session(pg_temp.guest_hash('guest-a'),sha256('test-ip'::bytea));
select private.create_guest_session(pg_temp.guest_hash('guest-b'),sha256('test-ip'::bytea));
select pg_temp.expect_error('select * from private.guest_sessions','42501');
select pg_temp.expect_error('select pg_temp.submit(1,''invalid-guest'')','42501');
select pg_temp.submit(1,'guest-a','[{"product_id":"20000000-0000-0000-0000-000000000001","quantity":2,"size_option_id":"30000000-0000-0000-0000-000000000001","sweetness_option_id":"40000000-0000-0000-0000-000000000001","note":"More ice"}]');
select pg_temp.assert_ok((private.read_guest_order(pg_temp.guest_hash('guest-a'),pg_temp.order_id(1))->>'total')::numeric=240,'database prices');
select pg_temp.expect_error('select private.read_guest_order(pg_temp.guest_hash(''guest-b''),pg_temp.order_id(1))','42501');
select pg_temp.expect_error('select pg_temp.submit(1,''guest-a'')','22023');
select pg_temp.expect_error($q$select pg_temp.submit(99,'guest-a','[{"product_id":"20000000-0000-0000-0000-000000000002","quantity":1,"price":0}]')$q$,'22023');
select pg_temp.expect_error($q$select pg_temp.submit(99,'guest-a','[{"product_id":"20000000-0000-0000-0000-000000000002","quantity":1,"size_option_id":"30000000-0000-0000-0000-000000000001"}]')$q$,'22023');
select pg_temp.submit(2);
select pg_temp.expect_error('select pg_temp.submit(3)','P0001');
select pg_temp.assert_ok((pg_temp.submit(2)).queue_number=2,'retry bypasses unpaid allowance');
reset role;
select pg_temp.assert_ok((select count(*)=2 from private.request_events where kind='order'),'retries create no new allowance events');
update public.cafe_tables set is_active=false where table_number=5;
set local role earvins_guest_server;
select pg_temp.expect_error('select pg_temp.submit(99,''guest-b'')','22023');
select pg_temp.assert_ok((pg_temp.submit(2)).queue_number=2,'existing retry survives table deactivation');
reset role;
update public.cafe_tables set is_active=true where table_number=5;
-- An authenticated browser with no staff membership still cannot read guest orders.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000099',true);
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
set local role authenticated;
select pg_temp.assert_ok((select count(*)=0 from public.orders),'browser cannot read any guest order');
select pg_temp.expect_error('update public.orders set total_amount=0','42501');
reset role;

-- MFA restrictions apply equally to staff and developer.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
select pg_temp.assert_ok(not private.is_staff(),'staff without MFA denied');
select pg_temp.expect_error('select public.transition_order(pg_temp.order_id(1),''Pending Payment'',''Preparing'')','42501');
reset role;
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
set local role authenticated;
select pg_temp.assert_ok(private.is_staff() and not private.is_developer(),'MFA cafe admin');
select pg_temp.expect_error($q$insert into public.products(slug,category_id,name,base_price) values('bad','10000000-0000-0000-0000-000000000001','Bad',10)$q$,'42501');
select pg_temp.expect_error('delete from public.products','42501');
select pg_temp.expect_error($q$insert into public.cafe_tables(table_number,qr_identifier) values(6,'60000000-0000-0000-0000-000000000001')$q$,'42501');
select pg_temp.expect_error('update public.cafe_tables set qr_identifier=gen_random_uuid()','42501');
insert into public.cafe_tables(table_number) values(6);
select set_config('earvins_test.previous_qr',(select qr_identifier::text from public.cafe_tables where table_number=6),true);
select pg_temp.assert_ok(public.rotate_table_qr((select id from public.cafe_tables where table_number=6))<>current_setting('earvins_test.previous_qr')::uuid,'guarded QR rotation creates a new identifier');
select pg_temp.assert_ok((select count(*)=0 from public.resolve_table_qr(current_setting('earvins_test.previous_qr')::uuid)),'old QR invalid after rotation');
update public.products set name='Edited Coffee',base_price=999,is_archived=true where slug='coffee';
update public.product_sizes set label='New Label',price=888 where id='30000000-0000-0000-0000-000000000001';
select pg_temp.assert_ok((select product_name_snapshot='Test Coffee' and unit_price=120 and line_total=240 from public.order_items where order_id=pg_temp.order_id(1)),'historical prices/name retained');
select pg_temp.assert_ok((select label_snapshot='16oz' and price_snapshot=120 from public.order_item_customizations where kind='size' and order_item_id in(select id from public.order_items where order_id=pg_temp.order_id(1))),'size snapshot retained');
select pg_temp.expect_error('select public.transition_order(pg_temp.order_id(1),''Pending Payment'',''Completed'')','23514');
select public.transition_order(pg_temp.order_id(1),'Pending Payment','Preparing');
select pg_temp.assert_ok((select payment_confirmed_by=auth.uid() and payment_confirmed_at is not null from public.orders where id=pg_temp.order_id(1)),'payment actor/time');
select pg_temp.expect_error('select public.transition_order(pg_temp.order_id(1),''Pending Payment'',''Preparing'')','40001');
select pg_temp.expect_error('select public.transition_order(pg_temp.order_id(1),''Preparing'',''Cancelled'',''Paid cancellation'')','42501');
select public.transition_order(pg_temp.order_id(2),'Pending Payment','Cancelled','Customer cancelled');
select pg_temp.expect_error('select public.transition_order(pg_temp.order_id(2),''Cancelled'',''Preparing'')','23514');
reset role;
select pg_temp.assert_ok((select cancellation_actor='staff' and cancelled_by is not null from public.orders where id=pg_temp.order_id(2)),'cancellation identity and reason');
select pg_temp.assert_ok((select count(*)=0 from public.order_refunds),'unpaid cancellation has no refund');

-- Paid cancellation and manual cash refund require extra capabilities.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
select set_config('request.jwt.claims','{"aal":"aal1"}',true);
set local role authenticated;
select pg_temp.expect_error($q$insert into public.products(slug,category_id,name,base_price) values('no-mfa','10000000-0000-0000-0000-000000000001','No MFA',10)$q$,'42501');
reset role;
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
set local role authenticated;
insert into public.products(slug,category_id,name,base_price) values('developer-added','10000000-0000-0000-0000-000000000001','Added',100);
reset role;
update public.user_roles set can_cancel_paid=true where user_id='00000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select public.transition_order(pg_temp.order_id(1),'Preparing','Cancelled','Manager approved cash refund');
select pg_temp.assert_ok((select status='Pending' and required_amount=240 and recorded_amount is null from public.order_refunds),'paid cancellation records pending refund only');
select pg_temp.expect_error('select public.record_manual_refund(pg_temp.order_id(1),240,''Missing refund capability'')','42501');
reset role;
update public.user_roles set can_record_refund=true where user_id='00000000-0000-0000-0000-000000000003';
set local role authenticated;
select pg_temp.expect_error('select public.record_manual_refund(pg_temp.order_id(1),0,''Only developer may waive'',true)','42501');
select pg_temp.expect_error('select public.record_manual_refund(pg_temp.order_id(1),1,''Incorrect amount'')','22023');
select public.record_manual_refund(pg_temp.order_id(1),240,'Cash physically returned at counter');
select pg_temp.expect_error('select public.record_manual_refund(pg_temp.order_id(1),240,''Duplicate'')','22023');
select pg_temp.assert_ok((select status='Recorded' and recorded_amount=240 and resolved_by=auth.uid() from public.order_refunds),'manual refund responsible staff');
reset role;

-- Database minute/hour limits. Tests raise unpaid cap only locally.
update private.security_settings set guest_unpaid_limit=100;
set local role earvins_guest_server;
select pg_temp.submit(3);
select pg_temp.expect_error('select pg_temp.submit(4)','P0001');
reset role;
update private.security_settings set guest_per_minute=1000,guest_per_hour=3;
set local role earvins_guest_server;
select pg_temp.expect_error('select pg_temp.submit(4)','P0001');
reset role;
update private.security_settings set guest_per_hour=10000,ip_challenge_per_minute=1;
set local role earvins_guest_server;
select pg_temp.expect_error('select pg_temp.submit(4)','P0001');
select private.place_order(pg_temp.guest_hash('guest-a'),pg_temp.qr(),'70000000-0000-0000-0000-000000000004',
 '[{"product_id":"20000000-0000-0000-0000-000000000002","quantity":1}]',sha256('test-ip'::bytea),true);
reset role;
select pg_temp.assert_ok((select max(queue_number)=4 from public.orders),'cancelled queue numbers retained');
update private.security_settings set ip_challenge_per_minute=1000,table_challenge_per_minute=1;
set local role earvins_guest_server;
select pg_temp.expect_error('select pg_temp.submit(5)','P0001');
reset role;
update private.security_settings set table_challenge_per_minute=1000;
update private.guest_sessions set expires_at=created_at+interval '1 second',created_at=created_at-interval '2 days' where token_hash=pg_temp.guest_hash('guest-b');
-- Explicitly put expiry in the past while satisfying expiry > created_at.
update private.guest_sessions set expires_at=clock_timestamp()-interval '1 day' where token_hash=pg_temp.guest_hash('guest-b');
set local role earvins_guest_server;
select pg_temp.expect_error('select private.read_guest_order(pg_temp.guest_hash(''guest-b''),pg_temp.order_id(1))','42501');
reset role;

-- Expiry is opt-in; holds protect customers already paying. No cron installed.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select set_config('request.jwt.claims','{"aal":"aal2"}',true);
set local role authenticated;
select public.hold_counter_payment(pg_temp.order_id(3),10);
reset role;
-- Test-only trigger suspension changes expiry timestamps; never a runtime grant.
alter table public.orders disable trigger order_guard;
update public.orders set unpaid_expires_at=clock_timestamp()-interval '1 minute' where status='Pending Payment';
alter table public.orders enable trigger order_guard;
select set_config('request.jwt.claim.sub','',true);select set_config('request.jwt.claims','{}',true);
set local role earvins_maintenance;
select pg_temp.assert_ok(private.expire_unpaid_orders()=0,'expiry disabled by default');
reset role;
update private.security_settings set unpaid_expiry_enabled=true;
set local role earvins_maintenance;
select pg_temp.assert_ok(private.expire_unpaid_orders()=1,'only unheld unpaid order expires');
reset role;
select pg_temp.assert_ok((select status='Pending Payment' from public.orders where id=pg_temp.order_id(3)),'counter hold protected');
select pg_temp.assert_ok((select status='Cancelled' and cancellation_actor='system' from public.orders where id=pg_temp.order_id(4)),'expiry system audit actor');
select pg_temp.assert_ok((select count(*)=0 from public.orders where status='Cancelled' and cancellation_reason is null),'cancel reasons always recorded');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);select set_config('request.jwt.claims','{"aal":"aal2"}',true);
set local role authenticated;
select public.transition_order(pg_temp.order_id(3),'Pending Payment','Preparing');
select public.transition_order(pg_temp.order_id(3),'Preparing','Ready for Pickup');
select public.transition_order(pg_temp.order_id(3),'Ready for Pickup','Completed');
select pg_temp.expect_error('select public.transition_order(pg_temp.order_id(3),''Completed'',''Cancelled'',''Terminal status'')','23514');
reset role;

-- Storage policy simulation; actual Storage API/MIME handling needs staging.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);select set_config('request.jwt.claims','{"aal":"aal2"}',true);
set local role authenticated;
insert into public.product_images(product_id,storage_path) values('20000000-0000-0000-0000-000000000002','products/20000000-0000-0000-0000-000000000002/main.webp');
insert into storage.objects(bucket_id,name) values('earvins-product-images','products/20000000-0000-0000-0000-000000000002/main.webp');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select pg_temp.expect_error($q$insert into public.product_images(product_id,storage_path) values('20000000-0000-0000-0000-000000000001','products/20000000-0000-0000-0000-000000000001/main.webp')$q$,'42501');
select pg_temp.expect_error($q$insert into storage.objects(bucket_id,name) values('earvins-product-images','new-object.webp')$q$,'42501');
update storage.objects set metadata='{"replacement":true}' where bucket_id='earvins-product-images';
select pg_temp.assert_ok((select count(*)=1 from storage.objects where metadata->>'replacement'='true'),'staff replaces existing image');
reset role;
-- Even an unrelated broad permissive policy cannot open the protected bucket.
create policy test_broad on storage.objects for all to anon,authenticated using(true) with check(true);
select set_config('request.jwt.claim.sub','',true);select set_config('request.jwt.claims','{}',true);
set local role anon;
select pg_temp.assert_ok((select count(*)=1 from storage.objects),'published image public-readable through private bucket policy');
select pg_temp.expect_error($q$insert into storage.objects(bucket_id,name) values('earvins-product-images','attacker.webp')$q$,'42501');
delete from storage.objects where bucket_id='earvins-product-images';
select pg_temp.assert_ok((select count(*)=1 from storage.objects),'restrictive delete guard');
reset role;
update public.products set is_archived=true where slug='bread';
set local role anon;
select pg_temp.assert_ok((select count(*)=0 from storage.objects),'archived image not published');
reset role;
update public.products set is_archived=false where slug='bread';

-- Midnight clock is replaced ONLY in this local test transaction.
create or replace function private.queue_clock() returns timestamptz language sql volatile set search_path='' as $$
 select coalesce(nullif(current_setting('earvins_test.clock',true),'')::timestamptz,clock_timestamp()); $$;
select set_config('earvins_test.clock','2030-01-01 15:59:59+00',true);
select pg_temp.assert_ok((select business_date='2030-01-01' and queue_number=1 from private.allocate_queue()),'before Manila midnight');
select set_config('earvins_test.clock','2030-01-01 16:00:00+00',true);
select pg_temp.assert_ok((select business_date='2030-01-02' and queue_number=1 from private.allocate_queue()),'new Manila day starts at one');
select pg_temp.assert_ok((select count(*)=2 from public.daily_queue_counters where business_date in('2030-01-01','2030-01-02')),'previous day retained');
select set_config('earvins_test.clock','',true);
-- Restore the exact production clock before tests complete.
create or replace function private.queue_clock() returns timestamptz language sql volatile set search_path='' as $$select clock_timestamp()$$;

-- Hash cleanup preserves all guest/order/refund history and live tokens.
update private.guest_sessions set created_at=clock_timestamp()-interval '60 days',expires_at=clock_timestamp()-interval '40 days' where token_hash=pg_temp.guest_hash('guest-b');
set local role earvins_maintenance;
select pg_temp.assert_ok(private.clean_expired_guest_tokens()=1,'expired hash erased');
reset role;
select pg_temp.assert_ok((select count(*)=4 from public.orders),'history retained');
select pg_temp.assert_ok((select count(*)=1 from public.order_refunds),'refund evidence retained');
-- Live revocation and database snapshot guards are tested independently of UI.
update public.user_roles set is_active=false where user_id='00000000-0000-0000-0000-000000000003';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);select set_config('request.jwt.claims','{"aal":"aal2"}',true);
set local role authenticated;
select pg_temp.expect_error('select public.rotate_table_qr(''50000000-0000-0000-0000-000000000001'')','42501');
reset role;
select pg_temp.expect_error('update public.order_items set unit_price=1','42501');
select pg_temp.expect_error('delete from public.orders','42501');
-- Leave fixture transaction open for the runner's queued parallel-call checks;
-- the runner rolls everything back afterward, even on failure.
