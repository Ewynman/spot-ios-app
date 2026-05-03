-- Allow PostgREST upsert on public.users for the signed-in user.
-- RLS still restricts which rows; column-level UPDATE remains from the security sweep migration.

grant select, insert, delete on table public.users to authenticated;
