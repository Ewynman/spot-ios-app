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
    author_is_private_snapshot
  )
  values (
    v_uid,
    p_vibe_tag_id,
    '',
    p_latitude,
    p_longitude,
    trim(coalesce(p_location_name, '')),
    coalesce(v_priv, false)
  )
  returning id into v_spot_id;

  v_idx := 0;
  foreach v_aid in array p_media_asset_ids
  loop
    select ma.approved_bucket, ma.approved_path
      into v_buck, v_path
    from public.media_assets ma
    where ma.id = v_aid;

    insert into public.spot_images (
      spot_id,
      storage_path,
      public_url,
      sort_index,
      storage_bucket,
      media_asset_id
    )
    values (
      v_spot_id,
      v_path,
      v_path,
      v_idx,
      v_buck,
      v_aid
    );

    update public.media_assets
    set linked_spot_id = v_spot_id,
        updated_at = now()
    where id = v_aid;

    v_idx := v_idx + 1;
  end loop;

  return v_spot_id;
end;
$$;

revoke all on function public.publish_spot_with_approved_media_assets_v1(uuid, double precision, double precision, text, uuid[]) from public;
grant execute on function public.publish_spot_with_approved_media_assets_v1(uuid, double precision, double precision, text, uuid[]) to authenticated;