# Spot Mock Data Seeder (Firestore)

Quickly create fake `users` and `spots` in Firestore for dev/testing.

## Prereqs
- A Firebase project with Firestore
- Service account key JSON or Application Default Credentials
- Node 18+

## Steps
```bash
cd Mock
npm init -y && npm i firebase-admin
# Either set a service account key path...
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/serviceAccountKey.json
# ...or use ADC via gcloud (optional)
# gcloud auth application-default login

# Seed 10 users x 20 spots each (adjust numbers as needed)
node seed.js --users 10 --spots 20
```

## What it writes
- `users/{uid}` with fields: `username`, `username_lower`, `profileImageURL`, `isPrivate`, `isPro`, `isVerified`, arrays for `following`, `requestedFollows`, `blockedUsers`, `likedSpots`, `bookmarkedSpots`, `vibeStats`, `createdAt`.
- `spots/{postId}` with fields from the app: `postId`, `userId`, `username`, `userProfileImageURL`, `imageURL`, `thumbnailURL`, `imageURLs` (1-3), `vibeTag`, `vibeTag_lower`, `latitude`, `longitude`, `locationName`, `locationName_lower`, `likes`, `saves`, `authorIsPrivate`, `createdAt`.

No Firebase Auth users are created; these are profile docs only.

## Clean up (optional)
Use the Firebase console to delete collections, or write a small admin script to delete `users` and `spots` if needed.


