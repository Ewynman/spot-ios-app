# Supabase Environment Setup Guide

## Purpose

Step-by-step instructions for setting up the two-environment Supabase strategy (staging + production) as implemented in the codebase.

## Audience

Repository administrators, infrastructure owners, and engineers completing the environment strategy implementation.

## Current Status

**Code is implemented** — Swift environment selection and CI/CD credential injection are ready. This guide covers the remaining manual setup steps:
1. Create the production Supabase project
2. Replicate schema and data
3. Configure GitHub secrets

---

## Overview

The codebase now supports two Supabase environments:

| Environment | Build Type | Branch | Supabase Project | Status |
|-------------|-----------|--------|------------------|--------|
| **Staging** | Firebase App Distribution | `main` | Current project (`aeurigbbohyxvtsfiyul`) | ✅ Ready (current project) |
| **Production** | TestFlight / App Store | `release/**` | New project (to be created) | ⚠️ Needs setup |

### How It Works

**DEBUG builds (local development, simulators)**:
- Use `#if DEBUG` to select staging environment
- Connect to current Supabase project (`aeurigbbohyxvtsfiyul`)
- Configuration hardcoded in `SupabaseEnvironment.swift`

**RELEASE builds (CI/CD for Firebase and TestFlight)**:
- GitHub Actions inject credentials into `Info.plist` before building
- Firebase builds (`deploy.yml`) inject staging credentials
- TestFlight builds (`testflight.yml`) inject production credentials
- Production builds **require** GitHub secrets to be configured

---

## Step 1: Create Production Supabase Project

### 1.1 Create New Project

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Click **New Project**
3. Configure:
   - **Name**: `Spot Production` (or similar)
   - **Database Password**: Generate a strong password (save in secure location)
   - **Region**: Same region as staging for consistency (check current project settings)
   - **Organization**: Same organization as current project (`mdnqvdzrrhjtaxbwnleq`)
4. Wait for project provisioning (2-3 minutes)

### 1.2 Record Project Details

After creation, save these values:

```
Project ID: ____________________  (e.g., abcdefghijklmnopqrst)
Project URL: https://______________________.supabase.co
Anon/Publishable Key: sb_publishable_____________________
Service Role Key: sb_service_role_______________________  (DO NOT add to repo or client)
```

**⚠️ Security**: Only the **Anon/Publishable Key** goes in GitHub secrets. Never commit or ship the service role key.

---

## Step 2: Replicate Schema to Production

### 2.1 Export Current Schema

From the workspace root:

```bash
cd /workspace

# Export schema from staging project
# Option A: Using Supabase CLI (if linked)
supabase db dump --linked > /tmp/staging-schema.sql

# Option B: Using pg_dump directly (requires connection string)
# Get connection string from Supabase dashboard → Database → Connection String
pg_dump "postgresql://..." > /tmp/staging-schema.sql
```

### 2.2 Apply Migrations to Production

**Recommended approach**: Apply migrations in order to maintain history.

```bash
# Link CLI to production project
supabase link --project-ref YOUR_PRODUCTION_PROJECT_ID

# Apply each migration file in order
for migration in supabase/migrations/*.sql; do
  echo "Applying $migration..."
  supabase db push --db-url "YOUR_PRODUCTION_DB_CONNECTION_STRING" < "$migration"
done
```

**Alternative**: Import full schema dump (loses migration history):

```bash
psql "YOUR_PRODUCTION_DB_CONNECTION_STRING" < /tmp/staging-schema.sql
```

### 2.3 Verify Schema Parity

Run these checks on both staging and production:

```sql
-- Check table count
SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';

-- Check RLS enabled
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public';

-- Check policies
SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname = 'public';

-- Check functions
SELECT routine_name FROM information_schema.routines WHERE routine_schema = 'public';
```

Compare results between environments. They should be identical.

---

## Step 3: Configure Storage Buckets

### 3.1 Create Buckets in Production

In the Supabase dashboard for your **production project**:

1. Go to **Storage**
2. Create these buckets:

| Bucket ID | Public | File Size Limit | Allowed MIME Types |
|-----------|--------|-----------------|-------------------|
| `pending_images` | Private | 5 MB | `image/jpeg`, `image/png`, `image/webp` |
| `approved_spot_images` | Private | 5 MB | `image/jpeg`, `image/png`, `image/webp` |
| `approved_profile_images` | Private | 5 MB | `image/jpeg`, `image/png`, `image/webp` |
| `spots` | Private | 5 MB | `image/jpeg`, `image/png`, `image/webp` |

### 3.2 Apply Storage Policies

Storage RLS policies are defined in migration `20260504100000_image_moderation_azure_v1.sql`. Verify they were applied when you replicated the schema.

Check via dashboard or SQL:

```sql
SELECT bucket_id, name FROM storage.policies;
```

---

## Step 4: Deploy Edge Functions to Production

### 4.1 Deploy moderate-image Function

```bash
cd /workspace

# Link to production project
supabase link --project-ref YOUR_PRODUCTION_PROJECT_ID

# Deploy the function
supabase functions deploy moderate-image
```

### 4.2 Configure Function Secrets

The `moderate-image` function requires Azure Content Safety credentials.

In Supabase dashboard → **Edge Functions** → **moderate-image** → **Settings**:

Add these secrets (get values from Azure portal):

```
AZURE_CONTENT_SAFETY_ENDPOINT=https://your-endpoint.cognitiveservices.azure.com/
AZURE_CONTENT_SAFETY_KEY=your-azure-key-here
```

**Note**: You can use the same Azure endpoint for both staging and production, or create separate endpoints for isolation.

### 4.3 Test Edge Function

```bash
# Test invocation (requires auth)
curl -X POST \
  "https://YOUR_PRODUCTION_PROJECT_ID.supabase.co/functions/v1/moderate-image" \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

---

## Step 5: Configure GitHub Secrets

### 5.1 Navigate to Repository Secrets

1. Go to GitHub repository: `https://github.com/Ewynman/spot-ios-app`
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**

### 5.2 Add Staging Secrets (Optional)

These are optional since staging uses hardcoded values as a fallback:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `SUPABASE_STAGING_URL` | `https://aeurigbbohyxvtsfiyul.supabase.co` | Current project URL |
| `SUPABASE_STAGING_ANON_KEY` | `sb_publishable_5IKZU3dDw6C0-V9lRPc7vw_z_v8a08G` | Current project anon key |

### 5.3 Add Production Secrets (Required)

These are **required** for TestFlight builds to work:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `SUPABASE_PRODUCTION_URL` | `https://YOUR_PROD_PROJECT_ID.supabase.co` | New production project URL |
| `SUPABASE_PRODUCTION_ANON_KEY` | `sb_publishable_YOUR_PROD_ANON_KEY` | New production project anon key |

**⚠️ Critical**: TestFlight builds will **fail** if these secrets are not set. The workflow intentionally blocks production builds without valid credentials.

### 5.4 Verify Secret Configuration

Secrets should look like this in GitHub:

```
✅ GOOGLE_SERVICE_INFO_PLIST_BASE64
✅ FIREBASE_DEV_CERT
✅ FIREBASE_PROVISIONING_PROFILE
✅ TESTFLIGHT_APPLE_CERT
✅ TESTFLIGHT_APPLE_PROFILE
✅ APP_STORE_CONNECT_API_KEY_ID
✅ APP_STORE_CONNECT_API_ISSUER_ID
✅ APP_STORE_CONNECT_API_KEY_P8_BASE64
✅ SUPABASE_STAGING_URL (optional)
✅ SUPABASE_STAGING_ANON_KEY (optional)
✅ SUPABASE_PRODUCTION_URL (required)
✅ SUPABASE_PRODUCTION_ANON_KEY (required)
```

---

## Step 6: Update Code Configuration (Optional)

### 6.1 Update SupabaseEnvironment.swift

If you want to hardcode the production URL (not recommended for security), update:

```swift
// File: Spot/Utils/SupabaseEnvironment.swift

case .production:
    return "https://YOUR_ACTUAL_PRODUCTION_PROJECT_ID.supabase.co"
```

**However**, it's better to leave placeholders and rely on CI/CD injection for production builds.

---

## Step 7: Test the Configuration

### 7.1 Test Staging Build (Firebase)

1. Make a test commit to `main` branch
2. Wait for GitHub Actions workflow to complete
3. Check workflow logs for:
   ```
   ✅ Using Supabase staging credentials from GitHub secrets
   ✅ Supabase staging configuration injected into Info.plist
   ```
4. Download the Firebase App Distribution build
5. Install and verify app connects to staging Supabase

### 7.2 Test Production Build (TestFlight)

1. Create a test `release/1.0.0` branch (or use existing)
2. Push a commit to trigger the workflow
3. Check workflow logs for:
   ```
   ✅ Using Supabase production credentials from GitHub secrets
   ✅ Supabase production configuration injected into Info.plist
   ```
4. Wait for TestFlight processing
5. Install TestFlight build and verify it connects to production Supabase

### 7.3 Test Local DEBUG Build

1. Open project in Xcode
2. Build and run in simulator (DEBUG configuration)
3. Check console logs:
   ```
   🔧 Supabase Environment: Staging
   🔧 Supabase URL: https://aeurigbbohyxvtsfiyul.supabase.co
   ```
4. Verify app functionality with staging database

---

## Step 8: Seed Production Data (Optional)

If you want to migrate existing user data from staging to production:

⚠️ **Warning**: Only do this if staging contains real user data you want to preserve. For most cases, start with an empty production database.

### 8.1 Export Data from Staging

```sql
-- Export users (passwords are hashed, safe to copy)
COPY (SELECT * FROM auth.users) TO '/tmp/users.csv' WITH CSV HEADER;
COPY (SELECT * FROM public.users) TO '/tmp/public_users.csv' WITH CSV HEADER;

-- Export spots and related data
COPY (SELECT * FROM public.spots) TO '/tmp/spots.csv' WITH CSV HEADER;
COPY (SELECT * FROM public.spot_images) TO '/tmp/spot_images.csv' WITH CSV HEADER;
-- ... repeat for other tables
```

### 8.2 Import to Production

```sql
COPY auth.users FROM '/tmp/users.csv' WITH CSV HEADER;
COPY public.users FROM '/tmp/public_users.csv' WITH CSV HEADER;
-- ... repeat for other tables
```

### 8.3 Verify Data Integrity

```sql
-- Check record counts match
SELECT 'users', count(*) FROM public.users
UNION ALL
SELECT 'spots', count(*) FROM public.spots
UNION ALL
SELECT 'follows', count(*) FROM public.follows;
```

---

## Step 9: Monitor Production

### 9.1 Enable Monitoring

In production Supabase project:
- Enable **Realtime** → Monitor subscriptions
- Check **Logs** → Enable log retention
- Configure **Usage** → Set up billing alerts

### 9.2 Monitor After First Production Release

After the first TestFlight build using production:
- Check **Auth** → Users (should see new signups in production only)
- Check **Database** → Tables (production should remain separate from staging)
- Check **Storage** → Buckets (uploads should go to production buckets)
- Check **API** → Logs (verify no errors)

---

## Rollback Plan

If production environment has issues:

### Quick Rollback (Emergency)

1. Update GitHub secrets to point production to staging temporarily:
   ```
   SUPABASE_PRODUCTION_URL → https://aeurigbbohyxvtsfiyul.supabase.co
   SUPABASE_PRODUCTION_ANON_KEY → sb_publishable_5IKZU3dDw6C0-V9lRPc7vw_z_v8a08G
   ```
2. Rebuild and redeploy TestFlight

### Full Rollback (Revert Implementation)

1. Revert these files to previous versions:
   - `Spot/Utils/SupabaseEnvironment.swift` (delete)
   - `Spot/Supabase/Supabase.swift` (restore old version)
   - `.github/workflows/deploy.yml` (remove Supabase injection step)
   - `.github/workflows/testflight.yml` (remove Supabase injection step)
2. Commit and push
3. Both environments will use the same Supabase project again

---

## Troubleshooting

### Problem: TestFlight build fails with "Production Supabase credentials are not configured"

**Solution**: Add `SUPABASE_PRODUCTION_URL` and `SUPABASE_PRODUCTION_ANON_KEY` to GitHub secrets.

### Problem: Local DEBUG build crashes with "Supabase configuration error"

**Solution**: Ensure `SupabaseEnvironment.swift` has valid staging credentials (not PLACEHOLDER values).

### Problem: App connects to wrong environment

**Check**:
- DEBUG builds → Should use staging (hardcoded in `SupabaseEnvironment.swift`)
- Firebase builds → Should use staging (check `deploy.yml` logs)
- TestFlight builds → Should use production (check `testflight.yml` logs)

**Debug**:
```swift
// Add temporary logging to see which URL is being used
print("Supabase URL: \(supabase.supabaseURL)")
```

### Problem: Schema drift between environments

**Fix**:
```bash
# Compare schemas
supabase db diff --linked --schema public

# If differences found, apply missing migrations to the outdated environment
```

---

## Related Documentation

- [docs/engineering/supabase-environment-strategy.md](supabase-environment-strategy.md) — Full PRD and strategy
- [docs/engineering/supabase.md](supabase.md) — Supabase integration overview
- [docs/engineering/database-and-rls.md](database-and-rls.md) — Database and RLS policies
- [docs/engineering/environment-variables.md](environment-variables.md) — Configuration secrets

---

## Completion Checklist

- [ ] Production Supabase project created
- [ ] Schema replicated from staging to production
- [ ] Storage buckets configured in production
- [ ] Edge Functions deployed to production
- [ ] Azure credentials configured for production Edge Function
- [ ] GitHub secrets added (staging optional, production required)
- [ ] Firebase build tested (uses staging)
- [ ] TestFlight build tested (uses production)
- [ ] Local DEBUG build tested (uses staging)
- [ ] Production monitoring enabled
- [ ] Team trained on new environment strategy

---

**Status**: Ready for implementation  
**Last Updated**: 2026-07-06  
**Implemented By**: Cursor Agent
