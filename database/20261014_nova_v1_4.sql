-- NOVA Clips: social video feed and creator settings. No external streaming service.
begin;
alter table public.clips
 add column title text not null default '' check(length(title)<=120),
 add column cover_path text check(cover_path is null or split_part(cover_path,'/',1)=user_id::text),
 add column status text not null default 'published' check(status in ('draft','published')),
 add column comments_enabled boolean not null default true,
 add column allow_sharing boolean not null default true,
 add column allow_saving boolean not null default true,
 add column fit text not null default 'cover' check(fit in ('cover','contain')),
 add column duration_seconds numeric check(duration_seconds>0 and duration_seconds<=180),
 add column published_at timestamptz not null default now(),
 add column updated_at timestamptz not null default now();
update public.clips set published_at=created_at;
create function private.clip_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='UPDATE' then
 if new.id<>old.id or new.user_id<>old.user_id or new.created_at<>old.created_at then raise exception 'Immutable clip identity'; end if;
 if old.status='draft' and new.status='published' then new.published_at=now();else new.published_at=old.published_at;end if;
 else new.published_at=now();end if;
 if cardinality(new.topics)>10 or exists(select 1 from unnest(new.topics) t where length(t) not between 1 and 50) then raise exception 'Invalid topics';end if;
 if length(new.caption)>2200 then raise exception 'Caption too long';end if;
 new.updated_at=now();return new;end$$;
revoke all on function private.clip_guard() from public,anon,authenticated;
create trigger clip_guard before insert or update on public.clips for each row execute function private.clip_guard();
grant update(title,cover_path,status,comments_enabled,allow_sharing,allow_saving,fit,duration_seconds) on public.clips to authenticated;
create or replace function private.clip_visible(c uuid) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.clips where id=c and (user_id=auth.uid() or (status='published' and private.social_visible(user_id,visibility))))$$;
create or replace function private.social_media_access(object_name text) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and (split_part(object_name,'/',1)=auth.uid()::text or exists(select 1 from public.posts p where p.media_path=object_name and private.post_visible(p.id)) or exists(select 1 from public.clips c where (c.media_path=object_name or c.cover_path=object_name) and private.clip_visible(c.id)) or exists(select 1 from public.stories s where s.media_path=object_name and s.expires_at>now() and private.social_visible(s.user_id,s.audience)))$$;
create table public.clip_comments(id uuid primary key default gen_random_uuid(),clip_id uuid not null references public.clips on delete cascade,user_id uuid not null references auth.users on delete cascade,parent_id uuid,body text not null check(length(btrim(body)) between 1 and 2000),created_at timestamptz not null default now(),unique(id,clip_id),foreign key(parent_id,clip_id) references public.clip_comments(id,clip_id) on delete cascade);
create index clip_comments_page on public.clip_comments(clip_id,created_at,id);
create table public.clip_saves(user_id uuid references auth.users on delete cascade,clip_id uuid references public.clips on delete cascade,created_at timestamptz not null default now(),primary key(user_id,clip_id));
create table public.clip_dismissals(user_id uuid references auth.users on delete cascade,clip_id uuid references public.clips on delete cascade,created_at timestamptz not null default now(),primary key(user_id,clip_id));
create table private.clip_views(user_id uuid references auth.users on delete cascade,clip_id uuid references public.clips on delete cascade,token uuid not null default gen_random_uuid(),started_at timestamptz not null default now(),watched_seconds numeric not null default 0,qualified boolean not null default false,completed boolean not null default false,primary key(user_id,clip_id));
alter table private.clip_views enable row level security;
revoke all on private.clip_views from public,anon,authenticated;
alter table public.clip_comments enable row level security;
alter table public.clip_saves enable row level security;
alter table public.clip_dismissals enable row level security;
revoke all on public.clip_comments,public.clip_saves,public.clip_dismissals from public,anon,authenticated;
grant select,insert,delete on public.clip_comments,public.clip_saves,public.clip_dismissals to authenticated;
create policy clip_comments_read on public.clip_comments for select to authenticated using(private.clip_visible(clip_id));
create policy clip_comments_add on public.clip_comments for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.clips c where c.id=clip_id and c.status='published' and c.comments_enabled and private.clip_visible(c.id)));
create policy clip_comments_delete on public.clip_comments for delete to authenticated using(user_id=auth.uid() or exists(select 1 from public.clips c where c.id=clip_id and c.user_id=auth.uid()));
create policy clip_saves_read on public.clip_saves for select to authenticated using(user_id=auth.uid());
create policy clip_saves_add on public.clip_saves for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.clips c where c.id=clip_id and c.status='published' and c.allow_saving and private.clip_visible(c.id)));
create policy clip_saves_delete on public.clip_saves for delete to authenticated using(user_id=auth.uid());
create policy clip_dismissals_owner on public.clip_dismissals for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and private.clip_visible(clip_id));
-- One reply level; lock the clip so disabling comments and posting cannot race.
create function private.clip_comment_guard() returns trigger language plpgsql security definer set search_path='' as $$declare c public.clips;begin
 select * into c from public.clips where id=new.clip_id for share;
 if c.status<>'published' or not c.comments_enabled or not private.clip_visible(c.id) then raise exception 'Comments disabled';end if;
 if new.parent_id is not null and not exists(select 1 from public.clip_comments where id=new.parent_id and clip_id=new.clip_id and parent_id is null) then raise exception 'Reply to a top-level comment only';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':clip-comment',0));
 if (select count(*) from public.clip_comments where user_id=auth.uid() and created_at>now()-interval '1 minute')>=10 then raise exception 'Comment rate limit';end if;
 new.created_at=now();return new;end$$;
revoke all on function private.clip_comment_guard() from public,anon,authenticated;
create trigger clip_comment_guard before insert on public.clip_comments for each row execute function private.clip_comment_guard();
create function private.nova_clip_watch(p_clip uuid,p_token uuid default null,p_seconds numeric default 0,p_completed boolean default false) returns uuid language plpgsql security definer set search_path='' as $$declare v private.clip_views;c public.clips;elapsed numeric;begin
 if auth.uid() is null or not private.clip_visible(p_clip) then raise exception 'Clip unavailable';end if;
 select * into c from public.clips where id=p_clip;
 if c.user_id=auth.uid() or c.status<>'published' then return null;end if;
 if p_token is null then
 insert into private.clip_views(user_id,clip_id) values(auth.uid(),p_clip) on conflict(user_id,clip_id) do update set token=gen_random_uuid(),started_at=clock_timestamp() returning token into p_token;return p_token;
 end if;
 select * into v from private.clip_views where user_id=auth.uid() and clip_id=p_clip and token=p_token for update;
 if not found then return null;end if;
 elapsed=least(180,extract(epoch from clock_timestamp()-v.started_at),greatest(0,coalesce(p_seconds,0)),coalesce(c.duration_seconds,180));
 update private.clip_views set watched_seconds=greatest(watched_seconds,elapsed),qualified=qualified or elapsed>=least(3,coalesce(c.duration_seconds,3)),completed=completed or (coalesce(p_completed,false) and c.duration_seconds is not null and elapsed>=c.duration_seconds*0.9) where user_id=auth.uid() and clip_id=p_clip;
 return p_token;end$$;
create function private.nova_clip_metrics(p_clip uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.clip_visible(p_clip) then raise exception 'Clip unavailable';end if;
 return jsonb_build_object('likes',(select count(*) from public.clip_likes where clip_id=p_clip),'comments',(select count(*) from public.clip_comments where clip_id=p_clip),'views',(select count(*) from private.clip_views where clip_id=p_clip and qualified),'saves',case when exists(select 1 from public.clips where id=p_clip and user_id=auth.uid()) then (select count(*) from public.clip_saves where clip_id=p_clip) else null end,'completed',case when exists(select 1 from public.clips where id=p_clip and user_id=auth.uid()) then (select count(*) from private.clip_views where clip_id=p_clip and completed) else null end,'avg_watch_seconds',case when exists(select 1 from public.clips where id=p_clip and user_id=auth.uid()) then (select round(avg(watched_seconds),1) from private.clip_views where clip_id=p_clip and qualified) else null end);
end$$;
create function public.nova_clips_feed(p_mode text default 'for_you',p_offset int default 0,p_limit int default 10) returns setof jsonb language sql stable security invoker set search_path='' as $$
 select to_jsonb(c)||jsonb_build_object('metrics',private.nova_clip_metrics(c.id),'liked',exists(select 1 from public.clip_likes l where l.clip_id=c.id and l.user_id=auth.uid()),'saved',exists(select 1 from public.clip_saves s where s.clip_id=c.id and s.user_id=auth.uid()),'following',exists(select 1 from public.user_follows f where f.followed_id=c.user_id and f.user_id=auth.uid()))
 from public.clips c where c.status='published'
 and (p_mode<>'following' or exists(select 1 from public.user_follows f where f.user_id=auth.uid() and f.followed_id=c.user_id))
 and (p_mode<>'saved' or exists(select 1 from public.clip_saves s where s.user_id=auth.uid() and s.clip_id=c.id))
 and (p_mode<>'for_you' or not exists(select 1 from public.clip_dismissals d where d.user_id=auth.uid() and d.clip_id=c.id))
 and p_mode in ('for_you','following','saved')
 order by case when p_mode='for_you' and coalesce((select recommendations from public.user_settings where user_id=auth.uid()),false) then
 (select count(*) from public.user_interests i where i.user_id=auth.uid() and i.topic=any(c.topics)) +
 (case when exists(select 1 from public.user_follows f where f.user_id=auth.uid() and f.followed_id=c.user_id) then 2 else 0 end) +
 (select count(distinct topic) from public.clip_likes l join public.clips liked on liked.id=l.clip_id cross join lateral unnest(liked.topics) topic where l.user_id=auth.uid() and topic=any(c.topics)) else 0 end desc,c.published_at desc,c.id desc
 limit least(20,greatest(1,p_limit)) offset least(10000,greatest(0,p_offset));
$$;
create function public.nova_clip_metrics(p_clip uuid) returns jsonb language sql security invoker set search_path='' as $$select private.nova_clip_metrics(p_clip)$$;
create function public.nova_clip_watch(p_clip uuid,p_token uuid default null,p_seconds numeric default 0,p_completed boolean default false) returns uuid language sql security invoker set search_path='' as $$select private.nova_clip_watch(p_clip,p_token,p_seconds,p_completed)$$;
revoke all on function private.nova_clip_metrics(uuid),private.nova_clip_watch(uuid,uuid,numeric,boolean),public.nova_clip_metrics(uuid),public.nova_clip_watch(uuid,uuid,numeric,boolean),public.nova_clips_feed(text,int,int) from public,anon,authenticated;
grant execute on function private.nova_clip_metrics(uuid),private.nova_clip_watch(uuid,uuid,numeric,boolean),public.nova_clip_metrics(uuid),public.nova_clip_watch(uuid,uuid,numeric,boolean),public.nova_clips_feed(text,int,int) to authenticated;
create index clips_published_page on public.clips(status,published_at desc,id desc);
insert into public.nova_schema_versions(version) values('20261014_nova_v1_4');
commit;
