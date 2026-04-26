/*
  Supabase seeder for Spot (DEV/TEST only)

  Defaults are tuned for a full synthetic load test:
    - 500 mock users
    - 50 private users (deterministic random pick)
    - 200 pro users (deterministic random pick, may overlap with private)
    - 1-15 spots per user
    - 1-3 images per spot
    - Locations sampled from ~60 cities across every populated continent

  Usage:
    cd Mock
    npm install
    export SUPABASE_URL="https://<project-ref>.supabase.co"
    export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
    node seed.js

  Common flags:
    --users 500                # number of public.users rows to create
    --privateUsers 50          # how many of those should be is_private = true
    --proUsers 200             # how many of those should be is_pro = true
    --spotsMin 1 --spotsMax 15 # spots-per-user range (inclusive)
    --imagesMin 1 --imagesMax 3
    --userIds <csv>            # reuse existing user ids (skips user creation)
    --skipUsers 1              # don't create users, only seed spots for existing ones
    --dryRun 1                 # log a plan, don't write

  Notes:
    - Service role key is required (bypasses RLS).
    - This seeder does NOT create rows in auth.users. The Spot app's data plane
      (public.users, public.spots, ...) does not have FKs to auth.users, so for
      synthetic load testing we only populate the public schema. Real signups
      still create auth users via the normal flow.
    - Inserts are batched for speed.
*/

const { createClient } = require('@supabase/supabase-js');
const { randomUUID } = require('node:crypto');

const args = process.argv.slice(2);
function getArg(name, def) {
  const i = args.indexOf(`--${name}`);
  if (i >= 0 && args[i + 1] !== undefined) return args[i + 1];
  return def;
}
const NUM_USERS = Number(getArg('users', 500));
const PRIVATE_USERS = Number(getArg('privateUsers', 50));
const PRO_USERS = Number(getArg('proUsers', 200));
const SPOTS_MIN = Number(getArg('spotsMin', 1));
const SPOTS_MAX = Number(getArg('spotsMax', 15));
const IMAGES_MIN = Number(getArg('imagesMin', 1));
const IMAGES_MAX = Number(getArg('imagesMax', 3));
const USER_IDS_ARG = getArg('userIds', '');
const SKIP_USERS = getArg('skipUsers', '0') === '1';
const DRY_RUN = getArg('dryRun', '0') === '1';
const BATCH_SIZE = Number(getArg('batchSize', 500));

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}
if (SUPABASE_SERVICE_ROLE_KEY.startsWith('sb_publishable_')) {
  console.error('SUPABASE_SERVICE_ROLE_KEY is a publishable key. Use the service_role key from project settings.');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

const vibeTags = [
  'Chill Spot', 'Hidden Gem', 'Scenic View', 'Romantic', 'Great For Photos',
  'Family Friendly', 'Nature Escape', 'Foodie Heaven', 'Beach Day', 'Late Night',
  'Historical', 'People Watching', 'Quiet Moment', 'Cozy Corner', 'Pet Friendly',
  'Adventure', 'Waterfront', 'Study Spot', 'Nightlife', 'Sunset Spot'
];

// Curated cities spanning all populated continents. Lat/lon will be jittered
// per-spot so a user's posts spread out around their picked city.
const cities = [
  // North America
  { name: 'New York, NY, USA', lat: 40.7128, lon: -74.0060 },
  { name: 'Los Angeles, CA, USA', lat: 34.0522, lon: -118.2437 },
  { name: 'San Francisco, CA, USA', lat: 37.7749, lon: -122.4194 },
  { name: 'Chicago, IL, USA', lat: 41.8781, lon: -87.6298 },
  { name: 'Miami, FL, USA', lat: 25.7617, lon: -80.1918 },
  { name: 'Austin, TX, USA', lat: 30.2672, lon: -97.7431 },
  { name: 'Seattle, WA, USA', lat: 47.6062, lon: -122.3321 },
  { name: 'Toronto, ON, Canada', lat: 43.6532, lon: -79.3832 },
  { name: 'Vancouver, BC, Canada', lat: 49.2827, lon: -123.1207 },
  { name: 'Mexico City, Mexico', lat: 19.4326, lon: -99.1332 },
  { name: 'Havana, Cuba', lat: 23.1136, lon: -82.3666 },
  // South America
  { name: 'Rio de Janeiro, Brazil', lat: -22.9068, lon: -43.1729 },
  { name: 'São Paulo, Brazil', lat: -23.5505, lon: -46.6333 },
  { name: 'Buenos Aires, Argentina', lat: -34.6037, lon: -58.3816 },
  { name: 'Lima, Peru', lat: -12.0464, lon: -77.0428 },
  { name: 'Bogotá, Colombia', lat: 4.7110, lon: -74.0721 },
  { name: 'Santiago, Chile', lat: -33.4489, lon: -70.6693 },
  { name: 'Quito, Ecuador', lat: -0.1807, lon: -78.4678 },
  // Europe
  { name: 'London, UK', lat: 51.5074, lon: -0.1278 },
  { name: 'Paris, France', lat: 48.8566, lon: 2.3522 },
  { name: 'Barcelona, Spain', lat: 41.3851, lon: 2.1734 },
  { name: 'Madrid, Spain', lat: 40.4168, lon: -3.7038 },
  { name: 'Lisbon, Portugal', lat: 38.7223, lon: -9.1393 },
  { name: 'Rome, Italy', lat: 41.9028, lon: 12.4964 },
  { name: 'Berlin, Germany', lat: 52.5200, lon: 13.4050 },
  { name: 'Amsterdam, Netherlands', lat: 52.3676, lon: 4.9041 },
  { name: 'Copenhagen, Denmark', lat: 55.6761, lon: 12.5683 },
  { name: 'Stockholm, Sweden', lat: 59.3293, lon: 18.0686 },
  { name: 'Oslo, Norway', lat: 59.9139, lon: 10.7522 },
  { name: 'Reykjavík, Iceland', lat: 64.1466, lon: -21.9426 },
  { name: 'Vienna, Austria', lat: 48.2082, lon: 16.3738 },
  { name: 'Prague, Czechia', lat: 50.0755, lon: 14.4378 },
  { name: 'Athens, Greece', lat: 37.9838, lon: 23.7275 },
  { name: 'Istanbul, Turkey', lat: 41.0082, lon: 28.9784 },
  { name: 'Dublin, Ireland', lat: 53.3498, lon: -6.2603 },
  // Africa
  { name: 'Cairo, Egypt', lat: 30.0444, lon: 31.2357 },
  { name: 'Cape Town, South Africa', lat: -33.9249, lon: 18.4241 },
  { name: 'Marrakesh, Morocco', lat: 31.6295, lon: -7.9811 },
  { name: 'Lagos, Nigeria', lat: 6.5244, lon: 3.3792 },
  { name: 'Nairobi, Kenya', lat: -1.2921, lon: 36.8219 },
  { name: 'Addis Ababa, Ethiopia', lat: 9.0320, lon: 38.7469 },
  { name: 'Accra, Ghana', lat: 5.6037, lon: -0.1870 },
  // Middle East
  { name: 'Dubai, UAE', lat: 25.2048, lon: 55.2708 },
  { name: 'Tel Aviv, Israel', lat: 32.0853, lon: 34.7818 },
  { name: 'Doha, Qatar', lat: 25.2854, lon: 51.5310 },
  { name: 'Beirut, Lebanon', lat: 33.8938, lon: 35.5018 },
  // Asia
  { name: 'Tokyo, Japan', lat: 35.6762, lon: 139.6503 },
  { name: 'Kyoto, Japan', lat: 35.0116, lon: 135.7681 },
  { name: 'Seoul, South Korea', lat: 37.5665, lon: 126.9780 },
  { name: 'Beijing, China', lat: 39.9042, lon: 116.4074 },
  { name: 'Shanghai, China', lat: 31.2304, lon: 121.4737 },
  { name: 'Hong Kong', lat: 22.3193, lon: 114.1694 },
  { name: 'Taipei, Taiwan', lat: 25.0330, lon: 121.5654 },
  { name: 'Bangkok, Thailand', lat: 13.7563, lon: 100.5018 },
  { name: 'Singapore', lat: 1.3521, lon: 103.8198 },
  { name: 'Bali, Indonesia', lat: -8.4095, lon: 115.1889 },
  { name: 'Ho Chi Minh City, Vietnam', lat: 10.8231, lon: 106.6297 },
  { name: 'Mumbai, India', lat: 19.0760, lon: 72.8777 },
  { name: 'Delhi, India', lat: 28.7041, lon: 77.1025 },
  { name: 'Kathmandu, Nepal', lat: 27.7172, lon: 85.3240 },
  // Oceania
  { name: 'Sydney, Australia', lat: -33.8688, lon: 151.2093 },
  { name: 'Melbourne, Australia', lat: -37.8136, lon: 144.9631 },
  { name: 'Auckland, New Zealand', lat: -36.8485, lon: 174.7633 },
  { name: 'Queenstown, New Zealand', lat: -45.0312, lon: 168.6626 },
  { name: 'Honolulu, HI, USA', lat: 21.3099, lon: -157.8581 }
];

function randInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function pick(arr) { return arr[randInt(0, arr.length - 1)]; }
function shuffle(array) {
  const out = [...array];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

function makeUsername(i) {
  const handles = [
    'alex', 'sam', 'jordan', 'morgan', 'taylor', 'chris', 'casey', 'riley',
    'jamie', 'kyle', 'jules', 'dev', 'river', 'remi', 'bailey', 'quinn',
    'parker', 'avery', 'rowan', 'sage', 'nova', 'reese', 'hayden', 'ari'
  ];
  return `${pick(handles)}_${String(i).padStart(4, '0')}_${randInt(100, 999)}`;
}

async function chunkInsert(table, rows, conflict = null) {
  if (DRY_RUN) {
    console.log(`[dryRun] would insert ${rows.length} rows into ${table}`);
    return;
  }
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const chunk = rows.slice(i, i + BATCH_SIZE);
    const q = supabase.from(table);
    const { error } = conflict
      ? await q.upsert(chunk, { onConflict: conflict })
      : await q.insert(chunk);
    if (error) {
      console.error(`Insert into ${table} failed at offset ${i}:`, error);
      throw error;
    }
  }
}

async function ensureVibeTags() {
  const lowers = vibeTags.map(v => v.toLowerCase());
  const { data: existing, error } = await supabase
    .from('vibe_tags')
    .select('id,name,name_lower')
    .in('name_lower', lowers);
  if (error) throw error;
  const have = new Set((existing ?? []).map(r => r.name_lower));
  const missing = vibeTags.filter(v => !have.has(v.toLowerCase()));
  if (missing.length > 0 && !DRY_RUN) {
    const rows = missing.map(name => ({ name, name_lower: name.toLowerCase() }));
    const { error: insertErr } = await supabase.from('vibe_tags').insert(rows);
    if (insertErr) throw insertErr;
  }
  const { data: all, error: allErr } = await supabase
    .from('vibe_tags')
    .select('id,name,name_lower')
    .in('name_lower', lowers);
  if (allErr) throw allErr;
  return all ?? [];
}

async function loadExistingUsers() {
  if (USER_IDS_ARG.trim().length > 0) {
    const ids = USER_IDS_ARG.split(',').map(s => s.trim()).filter(Boolean);
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
  return data ?? [];
}

async function createMockUsers() {
  if (PRIVATE_USERS > NUM_USERS) {
    throw new Error(`privateUsers (${PRIVATE_USERS}) > users (${NUM_USERS})`);
  }
  if (PRO_USERS > NUM_USERS) {
    throw new Error(`proUsers (${PRO_USERS}) > users (${NUM_USERS})`);
  }

  const usedNames = new Set();
  const profiles = [];
  for (let i = 1; i <= NUM_USERS; i++) {
    let uname;
    do { uname = makeUsername(i); } while (usedNames.has(uname.toLowerCase()));
    usedNames.add(uname.toLowerCase());
    profiles.push({
      id: randomUUID(),
      uname
    });
  }

  const indices = profiles.map((_, idx) => idx);
  const privateIdx = new Set(shuffle(indices).slice(0, PRIVATE_USERS));
  const proIdx = new Set(shuffle(indices).slice(0, PRO_USERS));

  const nowISO = new Date().toISOString();
  const proUntil = new Date(Date.now() + 1000 * 60 * 60 * 24 * 365).toISOString();

  const rows = profiles.map((p, idx) => {
    const isPrivate = privateIdx.has(idx);
    const isPro = proIdx.has(idx);
    return {
      id: p.id,
      email: `${p.uname.toLowerCase()}@mock.spot`,
      email_verified: true,
      username: p.uname,
      username_lower: p.uname.toLowerCase(),
      profile_image_url: `https://i.pravatar.cc/300?img=${1 + (idx % 70)}`,
      is_private: isPrivate,
      is_pro: isPro,
      pro_until: isPro ? proUntil : null,
      last_active_at: nowISO,
      locale: 'en_US',
      created_at: new Date(Date.now() - randInt(0, 1000 * 60 * 60 * 24 * 90)).toISOString()
    };
  });

  await chunkInsert('users', rows);
  console.log(`Created ${rows.length} users (${PRIVATE_USERS} private, ${PRO_USERS} pro).`);
  return rows.map(r => ({
    id: r.id,
    username: r.username,
    profile_image_url: r.profile_image_url,
    is_private: r.is_private
  }));
}

function jitter(n, amt = 0.12) {
  return n + (Math.random() - 0.5) * amt;
}

function spotRow(user, idx, vibeId) {
  const city = pick(cities);
  const id = randomUUID();
  const createdAt = new Date(Date.now() - randInt(0, 1000 * 60 * 60 * 24 * 60)).toISOString();
  return {
    id,
    user_id: user.id,
    vibe_tag_id: vibeId,
    caption: '',
    latitude: jitter(city.lat, 0.16),
    longitude: jitter(city.lon, 0.16),
    location_name: city.name,
    likes_count: randInt(0, 500),
    saves_count: randInt(0, 100),
    author_is_private_snapshot: !!user.is_private,
    created_at: createdAt
  };
}

function imageRowsForSpot(spotId) {
  const count = randInt(Math.max(1, IMAGES_MIN), Math.max(IMAGES_MIN, IMAGES_MAX));
  const seedBase = spotId.replaceAll('-', '').slice(0, 10);
  const out = [];
  for (let i = 0; i < count; i++) {
    const url = `https://picsum.photos/seed/${seedBase}${i}/1200/800`;
    out.push({
      spot_id: spotId,
      storage_path: url,
      public_url: url,
      sort_index: i
    });
  }
  return out;
}

async function seedSpots(users, vibeIds) {
  const spotInserts = [];
  const imageInserts = [];

  for (const user of users) {
    const count = randInt(Math.max(1, SPOTS_MIN), Math.max(SPOTS_MIN, SPOTS_MAX));
    for (let i = 0; i < count; i++) {
      const vibeId = pick(vibeIds);
      const spot = spotRow(user, i, vibeId);
      spotInserts.push(spot);
      imageInserts.push(...imageRowsForSpot(spot.id));
    }
  }

  console.log(`Planned ${spotInserts.length} spots and ${imageInserts.length} images.`);
  await chunkInsert('spots', spotInserts);
  await chunkInsert('spot_images', imageInserts);
}

async function main() {
  console.log(`Seeding Spot via ${SUPABASE_URL}`);
  console.log(`  users=${NUM_USERS}, private=${PRIVATE_USERS}, pro=${PRO_USERS}`);
  console.log(`  spots/user=${SPOTS_MIN}-${SPOTS_MAX}, images/spot=${IMAGES_MIN}-${IMAGES_MAX}`);
  if (DRY_RUN) console.log('  [DRY RUN — no writes]');

  const vibeRows = await ensureVibeTags();
  if (vibeRows.length === 0) {
    throw new Error('No vibe tags available');
  }
  const vibeIds = vibeRows.map(v => v.id);

  let users;
  if (SKIP_USERS || USER_IDS_ARG.trim().length > 0) {
    users = await loadExistingUsers();
    console.log(`Reusing ${users.length} existing users.`);
  } else {
    users = await createMockUsers();
  }

  if (users.length === 0) {
    console.error('No users to seed spots for.');
    process.exit(1);
  }

  await seedSpots(users, vibeIds);
  console.log('Done.');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
