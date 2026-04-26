/*
  Quick Supabase seeder for Spot (DEV/TEST only)

  Usage:
    cd Mock
    npm install
    export SUPABASE_URL="https://<project-ref>.supabase.co"
    export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
    node seed.js --users 10 --spots 20

  Optional:
    --userIds <comma-separated-uuid-list>   # force specific users
    --users 10                              # number of existing public.users to target
    --spots 20                              # spots per user (unless spotsMin/spotsMax set)
    --spotsMin 3 --spotsMax 12              # random range per user
    --dryRun 1                              # print plan, do not insert

  Notes:
    - Requires service role key (bypasses RLS).
    - Uses existing rows in public.users. It does NOT create auth users.
    - Inserts into public.spots and public.spot_images.
*/

const { createClient } = require('@supabase/supabase-js');
const { randomUUID } = require('node:crypto');

const args = process.argv.slice(2);
function getArg(name, def) {
  const i = args.indexOf(`--${name}`);
  if (i >= 0 && args[i + 1]) return args[i + 1];
  return def;
}
const NUM_USERS = Number(getArg('users', 8));
const SPOTS_PER_USER = Number(getArg('spots', 12));
const SPOTS_MIN = getArg('spotsMin', null);
const SPOTS_MAX = getArg('spotsMax', null);
const PRO_USERS = Number(getArg('proUsers', 0));
const IMAGES_MIN = Number(getArg('imagesMin', 1));
const IMAGES_MAX = Number(getArg('imagesMax', 3));
const USER_IDS_ARG = getArg('userIds', '');
const DRY_RUN = getArg('dryRun', '0') === '1';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}
if (SUPABASE_SERVICE_ROLE_KEY.startsWith('sb_publishable_')) {
  console.error('SUPABASE_SERVICE_ROLE_KEY is using a publishable key. Use the service_role key from Supabase project settings.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const vibeTags = [
  'Chill Spot','Hidden Gem','Scenic View','Romantic','Great For Photos','Family Friendly','Nature Escape','Foodie Heaven','Beach Day','Late Night','Historical','People Watching','Quiet Moment','Cozy Corner','Pet Friendly','Adventure','Waterfront','Study Spot'
];

const cities = [
  { name: 'Miami Beach, FL', lat: 25.7907, lon: -80.1300 },
  { name: 'New York, NY', lat: 40.7128, lon: -74.0060 },
  { name: 'Los Angeles, CA', lat: 34.0522, lon: -118.2437 },
  { name: 'San Francisco, CA', lat: 37.7749, lon: -122.4194 },
  { name: 'Austin, TX', lat: 30.2672, lon: -97.7431 },
];

function randInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function pick(arr) { return arr[randInt(0, arr.length - 1)]; }
function username(i) {
  const names = ['alex','sam','jordan','morgan','taylor','chris','casey','riley','jamie','kyle','jules','dev','river','remi','bailey'];
  return `${pick(names)}_${i}_${randInt(100,999)}`;
}
function shuffle(array) {
  const out = [...array];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}
async function loadTargetUsers() {
  if (USER_IDS_ARG.trim().length > 0) {
    const ids = USER_IDS_ARG
      .split(',')
      .map(s => s.trim())
      .filter(Boolean);
    const { data, error } = await supabase
      .from('users')
      .select('id,username,profile_image_url,is_private')
      .in('id', ids);
    if (error) throw error;
    return data ?? [];
  }

  const { data, error } = await supabase
    .from('users')
    .select('id,username,profile_image_url,is_private')
    .order('created_at', { ascending: false })
    .limit(NUM_USERS);
  if (error) throw error;
  const current = data ?? [];
  if (current.length >= NUM_USERS || DRY_RUN) return current;

  const needed = NUM_USERS - current.length;
  console.log(`Creating ${needed} mock users in auth.users + public.users...`);
  const nowISO = new Date().toISOString();
  const newProfiles = [];
  for (let idx = 0; idx < needed; idx++) {
    const i = idx + 1;
    const uname = username(i);
    const email = `${uname}.${Date.now()}.${i}@mock.spot`;
    const isPrivate = Math.random() < 0.18;
    const avatar = `https://i.pravatar.cc/150?img=${randInt(1,70)}`;

    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email,
      password: `MockPass!${randInt(100000, 999999)}`,
      email_confirm: true,
      user_metadata: {
        username: uname,
        is_private: isPrivate,
        profile_image_url: avatar
      }
    });
    if (createErr) throw createErr;
    if (!created?.user?.id) {
      throw new Error(`Auth user create returned no id for ${email}`);
    }

    newProfiles.push({
      id: created.user.id,
      email,
      email_verified: true,
      username: uname,
      username_lower: uname.toLowerCase(),
      profile_image_url: avatar,
      is_private: isPrivate,
      is_pro: false,
      pro_until: null,
      last_active_at: nowISO,
      locale: 'en_US',
      created_at: nowISO
    });
  }

  if (newProfiles.length > 0) {
    const { error: upsertErr } = await supabase
      .from('users')
      .upsert(newProfiles, { onConflict: 'id' });
    if (upsertErr) throw upsertErr;
  }

  const { data: refreshed, error: refreshedErr } = await supabase
    .from('users')
    .select('id,username,profile_image_url,is_private')
    .order('created_at', { ascending: false })
    .limit(NUM_USERS);
  if (refreshedErr) throw refreshedErr;
  return refreshed ?? current;
}

function jitter(n, amt = 0.02) {
  return n + (Math.random() - 0.5) * amt;
}

async function ensureVibeTagIds() {
  const lowers = vibeTags.map(v => v.toLowerCase());
  const { data: existing, error: existingErr } = await supabase
    .from('vibe_tags')
    .select('id,name_lower')
    .in('name_lower', lowers);
  if (existingErr) throw existingErr;

  const have = new Set((existing ?? []).map(r => r.name_lower));
  const missing = vibeTags.filter(v => !have.has(v.toLowerCase()));
  if (missing.length > 0) {
    const rows = missing.map(name => ({ name, name_lower: name.toLowerCase() }));
    const { error: insertErr } = await supabase
      .from('vibe_tags')
      .insert(rows);
    if (insertErr) throw insertErr;
  }

  const { data: allTags, error: allErr } = await supabase
    .from('vibe_tags')
    .select('id,name,name_lower')
    .in('name_lower', lowers);
  if (allErr) throw allErr;

  const byName = {};
  for (const row of allTags ?? []) {
    byName[row.name] = row.id;
    if (!byName[row.name] && row.name_lower) {
      const pretty = vibeTags.find(v => v.toLowerCase() === row.name_lower);
      if (pretty) byName[pretty] = row.id;
    }
  }
  return byName;
}

async function createSpotDoc(user, idx, vibeTagIdByName) {
  const city = pick(cities);
  const vibe = pick(vibeTags);
  const vibeTagId = vibeTagIdByName[vibe];
  if (!vibeTagId) {
    throw new Error(`Missing vibe_tag id for ${vibe}`);
  }

  const id = randomUUID();
  const seed = `${id.slice(0,6)}${idx}`;
  const imageCount = randInt(
    Math.max(1, IMAGES_MIN),
    Math.max(Math.max(1, IMAGES_MIN), IMAGES_MAX)
  );
  const imageURLs = [
    `https://picsum.photos/seed/${seed}/1200/800`,
    `https://picsum.photos/seed/${seed}b/1200/800`,
    `https://picsum.photos/seed/${seed}c/1200/800`,
    `https://picsum.photos/seed/${seed}d/1200/800`,
    `https://picsum.photos/seed/${seed}e/1200/800`
  ].slice(0, imageCount);

  const spotInsert = {
    id,
    user_id: user.id,
    vibe_tag_id: vibeTagId,
    caption: '',
    latitude: jitter(city.lat, 0.08),
    longitude: jitter(city.lon, 0.08),
    location_name: city.name || 'Unknown Location',
    likes_count: randInt(0, 500),
    author_is_private_snapshot: !!user.is_private,
    created_at: new Date(Date.now() - randInt(0, 1000 * 60 * 60 * 24 * 60)).toISOString()
  };

  const imageRows = imageURLs.map((url, sortIndex) => ({
    spot_id: id,
    storage_path: url,
    public_url: url,
    sort_index: sortIndex
  }));

  if (DRY_RUN) {
    return { spotInsert, imageRows };
  }

  const { error: spotErr } = await supabase
    .from('spots')
    .insert(spotInsert);
  if (spotErr) throw spotErr;

  const { error: imageErr } = await supabase
    .from('spot_images')
    .insert(imageRows);
  if (imageErr) throw imageErr;
}

async function main() {
  console.log(`\nSeeding Supabase with fake spots...`);
  const users = await loadTargetUsers();
  if (users.length === 0) {
    console.error('No users found in public.users and auto-create failed.');
    process.exit(1);
  }
  console.log(`Using ${users.length} users`);

  if (PRO_USERS > 0) {
    const selectedProUsers = shuffle(users).slice(0, Math.min(PRO_USERS, users.length));
    const proUserIds = selectedProUsers.map(u => u.id);
    const proUntil = new Date(Date.now() + 1000 * 60 * 60 * 24 * 365).toISOString();
    if (!DRY_RUN && proUserIds.length > 0) {
      const { error: proErr } = await supabase
        .from('users')
        .update({ is_pro: true, pro_until: proUntil })
        .in('id', proUserIds);
      if (proErr) throw proErr;
    }
    console.log(`Marked ${proUserIds.length} users as Pro`);
  }

  const vibeTagIdByName = await ensureVibeTagIds();
  let inserted = 0;

  for (const u of users) {
    const count = (SPOTS_MIN !== null && SPOTS_MAX !== null)
      ? randInt(Number(SPOTS_MIN), Number(SPOTS_MAX))
      : SPOTS_PER_USER;
    for (let s = 0; s < count; s++) {
      await createSpotDoc(u, s + 1, vibeTagIdByName);
      inserted += 1;
      if (inserted % 25 === 0) {
        console.log(`...${inserted} spots seeded`);
      }
    }
  }
  console.log(`Done. Seeded ${inserted} spots${DRY_RUN ? ' (dry run)' : ''}.`);
}

main().catch(err => { console.error(err); process.exit(1); });


