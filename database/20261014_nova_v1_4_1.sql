begin;
create table private.clip_conversions(user_id uuid references auth.users on delete cascade,author_id uuid references auth.users on delete cascade,clip_id uuid references public.clips on delete set null,created_at timestamptz not null default now(),primary key(user_id,author_id));
alter table private.clip_conversions enable row level security;
revoke all on private.clip_conversions from public,anon,authenticated;
create function private.nova_clip_follow(p_clip uuid) returns text language plpgsql security definer set search_path='' as $$declare author uuid;was_following boolean;result text;begin
if not private.clip_visible(p_clip) then raise exception 'Clip unavailable';end if;
select user_id into author from public.clips where id=p_clip and status='published';if author is null then raise exception 'Clip unavailable';end if;
perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||author::text,0));
was_following=exists(select 1 from public.user_follows where user_id=auth.uid() and followed_id=author);
result=private.nova_follow(author);
if not was_following and result='following' then insert into private.clip_conversions(user_id,author_id,clip_id) values(auth.uid(),author,p_clip) on conflict do nothing;end if;
return result;end$$;
create function public.nova_clip_follow(p_clip uuid) returns text language sql security invoker set search_path='' as $$select private.nova_clip_follow(p_clip)$$;
revoke all on function private.nova_clip_follow(uuid),public.nova_clip_follow(uuid) from public,anon,authenticated;
grant execute on function private.nova_clip_follow(uuid),public.nova_clip_follow(uuid) to authenticated;
create or replace function private.nova_clip_metrics(p_clip uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.clip_visible(p_clip) then raise exception 'Clip unavailable';end if;
 return jsonb_build_object('subscriptions',case when exists(select 1 from public.clips where id=p_clip and user_id=auth.uid()) then (select count(*) from private.clip_conversions where clip_id=p_clip) else null end,'likes',(select count(*) from public.clip_likes where clip_id=p_clip),'comments',(select count(*) from public.clip_comments where clip_id=p_clip),'views',(select count(*) from private.clip_views where clip_id=p_clip and qualified),'saves',case when exists(select 1 from public.clips where id=p_clip and user_id=auth.uid()) then (select count(*) from public.clip_saves where clip_id=p_clip) else null end,'completed',case when exists(select 1 from public.clips where id=p_clip and user_id=auth.uid()) then (select count(*) from private.clip_views where clip_id=p_clip and completed) else null end,'avg_watch_seconds',case when exists(select 1 from public.clips where id=p_clip and user_id=auth.uid()) then (select round(avg(watched_seconds),1) from private.clip_views where clip_id=p_clip and qualified) else null end);
end$$;
insert into public.nova_schema_versions(version) values('20261014_nova_v1_4_1');
commit;
