-- UGC moderation: server-side text content filter.
--
-- Provides a small, conservative server-side enforcement layer so client
-- bypass cannot publish obvious objectionable text. The filter splits the
-- input into word tokens (lower-cased, punctuation-stripped) and rejects the
-- write if any token matches a hardcoded blocklist of severe slurs / explicit
-- sexual / direct-violence terms.
--
-- This is intentionally conservative; richer ML/keyword classifiers can be
-- added later via Edge Functions writing into `content_moderation_results`.

create or replace function public.text_token_normalize(p_text text)
returns text[]
language sql
immutable
set search_path = public
as $$
  select case
    when p_text is null or btrim(p_text) = '' then array[]::text[]
    else (
      select coalesce(array_agg(lower(t.tok)), array[]::text[])
      from regexp_split_to_table(p_text, '[^[:alnum:]]+') as t(tok)
      where length(t.tok) > 0
    )
  end;
$$;

comment on function public.text_token_normalize(text) is
  'Splits free-form text into lowercased alphanumeric tokens (no punctuation).';

create or replace function public.text_contains_severe_blocked_terms(p_text text)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from unnest(public.text_token_normalize(p_text)) as t(tok)
    where t.tok = any (array[
      -- Severe slurs (intentionally minimal; expand carefully).
      'nigger', 'nigga',
      'faggot', 'fag',
      'kike',
      'spic',
      'chink',
      'tranny',
      'retard', 'retarded',
      -- Severe sexual / pornographic markers
      'pornhub', 'onlyfans',
      -- Explicit direct violence / self-harm prompts as single tokens.
      'kys'
    ])
  );
$$;

comment on function public.text_contains_severe_blocked_terms(text) is
  'Returns true if the input text contains any token matching the severe-blocklist.';

create or replace function public.enforce_spot_text_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caption_blocked boolean := public.text_contains_severe_blocked_terms(NEW.caption);
  v_location_blocked boolean := public.text_contains_severe_blocked_terms(NEW.location_name);
begin
  if v_caption_blocked then
    insert into public.content_moderation_results (
      target_type, target_id, user_id, input_type, status,
      categories, matched_terms, provider, provider_response
    ) values (
      'spot', NEW.id, NEW.user_id, 'text', 'rejected',
      jsonb_build_object('field', 'caption'),
      array['severe_blocklist'],
      'spot_internal_text_filter_v1',
      jsonb_build_object('caption_excerpt', left(coalesce(NEW.caption, ''), 200))
    );
    raise exception
      using errcode = '23514',
            message = 'caption rejected by content moderation',
            detail = 'spot_caption_blocked',
            hint = 'Please edit the caption before posting.';
  end if;

  if v_location_blocked then
    insert into public.content_moderation_results (
      target_type, target_id, user_id, input_type, status,
      categories, matched_terms, provider, provider_response
    ) values (
      'spot', NEW.id, NEW.user_id, 'text', 'rejected',
      jsonb_build_object('field', 'location_name'),
      array['severe_blocklist'],
      'spot_internal_text_filter_v1',
      jsonb_build_object('location_name_excerpt', left(coalesce(NEW.location_name, ''), 200))
    );
    raise exception
      using errcode = '23514',
            message = 'location name rejected by content moderation',
            detail = 'spot_location_name_blocked',
            hint = 'Please edit the location label before posting.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_enforce_spot_text_moderation on public.spots;
create trigger trg_enforce_spot_text_moderation
  before insert or update of caption, location_name on public.spots
  for each row
  execute function public.enforce_spot_text_moderation();

create or replace function public.enforce_user_text_moderation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.text_contains_severe_blocked_terms(NEW.username) then
    insert into public.content_moderation_results (
      target_type, target_id, user_id, input_type, status,
      categories, matched_terms, provider, provider_response
    ) values (
      'profile', NEW.id, NEW.id, 'text', 'rejected',
      jsonb_build_object('field', 'username'),
      array['severe_blocklist'],
      'spot_internal_text_filter_v1',
      jsonb_build_object('username_excerpt', left(coalesce(NEW.username, ''), 80))
    );
    raise exception
      using errcode = '23514',
            message = 'username rejected by content moderation',
            detail = 'username_blocked',
            hint = 'Please choose a different username.';
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_enforce_user_text_moderation on public.users;
create trigger trg_enforce_user_text_moderation
  before insert or update of username on public.users
  for each row
  execute function public.enforce_user_text_moderation();
