// Local-only PostgreSQL smoke tests. Does not load .env or connect to any server.
// Dependency is deliberately installed under ignored tmp/ rather than the app.
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const dependencyRoot = resolve(root, process.argv[2] || 'tmp/schema-tools');
const require = createRequire(import.meta.url);
const modulePath = require.resolve('@electric-sql/pglite', { paths: [dependencyRoot] });
const { PGlite } = await import(pathToFileURL(modulePath).href);
const db = new PGlite();
try {
  // Supabase Auth stand-ins ONLY in this in-memory database; no Auth users created.
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create table auth.users (id uuid primary key, is_anonymous boolean not null default false);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
    $$;
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
    $$;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text not null,metadata jsonb default '{}',unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant usage on schema public, auth to anon, authenticated;
    grant usage on schema storage to anon, authenticated;
    grant select,insert,update,delete on storage.objects to anon,authenticated;
    grant execute on function auth.uid() to anon, authenticated;
    grant execute on function auth.jwt() to anon, authenticated;
  `);
  const files = (await readdir(resolve(root, 'supabase/migrations')))
    .filter(file => file.endsWith('.sql')).sort();
  for (const file of files) {
    await db.exec(await readFile(resolve(root, 'supabase/migrations', file), 'utf8'));
    console.log(`PASS migration: ${file}`);
  }
  await db.exec(await readFile(resolve(root, 'supabase/tests/schema_security.sql'), 'utf8'));
  console.log('PASS local guest, limits, MFA, pricing, idempotency, QR, cancellation, refund, expiry, Storage and retention tests');
  await db.exec('commit; set role earvins_guest_server;');
  await db.exec("select private.create_guest_session(sha256('queued-guest'::bytea),sha256('queued-ip'::bytea));");
  const statement = key => `select id,queue_number from private.place_order(
    sha256('queued-guest'::bytea),pg_temp.qr(),
    '80000000-0000-0000-0000-${String(key).padStart(12, '0')}',
    '[{"product_id":"20000000-0000-0000-0000-000000000002","quantity":1}]',sha256('queued-ip'::bytea));`;
  const retries = await Promise.all(Array.from({ length: 20 }, () => db.query(statement(1))));
  if (new Set(retries.map(result => result.rows[0].id)).size !== 1) throw new Error('Queued retries duplicated an order');
  const unique = await Promise.all(Array.from({ length: 20 }, (_, index) => db.query(statement(index + 2))));
  if (new Set(unique.map(result => result.rows[0].queue_number)).size !== 20) throw new Error('Queued submissions duplicated queue numbers');
  await db.exec('reset role;');
  const counts = await db.query("select count(*)::integer n from public.orders where guest_session_id=(select id from private.guest_sessions where token_hash=sha256('queued-guest'::bytea))");
  if (counts.rows[0].n !== 21) throw new Error('Queued request count mismatch');
  console.log('PASS 20 queued idempotent retries -> 1 order; 20 queued distinct requests -> 20 unique queue numbers');
  console.log('LIMITATION: PGlite serializes connections; these are not independent PostgreSQL writer sessions.');
  console.log('No network database connection, environment variables, or production data were used.');
} catch (error) {
  console.error(`FAIL local database validation: ${error.message}; SQLSTATE=${error.code || 'unknown'}; position=${error.position || error.internalPosition || 'unknown'}`);
  if (error.where) console.error(error.where);
  process.exitCode = 1;
} finally {
  await db.exec('rollback');
  await db.close();
}
