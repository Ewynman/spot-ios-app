/*
  Wipe all objects from Supabase Storage buckets used by Spot.

  Why this exists:
    The Supabase database has a guard trigger that prevents direct
    DELETE FROM storage.objects, so the database wipe leaves the
    binary files in storage untouched. This script clears them via
    the supported Storage API using the service_role key.

  Usage:
    cd Mock
    npm install
    export SUPABASE_URL="https://<project-ref>.supabase.co"
    export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
    node wipe-storage.js
*/

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const BUCKETS = ['avatars', 'spots'];
const PAGE_SIZE = 1000;

async function listAllPaths(bucket, prefix = '') {
  const collected = [];
  let offset = 0;
  while (true) {
    const { data, error } = await supabase.storage.from(bucket).list(prefix, {
      limit: PAGE_SIZE,
      offset,
      sortBy: { column: 'name', order: 'asc' }
    });
    if (error) throw error;
    if (!data || data.length === 0) break;

    for (const entry of data) {
      const fullPath = prefix ? `${prefix}/${entry.name}` : entry.name;
      // Folders show up as entries with a null id in supabase-js v2.
      if (entry.id == null) {
        const nested = await listAllPaths(bucket, fullPath);
        collected.push(...nested);
      } else {
        collected.push(fullPath);
      }
    }

    if (data.length < PAGE_SIZE) break;
    offset += data.length;
  }
  return collected;
}

async function wipeBucket(bucket) {
  console.log(`Listing ${bucket}...`);
  const paths = await listAllPaths(bucket);
  if (paths.length === 0) {
    console.log(`  ${bucket}: already empty.`);
    return;
  }
  console.log(`  ${bucket}: removing ${paths.length} objects...`);
  for (let i = 0; i < paths.length; i += 100) {
    const chunk = paths.slice(i, i + 100);
    const { error } = await supabase.storage.from(bucket).remove(chunk);
    if (error) {
      console.error(`  remove failed at offset ${i}:`, error);
      throw error;
    }
  }
  console.log(`  ${bucket}: done.`);
}

(async () => {
  for (const bucket of BUCKETS) {
    try {
      await wipeBucket(bucket);
    } catch (err) {
      console.error(`Bucket ${bucket} failed:`, err.message ?? err);
      process.exitCode = 1;
    }
  }
  console.log('Storage wipe complete.');
})();
