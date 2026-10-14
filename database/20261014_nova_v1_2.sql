begin;
create or replace function public.nova_chat_list() returns setof jsonb language sql stable security invoker set search_path='' as $fn$
 select jsonb_build_object('id',g.id,'name',g.name,'kind',g.kind,'is_private',g.is_private,'role',mine.role,'muted',mine.muted,'peer_id',case when g.kind='personal' then (select other.user_id from public.group_members other where other.group_id=g.id and other.user_id<>auth.uid() limit 1) else null end,'member_count',(select count(*) from public.group_members gm where gm.group_id=g.id),'last_body',last_msg.body,'last_kind',last_msg.message_kind,'last_message_at',last_msg.created_at,'unread_count',(select count(*) from public.messages unread where unread.group_id=g.id and unread.sender_id<>auth.uid() and unread.created_at>coalesce(mine.last_read_at,'epoch'::timestamptz)))
 from public.group_members mine join public.nova_groups g on g.id=mine.group_id
 left join lateral (select m.body,m.message_kind,m.created_at from public.messages m where m.group_id=g.id order by m.created_at desc,m.id desc limit 1) last_msg on true
 where mine.user_id=auth.uid() order by mine.pinned desc,coalesce(last_msg.created_at,g.created_at) desc,g.id;
$fn$;
create or replace function public.nova_set_interests(p_topics text[]) returns void language plpgsql security invoker set search_path='' as $fn$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if cardinality(p_topics)>10 or exists(select 1 from unnest(p_topics) t where length(btrim(t)) not between 1 and 50) then raise exception 'Up to 10 topics, each 1-50 characters'; end if;
 delete from public.user_interests where user_id=auth.uid();
 insert into public.user_interests(user_id,topic,weight) select auth.uid(),lower(btrim(t)),1 from unnest(p_topics) t group by lower(btrim(t));
end;
$fn$;
revoke all on function public.nova_chat_list(),public.nova_set_interests(text[]) from public,anon;
grant execute on function public.nova_chat_list(),public.nova_set_interests(text[]) to authenticated;
insert into public.nova_schema_versions(version) values ('20261014_nova_v1_2') on conflict do nothing;
commit;
