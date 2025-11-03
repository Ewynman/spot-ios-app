/*
  Quick Firestore seeder for Spot (DEV/TEST only)

  Usage:
    cd Mock
    npm init -y && npm i firebase-admin
    export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/serviceAccountKey.json
    node seed.js --users 10 --spots 20

  Notes:
    - This uses Firebase Admin SDK (bypasses security rules) to write directly to Firestore.
    - It creates fake users in the 'users' collection and corresponding 'spots' documents.
    - No Firebase Auth accounts are created; these are profile docs only.
*/

const admin = require('firebase-admin');

try {
  admin.initializeApp();
} catch (_) {
  // ignore reinit in watch mode
}
const db = admin.firestore();

const args = process.argv.slice(2);
function getArg(name, def) {
  const i = args.indexOf(`--${name}`);
  if (i >= 0 && args[i + 1]) return Number(args[i + 1]);
  return def;
}
const NUM_USERS = getArg('users', 8);
const SPOTS_PER_USER = getArg('spots', 12);
const SPOTS_MIN = getArg('spotsMin', null);
const SPOTS_MAX = getArg('spotsMax', null);

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

async function createUserDoc(i) {
  const uid = `mock_${i}_${Date.now()}`;
  const isPrivate = Math.random() < 0.15;
  const isPro = Math.random() < 0.4;
  const uname = username(i);
  const profileImageURL = `https://i.pravatar.cc/150?img=${randInt(1,70)}`;
  const vibeStats = {};
  vibeTags.forEach(tag => (vibeStats[tag] = randInt(0, 7)));
  const doc = {
    username: uname,
    username_lower: uname.toLowerCase(),
    email: `${uname}@example.com`,
    profileImageURL,
    isPrivate,
    isPro,
    isVerified: true,
    following: [],
    requestedFollows: [],
    blockedUsers: [],
    likedSpots: [],
    bookmarkedSpots: [],
    vibeStats,
    createdAt: admin.firestore.Timestamp.now(),
  };
  await db.collection('users').doc(uid).set(doc);
  return { uid, username: uname, profileImageURL, isPrivate, isPro };
}

function jitter(n, amt = 0.02) {
  return n + (Math.random() - 0.5) * amt;
}

async function createSpotDoc(user, idx) {
  const city = pick(cities);
  const vibe = pick(vibeTags);
  const id = db.collection('spots').doc().id;
  const seed = `${id.slice(0,6)}${idx}`;
  const imageURL = `https://picsum.photos/seed/${seed}/1200/800`;
  const thumbURL = `https://picsum.photos/seed/${seed}/600/400`;
  const data = {
    postId: id,
    userId: user.uid,
    username: user.username,
    userProfileImageURL: user.profileImageURL,
    imageURL,
    thumbnailURL: thumbURL,
    // multi-image demo
    imageURLs: [imageURL, `https://picsum.photos/seed/${seed}b/1200/800`, `https://picsum.photos/seed/${seed}c/1200/800`].slice(0, randInt(1,3)),
    caption: '',
    vibeTag: vibe,
    vibeTag_lower: vibe.toLowerCase(),
    latitude: jitter(city.lat, 0.08),
    longitude: jitter(city.lon, 0.08),
    locationName: city.name,
    locationName_lower: city.name.toLowerCase(),
    likes: randInt(0, 500),
    saves: randInt(0, 200),
    authorIsPrivate: user.isPrivate,
    createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - randInt(0, 1000*60*60*24*60)),
  };
  await db.collection('spots').doc(id).set(data);
}

async function main() {
  console.log(`\nSeeding ${NUM_USERS} users x ${SPOTS_PER_USER} spots...`);
  const users = [];
  for (let i=0; i<NUM_USERS; i++) {
    users.push(await createUserDoc(i+1));
  }
  for (const u of users) {
    const count = (SPOTS_MIN !== null && SPOTS_MAX !== null)
      ? randInt(Number(SPOTS_MIN), Number(SPOTS_MAX))
      : SPOTS_PER_USER;
    for (let s=0; s<count; s++) {
      await createSpotDoc(u, s+1);
    }
  }
  console.log('Done.');
}

main().catch(err => { console.error(err); process.exit(1); });


