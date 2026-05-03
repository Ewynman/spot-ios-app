-- Spot media layout v1: persisted display aspect ratio on spots + per-image
-- metadata on spot_images (aligned with app SpotMediaAspectRatio clamp 0.80–1.91).
-- Updates publish_spot_with_approved_media_assets_v1 to populate these fields.
--
-- Follow-up (Supabase SQL editor / migration): extend public.get_home_feed_v1 and
-- public.get_map_spots_v1 to SELECT s.media_display_aspect_ratio AS
-- media_display_aspect_ratio so feed/map rows can size cards before image load.

-- ---------------------------------------------------------------------------
-- 1. Clamp helper (immutable; width/height ratio = width / height)
-- ---------------------------------------------------------------------------
create or replace function public.spot_clamp_display_aspect_ratio(p_raw numeric)
returns numeric
language sql
immutable
as $$
  select greatest(
    0.80::numeric,
    least(1.91::numeric, coalesce(p_raw, 1.0::numeric))
  );
$$;

comment on function public.spot_clamp_display_aspect_ratio(numeric) is
  'Clamps spot card width/height ratio for stable feed layout (0.80–1.91).';

-- ---------------------------------------------------------------------------
-- 2. spots: denormalized layout for clients
-- ---------------------------------------------------------------------------
alter table public.spots
  add column if not exists media_display_aspect_ratio numeric not null default 1.0;

alter table public.spots
  add column if not exists media_count integer not null default 0;

alter table public.spots
  add column if not exists media_layout_version integer not null default 1;

comment on column public.spots.media_display_aspect_ratio is
  'Width/height display ratio for the Spot media shell (cover = lowest sort_index).';
comment on column public.spots.media_count is
  'Number of spot_images rows for this spot.';
comment on column public.spots.media_layout_version is
  'Layout contract version; app uses 1 for aspect-aware cards.';

-- ---------------------------------------------------------------------------
-- 3. spot_images: per-image geometry (mirrors moderation media_assets when linked)
-- ---------------------------------------------------------------------------
alter table public.spot_images
  add column if not exists width integer;

alter table public.spot_images
  add column if not exists height integer;

alter table public.spot_images
  add column if not exists aspect_ratio numeric;

alter table public.spot_images
  add column if not exists display_aspect_ratio numeric not null default 1.0;

alter table public.spot_images
  add column if not exists orientation text not null default 'square';

alter table public.spot_images
  drop constraint if exists spot_images_orientation_check;

alter table public.spot_images
  add constraint spot_images_orientation_check
  check (orientation in ('landscape', 'square', 'portrait'));

-- ---------------------------------------------------------------------------
-- 4. Backfill from media_assets + defaults
-- ---------------------------------------------------------------------------
update public.spot_images si
set
  width = coalesce(si.width, ma.width),
  height = coalesce(si.height, ma.height)
from public.media_assets ma
where si.media_asset_id = ma.id;

update public.spot_images si
set
  aspect_ratio = case
    when si.width is not null and si.height is not null and si.height <> 0
      then si.width::numeric / si.height::numeric
    else 1.0::numeric
  end,
  display_aspect_ratio = public.spot_clamp_display_aspect_ratio(
    case
      when si.width is not null and si.height is not null and si.height <> 0
        then si.width::numeric / si.height::numeric
      else null
    end
  ),
  orientation = case
    when si.width is null or si.height is null or si.height = 0 then 'square'
    when si.width::numeric > si.height::numeric * 1.05 then 'landscape'
    when si.height::numeric > si.width::numeric * 1.05 then 'portrait'
    else 'square'
  end;

update public.spots s
set
  media_count = coalesce(c.cnt, 0),
  media_display_aspect_ratio = coalesce(c.dar, 1.0::numeric),
  media_layout_version = 1
from (
  select
    si.spot_id as spot_id,
    count(*)::integer as cnt,
    (
      select si2.display_aspect_ratio
      from public.spot_images si2
      where si2.spot_id = si.spot_id
      order by si2.sort_index asc
      limit 1
    ) as dar
  from public.spot_images si
  group by si.spot_id
) c
where s.id = c.spot_id;

-- ---------------------------------------------------------------------------
-- 5. Publish RPC: copy dimensions from media_assets; update spot summary
-- ---------------------------------------------------------------------------
create or replace function public.publish_spot_with_approved_media_assets_v1(
  p_vibe_tag_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_location_name text,
  p_media_asset_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_spot_id uuid;
  v_idx int := 0;
  v_aid uuid;
  v_priv boolean;
  v_buck text;
  v_path text;
  n int;
  v_w int;
  v_h int;
  v_ar numeric;
  v_dar numeric;
  v_ori text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if p_media_asset_ids is null then
    raise exception 'p_media_asset_ids required';
  end if;

  n := coalesce(array_length(p_media_asset_ids, 1), 0);
  if n < 1 or n > 10 then
    raise exception 'between 1 and 10 images required';
  end if;

  if n <> cardinality(array(select distinct unnest(p_media_asset_ids))) then
    raise exception 'duplicate media_asset_ids';
  end if;

  if not exists (select 1 from public.vibe_tags vt where vt.id = p_vibe_tag_id) then
    raise exception 'invalid vibe_tag_id';
  end if;

  foreach v_aid in array p_media_asset_ids
  loop
    if not exists (
      select 1
      from public.media_assets ma
      where ma.id = v_aid
        and ma.owner_id = v_uid
        and ma.kind = 'spot_image'
        and ma.status = 'approved'
        and ma.linked_spot_id is null
        and ma.approved_bucket is not null
        and ma.approved_path is not null
    ) then
      raise exception 'invalid or unavailable media asset %', v_aid;
    end if;
  end loop;

  select coalesce(u.is_private, false) into v_priv
  from public.users u
  where u.id = v_uid;

  insert into public.spots (
    user_id,
    vibe_tag_id,
    caption,
    latitude,
    longitude,
    location_name,
    author_is_private_snapshot,
    media_display_aspect_ratio,
    media_count,
    media_layout_version
  )
  values (
    v_uid,
    p_vibe_tag_id,
    '',
    p_latitude,
    p_longitude,
    trim(coalesce(p_location_name, '')),
    coalesce(v_priv, false),
    1.0::numeric,
    0,
    1
  )
  returning id into v_spot_id;

  v_idx := 0;
  foreach v_aid in array p_media_asset_ids
  loop
    select ma.approved_bucket, ma.approved_path, ma.width, ma.height
      into v_buck, v_path, v_w, v_h
    from public.media_assets ma
    where ma.id = v_aid;

    if coalesce(v_w, 0) > 0 and coalesce(v_h, 0) > 0 then
      v_ar := v_w::numeric / v_h::numeric;
      v_dar := public.spot_clamp_display_aspect_ratio(v_ar);
      if v_w::numeric > v_h::numeric * 1.05 then
        v_ori := 'landscape';
      elsif v_h::numeric > v_w::numeric * 1.05 then
        v_ori := 'portrait';
      else
        v_ori := 'square';
      end if;
    else
      v_ar := 1.0::numeric;
      v_dar := 1.0::numeric;
      v_ori := 'square';
    end if;

    insert into public.spot_images (
      spot_id,
      storage_path,
      public_url,
      sort_index,
      storage_bucket,
      media_asset_id,
      width,
      height,
      aspect_ratio,
      display_aspect_ratio,
      orientation
    )
    values (
      v_spot_id,
      v_path,
      v_path,
      v_idx,
      v_buck,
      v_aid,
      v_w,
      v_h,
      v_ar,
      v_dar,
      v_ori
    );

    update public.media_assets
    set linked_spot_id = v_spot_id,
        updated_at = now()
    where id = v_aid;

    v_idx := v_idx + 1;
  end loop;

  update public.spots
  set
    media_count = v_idx,
    media_display_aspect_ratio = (
      select si.display_aspect_ratio
      from public.spot_images si
      where si.spot_id = v_spot_id
      order by si.sort_index asc
      limit 1
    ),
    media_layout_version = 1
  where id = v_spot_id;

  return v_spot_id;
end;
$$;

revoke all on function public.publish_spot_with_approved_media_assets_v1(uuid, double precision, double precision, text, uuid[]) from public;
grant execute on function public.publish_spot_with_approved_media_assets_v1(uuid, double precision, double precision, text, uuid[]) to authenticated;

comment on function public.publish_spot_with_approved_media_assets_v1 is
  'Creates a spot and spot_images rows only for approved moderated media_assets; writes media_display_aspect_ratio and per-image geometry.';
