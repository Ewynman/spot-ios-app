# Deploy `moderate-image` Edge Function

This project’s moderation pipeline calls  
`POST https://<project-ref>.supabase.co/functions/v1/moderate-image`  
with the user’s JWT. The function code lives at:

`supabase/functions/moderate-image/index.ts` (+ `deno.json`).

**Database migrations** must be applied on your Supabase project (not only Edge deploy). If the Edge logs show `permission denied for table media_assets`, apply latest migrations — including `20260504150000_media_assets_grants_for_edge_service_role.sql`, which grants `service_role` access required by the function’s admin client:

```bash
# Linked project: pushes pending migration files to remote Postgres
npx supabase@latest db push
```

Or run the SQL from that migration file in **Dashboard → SQL Editor**.

---

## One-time setup

1. **Install Supabase CLI** (pick one):
   - Homebrew: `brew install supabase/tap/supabase`
   - Or use **npx** (no global install): every command below can use `npx supabase@latest` instead of `supabase`.

2. **Authenticate** (pick one):

   **A — Interactive login (good for your laptop)**  

   ```bash
   npx supabase@latest login
   ```

   Follow the browser flow.

   **B — Access token (good for CI or scripted deploys)**  

   - Dashboard: **Account** → **Access Tokens** → create a token.  
   - Then:

   ```bash
   export SUPABASE_ACCESS_TOKEN="your_personal_access_token"
   ```

   The CLI will use this env var automatically.

3. **Secrets for Azure** (production — **not** stored in the repo):

   Supabase already injects **`SUPABASE_URL`**, **`SUPABASE_ANON_KEY`**, and **`SUPABASE_SERVICE_ROLE_KEY`** into hosted Edge Functions — you do **not** need to add those manually unless you override them.

   You **do** need to add **your Azure Content Safety** values as Edge secrets:

   | Secret name | Required | Notes |
   |-------------|----------|--------|
   | `AZURE_CONTENT_SAFETY_ENDPOINT` | Yes | Azure endpoint URL (no trailing slash issues handled in code). |
   | `AZURE_CONTENT_SAFETY_KEY` | Yes | Subscription / API key. |
   | `AZURE_CONTENT_SAFETY_API_VERSION` | Optional | Defaults to `2024-09-01` in code if unset. |
   | `MODERATION_THRESHOLDS_JSON` | Optional | Overrides default thresholds; JSON keyed by `spot_image` / `profile_image`. |

   **Where to set them**

   - Dashboard: **Project** → **Edge Functions** → **Secrets** (or **Project Settings** → **Edge Functions** → secrets, depending on UI version).  
   - CLI (after login / token):

     ```bash
     npx supabase@latest secrets set \
       AZURE_CONTENT_SAFETY_ENDPOINT="https://YOUR_RESOURCE.cognitiveservices.azure.com" \
       AZURE_CONTENT_SAFETY_KEY="YOUR_KEY" \
       --project-ref aeurigbbohyxvtsfiyul
     ```

   Never commit keys to git. Use Dashboard/CLI only.

---

## Deploy (every time you change the function)

From the **repository root**:

```bash
./scripts/deploy-moderate-image.sh
```

Or explicitly:

```bash
npx supabase@latest functions deploy moderate-image --project-ref aeurigbbohyxvtsfiyul
```

You need network access and a valid CLI session (`login` or `SUPABASE_ACCESS_TOKEN`).

---

## Verify

1. Dashboard: **Edge Functions** → **`moderate-image`** → open **Code** (or latest deployment).  
   You should see the full handler (Azure `image:analyze`, `media_assets`, storage download/upload).  
   If you only see a short placeholder (`ok`, `message`), redeploy from this repo.

2. Optional: **Logs** tab on the same function after posting from the app.

3. Optional CLI:

   ```bash
   npx supabase@latest secrets list --project-ref aeurigbbohyxvtsfiyul
   ```

   Confirm Azure-related secrets exist (names only are listed in some setups).

---

## Troubleshooting

| Symptom | Likely cause |
|--------|----------------|
| App toast “couldn’t check…” / logs show `jsonKeys` like `message,ok` | Placeholder still deployed; redeploy real `index.ts`. |
| Logs / DB show `azure_env_missing` | Azure secrets not set on the project. |
| `401` / invalid token | App JWT or anon header; ensure user is signed in. |

Secrets apply immediately after `secrets set`; you usually **do not** need to redeploy only for secret changes.
