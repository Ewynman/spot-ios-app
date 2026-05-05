-- Pro post entitlements: multi-vibe storage (spot_vibe_tags), RLS, backfill.
-- RPCs (new publish signature, update_spot_metadata_v1, search): `20260515200100_pro_spot_publish_rpc_and_search.sql`.

-- ---------------------------------------------------------------------------
-- 1) Effective Pro (aligns with iOS ProfileSupabaseSchema.effectiveIsPro)
-- ---------------------------------------------------------------------------
create or replace function public.spot_user_effective_is_pro(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when u.pro_until is not null then (u.pro_until > now())
    else coalesce(u.is_pro, false)
  end
  from public.users u
  where u.id = p_user_id;
$$;

revoke all on function public.spot_user_effective_is_pro(uuid) from public;
grant execute on function public.spot_user_effective_is_pro(uuid) to authenticated, service_role;

comment on function public.spot_user_effective_is_pro(uuid) is
  'True when pro_until is in the future, else falls back to is_pro (matches client entitlement helper).';

-- ---------------------------------------------------------------------------
-- 2) Junction: many vibe_tags per spot (order preserved)
-- ---------------------------------------------------------------------------
create table if not exists public.spot_vibe_tags (
  spot_id uuid not null references public.spots(id) on delete cascade,
  vibe_tag_id uuid not null references public.vibe_tags(id),
  sort_order integer not null default 0,
  primary key (spot_id, vibe_tag_id)
);

create index if not exists spot_vibe_tags_spot_sort_idx
  on public.spot_vibe_tags (spot_id, sort_order);

alter table public.spot_vibe_tags enable row level security;

drop policy if exists spot_vibe_tags_select_visible on public.spot_vibe_tags;
create policy spot_vibe_tags_select_visible
  on public.spot_vibe_tags
  for select
  to authenticated
  using (public.can_view_spot(spot_id));

drop policy if exists spot_vibe_tags_insert_own on public.spot_vibe_tags;
create policy spot_vibe_tags_insert_own
  on public.spot_vibe_tags
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.spots s
      where s.id = spot_id and s.user_id = (select auth.uid())
    )
  );

drop policy if exists spot_vibe_tags_delete_own on public.spot_vibe_tags;
create policy spot_vibe_tags_delete_own
  on public.spot_vibe_tags
  for delete
  to authenticated
  using (
    exists (
      select 1 from public.spots s
      where s.id = spot_id and s.user_id = (select auth.uid())
    )
  );

grant select on public.spot_vibe_tags to authenticated;
grant insert, delete on public.spot_vibe_tags to authenticated;

-- Backfill from legacy primary column (idempotent)
insert into public.spot_vibe_tags (spot_id, vibe_tag_id, sort_order)
select s.id, s.vibe_tag_id, 0
from public.spots s
where s.vibe_tag_id is not null
on conflict (spot_id, vibe_tag_id) do nothing;
