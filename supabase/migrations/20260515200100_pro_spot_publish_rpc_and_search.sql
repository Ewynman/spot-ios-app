-- Continuation: publish/update RPCs + search (paired with pro_spot_vibes_and_entitlements when applying remotely split).

drop function if exists public.publish_spot_with_approved_media_assets_v1(uuid, double precision, double precision, text, uuid[]);

create or replace function public.publish_spot_with_approved_media_assets_v1(
  p_vibe_tag_ids uuid[],
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
  v_is_pro boolean;
  v_max_images int;
  v_max_vibes int;
  v_nv int;
  v_i int;
  v_vid uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_is_pro := coalesce(public.spot_user_effective_is_pro(v_uid), false);
  v_max_images := case when v_is_pro then 5 else 1 end;
  v_max_vibes := case when v_is_pro then 5 else 1 end;

  if p_media_asset_ids is null then
    raise exception 'p_media_asset_ids required';
  end if;

  n := coalesce(array_length(p_media_asset_ids, 1), 0);
  if n < 1 then
    raise exception 'at least one image required';
  end if;

  if n > v_max_images then
    if v_is_pro then
      raise exception 'You can add up to 5 images per post.';
    else
      raise exception 'Multiple images are a Pro feature.';
    end if;
  end if;

  if n <> cardinality(array(select distinct unnest(p_media_asset_ids))) then
    raise exception 'duplicate media_asset_ids';
  end if;

  if p_vibe_tag_ids is null or coalesce(array_length(p_vibe_tag_ids, 1), 0) < 1 then
    raise exception 'p_vibe_tag_ids required';
  end if;

  v_nv := array_length(p_vibe_tag_ids, 1);

  if v_nv > v_max_vibes then
    if v_is_pro then
      raise exception 'You can select up to 5 vibes.';
    else
      raise exception 'Multiple vibes are a Pro feature.';
    end if;
  end if;

  if v_nv <> (select count(distinct x) from unnest(p_vibe_tag_ids) as x) then
    raise exception 'duplicate vibe_tag_ids';
  end if;

  for v_i in 1..v_nv loop
    v_vid := p_vibe_tag_ids[v_i];
    if not exists (select 1 from public.vibe_tags vt where vt.id = v_vid) then
      raise exception 'invalid vibe_tag_id';
    end if;
  end loop;

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
    p_vibe_tag_ids[1],
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

  for v_i in 1..v_nv loop
    insert into public.spot_vibe_tags (spot_id, vibe_tag_id, sort_order)
    values (v_spot_id, p_vibe_tag_ids[v_i], v_i - 1);
  end loop;

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

revoke all on function public.publish_spot_with_approved_media_assets_v1(uuid[], double precision, double precision, text, uuid[]) from public;
grant execute on function public.publish_spot_with_approved_media_assets_v1(uuid[], double precision, double precision, text, uuid[]) to authenticated;

create or replace function public.update_spot_metadata_v1(
  p_spot_id uuid,
  p_vibe_tag_ids uuid[],
  p_latitude double precision,
  p_longitude double precision,
  p_location_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_is_pro boolean;
  v_max_vibes int;
  v_nv int;
  v_i int;
  v_vid uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select s.user_id into v_owner from public.spots s where s.id = p_spot_id;
  if v_owner is null then
    raise exception 'spot not found';
  end if;
  if v_owner <> v_uid then
    raise exception 'not authorized';
  end if;

  v_is_pro := coalesce(public.spot_user_effective_is_pro(v_uid), false);
  v_max_vibes := case when v_is_pro then 5 else 1 end;

  if p_vibe_tag_ids is null or coalesce(array_length(p_vibe_tag_ids, 1), 0) < 1 then
    raise exception 'p_vibe_tag_ids required';
  end if;

  v_nv := array_length(p_vibe_tag_ids, 1);

  if v_nv > v_max_vibes then
    if v_is_pro then
      raise exception 'You can select up to 5 vibes.';
    else
      raise exception 'Multiple vibes are a Pro feature.';
    end if;
  end if;

  if v_nv <> (select count(distinct x) from unnest(p_vibe_tag_ids) as x) then
    raise exception 'duplicate vibe_tag_ids';
  end if;

  for v_i in 1..v_nv loop
    v_vid := p_vibe_tag_ids[v_i];
    if not exists (select 1 from public.vibe_tags vt where vt.id = v_vid) then
      raise exception 'invalid vibe_tag_id';
    end if;
  end loop;

  update public.spots
  set
    vibe_tag_id = p_vibe_tag_ids[1],
    latitude = p_latitude,
    longitude = p_longitude,
    location_name = trim(coalesce(p_location_name, ''))
  where id = p_spot_id;

  delete from public.spot_vibe_tags where spot_id = p_spot_id;

  for v_i in 1..v_nv loop
    insert into public.spot_vibe_tags (spot_id, vibe_tag_id, sort_order)
    values (p_spot_id, p_vibe_tag_ids[v_i], v_i - 1);
  end loop;
end;
$$;

revoke all on function public.update_spot_metadata_v1(uuid, uuid[], double precision, double precision, text) from public;
grant execute on function public.update_spot_metadata_v1(uuid, uuid[], double precision, double precision, text) to authenticated;

create or replace function public.list_spot_ids_for_vibe_search_v1(
  p_vibe_tag_ids uuid[],
  p_limit int,
  p_offset int
)
returns table(spot_id uuid, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.created_at
  from public.spots s
  where public.can_view_spot(s.id)
    and (
      s.vibe_tag_id = any(p_vibe_tag_ids)
      or exists (
        select 1 from public.spot_vibe_tags svt
        where svt.spot_id = s.id
          and svt.vibe_tag_id = any(p_vibe_tag_ids)
      )
    )
  order by s.created_at desc
  limit greatest(coalesce(p_limit, 1), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.list_spot_ids_for_vibe_search_v1(uuid[], int, int) from public;
grant execute on function public.list_spot_ids_for_vibe_search_v1(uuid[], int, int) to authenticated;

create or replace function public.list_spot_ids_for_location_and_vibe_search_v1(
  p_location_pattern text,
  p_vibe_tag_ids uuid[],
  p_limit int,
  p_offset int
)
returns table(spot_id uuid, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.created_at
  from public.spots s
  where public.can_view_spot(s.id)
    and s.location_name ilike p_location_pattern escape '\'
    and (
      s.vibe_tag_id = any(p_vibe_tag_ids)
      or exists (
        select 1 from public.spot_vibe_tags svt
        where svt.spot_id = s.id
          and svt.vibe_tag_id = any(p_vibe_tag_ids)
      )
    )
  order by s.created_at desc
  limit greatest(coalesce(p_limit, 1), 1)
  offset greatest(coalesce(p_offset, 0), 0);
$$;

revoke all on function public.list_spot_ids_for_location_and_vibe_search_v1(text, uuid[], int, int) from public;
grant execute on function public.list_spot_ids_for_location_and_vibe_search_v1(text, uuid[], int, int) to authenticated;
