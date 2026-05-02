# Supabase migrations (Spot)

SQL in this folder is applied to your Supabase project with the [Supabase CLI](https://supabase.com/docs/guides/cli).

## `delete_my_account`

[`20260430200000_delete_my_account.sql`](20260430200000_delete_my_account.sql) defines `public.delete_my_account()` used by the iOS app when the user deletes their account. [`20260430203000_delete_my_account_refresh_tokens.sql`](20260430203000_delete_my_account_refresh_tokens.sql) replaces the same function to also delete `auth.refresh_tokens` before sessions.

**After applying:** confirm in the SQL editor that the function exists and that `authenticated` can execute it. Storage files (`avatars`, `spots` buckets) are not removed by this function; use your Storage maintenance flow if you need blobs deleted.

**Scope:** this RPC only cleans **Supabase Postgres + `auth.users`**. Legacy Firebase Storage or other non-Supabase systems need separate cleanup if you still use them.
