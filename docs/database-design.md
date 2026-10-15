# Phase 3B corrected database and security design

LOCAL DRAFTS ONLY. Nothing here has been applied to hosted Supabase. No Auth accounts, remote tables, bucket, role logins, credentials, schedules, backend handlers or UI changes are created by preparing these files. These drafts replace the earlier **unapplied** drafts; do not run them on a database that already has the old objects. No Git writes are performed.

## Architecture and table inventory

The design uses 13 public application tables and three private operational tables (16 application tables total), plus Supabase's existing Auth/Storage tables:

| Table | Purpose and access |
| --- | --- |
| public.categories | Active category reads for visitors; MFA developer insertion/editing. |
| public.products | Nonarchived catalog reads; MFA staff edit/archive/restore/availability; only MFA developer INSERT; no application DELETE. |
| public.product_sizes | Active size labels/full prices; staff edit/add/deactivate sizes on an existing product. |
| public.product_sweetness_options | Active free sweetness choices; staff edit/add/deactivate choices on an existing product. |
| public.product_images | One developer-created fixed object slot per product; public metadata for published products, staff alt-text edit and Storage replacement. |
| public.cafe_tables | Staff add/edit/deactivate; database-generated UUID QR; rotation only through a guarded operation. No public enumeration or direct identifier editing. |
| public.user_roles | Permanent staff/developer memberships and optional paid-cancellation/refund capabilities; self/developer reads, trusted operator writes only. |
| public.orders | Guest-session owner, immutable table/price/date/queue snapshots, idempotency body, unpaid deadline, payment hold, staff payment/cancellation evidence. |
| public.order_items | Immutable product-name/unit-price/quantity/note snapshots and generated line total. |
| public.order_item_customizations | Immutable selected size/sweetness ID, label and price snapshots. |
| public.daily_queue_counters | One retained row per Manila date. No client/server-role table grants; internal allocation only. |
| public.order_status_history | Append-only guest/staff/system actor, previous/next status and cancellation reason. |
| public.order_refunds | Full cash-refund requirement after paid cancellation; Pending/Recorded/Waived refund tracking, amount, responsible staff, reason/time. These are refund attributes, not extra order statuses. |
| private.guest_sessions | SHA-256 token hash, expiry/revocation, opaque owner UUID. No browser/API table access. |
| private.security_settings | Singleton configurable quotas, TTLs, challenge thresholds and opt-in expiry. Trusted operator updates only. |
| private.request_events | Bounded short-lived IP-HMAC/guest/table event history for database quota/challenge checks. |

All application tables have RLS enabled. Public-schema defaults are explicitly revoked and runtime operations whitelisted. No direct guest SELECT/INSERT/UPDATE/DELETE grants exist on orders or private tables. Staff order reads require MFA; mutations use guarded functions. Snapshots/history cannot be edited or deleted by application accounts. FK delete restrictions and indexes protect relationships and lookup performance. Product/option/café-table deletion is disabled: archive/deactivate instead. Prices use exact `numeric` PHP amounts.

## Guest checkout: no customer account or login

Customers have no `auth.users` rows. `orders.guest_session_id` references a private guest record, not Supabase Auth. Only staff/developer use Auth. No anonymous Auth sign-in is needed or should be enabled for this design.

The future Next.js server must generate a token with `crypto.randomBytes(32)` and SHA-256 hash the raw bytes. It sends **only the 32-byte hash** to `private.create_guest_session`. The plaintext token goes only in a production cookie such as:

```
__Host-earvins_guest=<base64url token>; Secure; HttpOnly; SameSite=Lax; Path=/
```

Omit Domain. Align cookie Max-Age/Expires with the database expiry (default seven days); do not silently renew expired sessions or rotate away an owner's only access token. Local HTTP development may use a clearly separate unprefixed development cookie; production must require HTTPS and the flags above. Never log a token, hash, cookie, Authorization header, DB connection string or full request body. A token hash is also a sensitive bearer capability inside the trusted server/DB channel, so it must never appear in browser responses or public schema rows.

Each server request decodes the fixed-length cookie, hashes it, and invokes a scoped guest function. `private.require_guest` locks the matching session, checks expiry/revocation, and resolves ownership. `private.read_guest_order(hash, order_uuid)` additionally checks that order's owner. QR identifiers, sequential table numbers and order IDs alone never authorize order access. The curated response omits raw QR/request, staff UUIDs, token hashes and internal session IDs.

Refresh retains access through the cookie. During a temporary disconnect, keep the same locally persisted idempotency UUID and exact submitted item body; retry only after connection returns, with the same cookie. Do not store the guest token in localStorage, URL parameters or IndexedDB. A client may cache its nonsensitive cart/request for retry, but server pricing always wins. Guest access expires after the documented TTL; missing/expired cookies require counter assistance for old orders, not a lookup by queue number alone. No unapproved cross-device recovery or indefinite session renewal is implemented.

### Scoped server connection

The migration defines NOLOGIN, NOINHERIT, NOBYPASSRLS roles `earvins_guest_server` and `earvins_maintenance`; it does not create credentials. The future backend requires a private PostgreSQL connection using a separately provisioned login allowed to SET ROLE only to the needed scoped role. The guest login must never inherit/authenticate as `postgres`, `authenticated`, `service_role` or maintenance. Revoke unneeded role memberships and audit provisioning. The maintenance login is separate from the web application.

The browser Supabase client/publishable key has **no guest session creation, order creation or guest order-read RPC**. These functions exist only in `private`, are not exposed in the Data API, and grant EXECUTE only to the scoped server role. That role has no direct application-table rights. No service-role key is needed for the guest path. Fixed-search-path SECURITY DEFINER functions validate ownership and inputs; privileged implementations remain private. Public staff/table RPC wrappers use SECURITY INVOKER and delegate to checked private implementations. Keep `private` outside all exposed schemas.

Future server APIs must validate Origin/Host against an allowlist, defend CSRF (including cookie-backed POSTs), set private/no-store responses, avoid shared caching, enforce JSON content type and a request size limit (proposed 32 KiB), and reject unsupported fields before DB work. Parse/verify actual staff JWTs rather than copying untrusted claims to a database connection. For PostgREST staff calls use the user's JWT; never let a browser set `request.jwt.claims` via a SQL endpoint. With pooled dedicated guest connections, use transaction-scoped role setup/reset; no guest identity is stored in session GUCs. No application server implementation is included in this database-only phase.

## Configurable abuse prevention

`private.security_settings` defaults:

| Policy | Default | Outcome |
| --- | --- | --- |
| New orders per guest / rolling minute | 3 | Temporary guest allowance error |
| New orders per guest / rolling hour | 10 | Temporary guest allowance error |
| Active Pending Payment orders per guest | 2 | Pay/cancel existing unpaid orders before submitting more |
| New orders per IP-HMAC / minute | 30 | Require a verified CAPTCHA, not a permanent IP ban |
| New orders per table / minute | 15 | Require a verified CAPTCHA, not a permanent table ban |
| New guest sessions per IP-HMAC / hour | 120 | Require a verified CAPTCHA; supports shared café Wi-Fi |
| Guest session lifetime | 7 days | Expired sessions cannot read/place orders |
| Request-event retention | 2 hours | Maintenance removes old operational events only |

Successful new-order counts derive from committed orders. A session row lock serializes each guest's new submissions and retries. IP advisory locks and table row locks serialize shared-threshold decisions. A matching idempotent retry returns the existing order **before** new-order quotas/QR activity checks; it creates no new order, queue allocation or rate event. It still requires a valid unexpired guest session. Same key/different body is rejected. An expired session does not gain access simply by replaying a key.

The future server must calculate IP HMACs with a separate server-only secret, using only the verified reverse proxy source address (never an arbitrary X-Forwarded-For supplied by the browser). Roaming to another IP does not invalidate the guest cookie. Rotating the IP HMAC secret changes buckets; plan that operationally. No raw IP address is stored in this schema.

`p_challenge_verified` is a **trusted server attestation**, never a browser boolean. The future server verifies CAPTCHA provider responses server-side (hostname/action, expiry, one-use replay prevention and binding to guest/table/action) before passing true. Challenge success bypasses IP/table soft thresholds only; guest hard limits remain. Provide Retry-After and human-readable messages such as “Please pay for or cancel an existing unpaid order at the counter.” Avoid permanent exclusion based only on shared Wi-Fi.

Rejected transactions roll back their DB event writes. Therefore, add a shared ingress limiter for **all attempts**, including invalid QR/cookie/JSON requests, before opening a database transaction. Proposed defaults: challenge at 60 requests/IP/minute, brief capped backoff only for sustained automated traffic, individual guest/cart bounds, and an accessible counter-assisted path. Configure real proxy connection/statement/lock timeouts and a bounded connection pool to limit lock-wait resource exhaustion. Database checks already protect new orders even if future server code omits its limiter; browser clients cannot bypass the server to invoke guest functions. CAPTCHA integration and the all-attempt ingress limiter remain future backend work and production gates.

## Catalog authorization and MFA

`private.is_staff` requires an active permanent Auth user membership **and a verified JWT `aal2` claim**. `is_developer` adds the developer role. Missing/aal1 tokens cannot perform privileged database or Storage operations, even for a developer. Browser-editable user metadata is not used for authority. Both role activity and capabilities are read from the database for each operation; a new request after revocation fails. Public menu reads remain available without MFA.

Café admins may edit existing names/descriptions/categories/prices/options, availability and archive flags; add sizes/sweetness to an existing product; replace an existing image; add/deactivate/renumber tables and rotate QR codes through the guarded operation. They cannot INSERT a product, create its first image slot, permanently DELETE products, assign roles, alter order snapshots or edit QR identifiers directly. Only MFA developers can INSERT products/categories/image slots. The shared PostgreSQL authenticated role has grants needed by these operations, but RLS restricts which app members may use them. Protected ID/slug/QR/path/order columns have no browser UPDATE grant.

Role provisioning: a trusted project owner later invites a permanent developer through verified Auth admin tooling, verifies the Auth UUID, enrolls MFA, then inserts an active developer membership using a reviewed operator session. Invite café staff individually, verify UUIDs/MFA, and grant only cafe_admin. Paid-cancellation/refund capabilities default false; grant them explicitly to designated managers. Developers have these capabilities through their role. No automatic bootstrap RPC, fixed production UUIDs, password or role assignment from customer requests is provided. Log all operator membership/capability grants and revocations. Test actual JWT AAL2 and recovery procedures on staging before launch.

## Table QR security

The database defaults `qr_identifier` to `gen_random_uuid()`. Staff INSERT grants include only table_number/is_active; supplying id/qr_identifier is denied. Staff UPDATE grants omit QR identifiers. `rotate_table_qr(table_id)` checks MFA staff authority, generates a fresh UUID internally and accepts no replacement token argument. Old identifiers stop resolving/creating new orders; old order snapshots and legitimate idempotent retries remain accessible to their owner.

`resolve_table_qr` exposes only the number for one known active random QR. The trusted order function checks/locks the actual active table. An image of a valid static QR can still be shared; possession is a table locator, not proof of physical presence. Rate challenges, staff counter-payment checks and optional later on-site controls address that residual risk. Do not revert production URLs to trusting `?table=5`.

## Five order statuses, cancellation, payment and refunds

The enum remains exactly Pending Payment, Preparing, Ready for Pickup, Completed, Cancelled. New orders start Pending Payment. Permitted transitions are:

| From | Allowed next |
| --- | --- |
| Pending Payment | Preparing (staff confirms actual counter payment), Cancelled |
| Preparing | Ready for Pickup, Cancelled with extra paid-cancellation authority |
| Ready for Pickup | Completed after collection at counter, Cancelled with extra paid-cancellation authority |
| Completed | None |
| Cancelled | None |

Staff transitions require MFA, expected-state checking and a locked order. Database triggers enforce the transition graph and immutable fields as a second layer. Payment confirmation records database time/staff UUID. Cancellation records actor kind, staff UUID (or system), and nonempty reason. A changed expected state returns `40001`; invalid transition `23514`; authorization `42501`; malformed request/idempotency conflict `22023`; quotas/challenge `P0001`. Future server responses must map these to safe messages without database details.

Unpaid cancellation is allowed for MFA café staff. Paid cancellation additionally requires developer or `can_cancel_paid`. It preserves payment evidence and creates one `order_refunds` row with full required order total and Pending refund status. This records a responsibility, **not a transfer of money**. A developer or MFA manager with `can_record_refund` may call `record_manual_refund` only after physically returning the full cash amount, providing a reason. The record stores amount, responsible person and time. A developer may explicitly waive it with a reason; zero recorded amount and Waived status remain auditable. Finalized records cannot be resolved twice through the RPC, and browser roles have no direct refund mutation grants.

Proposed default is **full refunds only**; partial/multiple refunds are intentionally not implemented. Refunds are separate attributes, not a sixth order status. Orders remain Cancelled in history regardless of unresolved refund responsibility. Automatic payments/refunds, accounting reconciliation and online payment APIs are absent. Confirm full-refund/waiver policy and authorized staff before enabling paid cancellation in production.

### Unpaid expiry and counter holds

Every order records a proposed deadline (default 30 minutes). Automatic expiry is **disabled by default**, has no installed scheduler, and must not be enabled until customer messaging is implemented and approved. Proposed message before checkout/confirmation: “Please pay at the counter within 30 minutes. If you are already paying, ask staff to hold your order.” Display the server-provided deadline/hold. On expiry: “Your unpaid order expired. Please speak to counter staff or place a new order.” Do not show a deadline as enforced while the worker is disabled; future API messaging must use the effective configuration.

`hold_counter_payment` lets MFA staff place/extend a 1–15 minute hold (default 10) when a customer reaches the counter. `expire_unpaid_orders` is maintenance-only, bounded, locks eligible rows with SKIP LOCKED and rechecks status/deadline/hold in the trigger. It never cancels paid/preparing orders and never processes refunds. Concurrent payment/hold and expiry serialize on the same order row. If expiry wins before staff acquired the row, payment fails with stale state; staff must check status **before accepting cash**, assist the customer, and create a fresh order if needed rather than resurrecting Cancelled. Cancellation/expiry never frees its queue number. No scheduled job is created now.

## Queues, midnight and snapshots

`private.allocate_queue` acquires a dedicated transaction advisory lock **before** reading its internal real clock. It then derives `(timestamp at time zone 'Asia/Manila')::date` and performs an atomic INSERT ... ON CONFLICT UPDATE increment. Unique `(business_date,queue_number)` is a second defense. A new date starts at 1; old counters/orders remain. The global allocation lock lasts until commit, so date selection cannot be based on a time read before waiting for another allocation. Catalog/session/table checks precede allocation; keep transactions short and do not perform network calls while holding locks.

The defined date is allocation time after lock acquisition, not commit time; a commit just after midnight can retain an allocation made just before midnight. This is deliberate and documented. Production does not accept a client date or read test settings. Numbers display with minimum three digits and grow beyond 999; they never wrap. Failed transactions roll back together; committed cancellations never decrement counters.

Per-guest row locks plus unique `(guest_session_id,idempotency_key)` serialize retries. JSONB equality includes table and exact submitted option/line representation; retain the same original body/key for offline retries. Different keys are different intentional orders and consume quotas. Product parent locks and option-parent write triggers stabilize prices and choices; snapshots are written in the same transaction. Product edits/archives and table changes do not rewrite old order prices, names, table number or customization details.

## Product-image Storage policies

Migration 003 prepares a **private** `earvins-product-images` bucket with 1 MiB limit and image/webp allowlist. Customers may use the Storage authenticated-download API with public/anonymous read policy or a future server streaming endpoint for published images; the unconditional `/object/public/` route is intentionally unavailable. Verify the chosen public/publishable-key download flow on staging. Avoid public signed URLs that outlive archive/removal visibility changes.

Developer creates a fixed slot `products/<product UUID>/main.webp` in product_images, then uploads the first image. Staff may replace only an existing object with that exact associated path, using Storage **update**, not upsert (upsert requires INSERT). Staff cannot INSERT a new object or create an image association for a new product. Direct object deletion is denied to app roles. Product path metadata cannot be edited by staff. A helper checks an existing target during UPDATE, preventing a rename into a nonexistent new slot. Restrictive per-command policies keep this bucket protected even if another broad permissive policy exists, while not changing other buckets.

The future upload handler must decode actual image bytes, verify dimensions/file signature, reject SVG/HTML/animated or malformed uploads as appropriate, strip metadata, and encode a safe WebP derivative. MIME labels and file extensions alone are insufficient. Copy derivatives from original real café assets; never modify original references. Storage database-row tests do not verify actual object bytes, API upsert semantics, CDN cache behavior or file deletion. No cleanup removes objects/metadata automatically. Replacements may require version/cache handling at the server/client later without changing the underlying authorized slot.

## Retention and privacy defaults

Guest sessions expire after seven days; expired token hashes are erased after an additional 30 days by a separately invoked maintenance cleanup. Session IDs referenced by orders remain as pseudonymous records. The maintenance operation does not delete any guest/order/item/customization/history/refund row. Request IP-HMAC events may be removed after two hours (configurable 2–24 hours). These hashes are pseudonymous data and need an approved privacy notice/retention policy.

`order_retention` defaults NULL: indefinite preservation pending an approved accounting/privacy policy. Setting a future retention interval does **not** authorize or perform deletion; no financial-history deletion function/schedule exists. Legal retention duration, backups, access review, guest-session recovery and later irreversible anonymization require explicit owner approval and a separate reviewed migration. Do not delete Auth staff identities referenced by financial history; deactivate access instead.

## Existing menu and first catalog initialization

No production seed is included: src/lib/menu.ts labels prices as demonstrations. Review the actual intended catalog before importing. Preserve seven categories in current order: Coffee, Non-coffee, Pastries, Sandwiches, Pasta, Meals, Add-ons. Retain mock slugs while generating stable UUID import mappings. Review 16oz/22oz full-price sizes and Original/Less Sweet/Sweeter choices. Do not import browser mock orders/queues or silently overwrite existing rows.

| Existing slug | Demo PHP prices to approve | Real source filename |
| --- | --- | --- |
| vietnamese-coffee | 120; sizes 120/150 | iced vietnamese latte - grab.png |
| iced-latte | 120; sizes 120/150 | iced latte.jpg |
| iced-matcha | 140; sizes 140/150 | Iced matcha latte from Earvin_s Brew.png |
| ube-milk | 130; Sold Out | ube milk.png |
| croissant | 90 | butter croissant.png |
| blueberry-muffin | 95 | blueberry muffin.png |
| ham-sandwich | 150 | grilled ham and cheese.png |
| tuna-sandwich | 150 | tuna sandwich.png |

The developer/operator runs a separately reviewed transactional import, validates option/category completeness and creates image slots before authorized uploads. Review initial production tables and production QR origin separately. UI remains mock-based and unchanged; customer images remain Menu-only and admin thumbnails remain permitted.

## Local tests, Supabase-specific gates and rollback

Apply order (only after later approval): 001 schema, 002 permissions/workflow, 003 Storage. Each is transactional. Fresh object/role/schema/bucket names and the managed Supabase Auth/Storage schema are preconditions. Inspect existing objects/default grants before approval; do not use IF NOT EXISTS to hide conflicts. No role login/password or database link is configured here.

Run local tests without .env or network DB access:

```powershell
npm install --prefix tmp/schema-tools --no-save --package-lock=false @electric-sql/pglite
node scripts/validate-database-schema.mjs
```

PGlite runs the exact migrations and tests against synthetic Auth/Storage interfaces. Tests cover all-table RLS/grants, guest ownership/expiry, blocked browser submission, server-role table denial, quota/idempotency, real catalog pricing, option ownership, immutable snapshots, database-only QR identifiers/rotation, AAL1/AAL2 staff/developer differences, paid/unpaid cancellation, manual refund tracking, expiry opt-in/counter holds, public/unauthorized Storage operations even with a broad policy, history preservation and expired hash cleanup. Midnight tests replace the internal clock **only in the test database**, allocate on either side of Manila midnight, verify both days start at 1 and preserve the prior day, then restore the production clock.

The runner additionally submits 20 parallel JS retry calls and 20 distinct calls against PGlite, checking one retry order and distinct queues. **PGlite queues work on one PostgreSQL session**: this is useful request replay coverage, not proof of real independent-writer concurrency. No local Docker/PostgreSQL binary was available during preparation. Before production, use an isolated local Supabase/staging database to test 100 independent sessions, same-key and different-key races, per-guest limits, table/IP challenges, repricing/archive/option edits, counter holds/payment versus expiry, and an allocation blocked across midnight. Check deadlock/lock-timeout behavior and retry the original key/body with bounded backoff; never retry staff transitions blindly.

Supabase-specific validation remains mandatory: real JWT signature/AAL2, Auth permanent-user flags, PostgREST wrappers/schema-cache behavior and direct unauthorized HTTP calls; actual Storage downloads/updates/upserts and bucket file validation; existing role inheritance/default privileges and migration-role ability to create NOLOGIN roles/policies; private schema exposure; dedicated login/SET ROLE handling through the chosen direct/session/transaction pooler; real distributed ingress/CAPTCHA/proxy identity; Realtime subscription privacy if later enabled; private/no-store cache behavior. Fake local Auth rows do not create or test actual Auth accounts. No Realtime publication or scheduler is enabled.

Application checks: run lint, typecheck and production build. Frontend mock tests remain applicable but do not exercise this unconnected backend. No UI change should be needed in this draft phase.

Rollback: back up before any later approved deployment. A failed migration rolls back that file; a failure after 001 leaves RLS-enabled runtime-denied tables. No destructive down migration is provided. Recreate only a known disposable local database for repeated tests. Once real orders exist, prefer feature-disable plus forward repair; never drop/truncate orders, history, refunds or counters. Restore a backup to a separate recovery project and reconcile newer cash/orders before any reviewed cutover.

## Documented defaults and remaining approvals

- Seven-day guest access, 30-day expired-token-hash retention, two-hour IP-event retention; no history deletion. Confirm privacy/accounting retention and expired-session support policy.
- 30-minute unpaid expiry is proposed but disabled. Enable only after messaging, counter hold training, scheduler authority and race tests are approved.
- Full paid-order refunds only; developer may explicitly waive with a reason. Grant extra capabilities only to designated MFA managers; no automatic refunds.
- Initial shared-IP/table thresholds trigger CAPTCHA, never permanent Wi-Fi exclusion. Tune using café traffic and provide staff assistance.
- A dedicated server PostgreSQL login and shared ingress limiter/CAPTCHA are deployment/backend prerequisites, not implemented live here. Do not use a generic service-role browser client as a shortcut.
- Fixed WebP derivatives simplify safe replacement. Approve the upload conversion/cache plan; original files remain untouched.
- Minimum three-digit queues expand beyond 999. Allocation date is read after the global allocation lock, not at HTTP start or commit.

References: [Supabase functions](https://supabase.com/docs/guides/database/functions), [RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [MFA](https://supabase.com/docs/guides/auth/auth-mfa), [Storage access control](https://supabase.com/docs/guides/storage/security/access-control), [PostgreSQL INSERT](https://www.postgresql.org/docs/current/sql-insert.html).
