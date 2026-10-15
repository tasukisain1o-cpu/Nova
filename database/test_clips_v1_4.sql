-- Fixtures and changes are transaction-only, rolled back at the end.
begin;
insert into auth.users(id,email) values
 ('c1140000-0000-4000-8000-000000000001','nova-test-clips-author@example.invalid'),
 ('c2140000-0000-4000-8000-000000000002','nova-test-clips-viewer@example.invalid');
set local role authenticated;
select set_config('request.jwt.claim.sub','c1140000-0000-4000-8000-000000000001',true);
insert into public.clips(id,user_id,video_url,media_path,title,duration_seconds,topics,visibility) values('c0140000-0000-4000-8000-000000000001',auth.uid(),'test.webm',auth.uid()::text||'/test.webm','Public fixture',10,array['music'],'public');
insert into public.clips(id,user_id,video_url,status) values('c0140000-0000-4000-8000-000000000002',auth.uid(),'draft.webm','draft');
insert into public.clips(id,user_id,video_url,visibility) values('c0140000-0000-4000-8000-000000000003',auth.uid(),'private.webm','private');
update public.clips set cover_path=auth.uid()::text||'/cover.jpg' where id='c0140000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','c2140000-0000-4000-8000-000000000002',true);
do $test$ begin
 if (select count(*) from public.clips where id::text like 'c0140000%')<>1 then raise exception 'Draft/private clip leaked';end if;
 if (select count(*) from public.nova_clips_feed() r where r->>'id'='c0140000-0000-4000-8000-000000000001')<>1 then raise exception 'Feed missing clip';end if;
 if exists(select 1 from public.nova_clips_feed('following') r where r->>'id'='c0140000-0000-4000-8000-000000000001') then raise exception 'Following feed unfiltered';end if;
 if not private.social_media_access('c1140000-0000-4000-8000-000000000001/cover.jpg') then raise exception 'Visible cover denied';end if;
 update public.clips set title='Hacked' where id='c0140000-0000-4000-8000-000000000001';if found then raise exception 'Non-owner edited clip';end if;
 begin perform public.nova_clip_metrics('c0140000-0000-4000-8000-000000000002');raise exception 'Draft metrics leaked';exception when raise_exception then if sqlerrm<>'Clip unavailable' then raise;end if;end;
 begin perform 1 from private.clip_views;raise exception 'Raw watch history readable';exception when insufficient_privilege then null;end;
end $test$;
insert into public.clip_likes(clip_id,user_id) values('c0140000-0000-4000-8000-000000000001',auth.uid());
insert into public.clip_saves(clip_id,user_id) values('c0140000-0000-4000-8000-000000000001',auth.uid());
insert into public.clip_comments(id,clip_id,user_id,body) values('cc140000-0000-4000-8000-000000000001','c0140000-0000-4000-8000-000000000001',auth.uid(),'<script>plain text fixture</script>');
insert into public.clip_comments(id,clip_id,user_id,parent_id,body) values('cc140000-0000-4000-8000-000000000002','c0140000-0000-4000-8000-000000000001',auth.uid(),'cc140000-0000-4000-8000-000000000001','Reply');
select public.nova_clip_follow('c0140000-0000-4000-8000-000000000001');
select public.nova_clip_follow('c0140000-0000-4000-8000-000000000001');
do $test$ declare token uuid;begin
 if (select count(*) from public.nova_clips_feed('following') r where r->>'id'='c0140000-0000-4000-8000-000000000001')<>1 then raise exception 'Following feed missing clip';end if;
 if (public.nova_clip_metrics('c0140000-0000-4000-8000-000000000001')->>'likes')::int<>1 then raise exception 'Like count wrong';end if;
 if (public.nova_clip_metrics('c0140000-0000-4000-8000-000000000001')->>'comments')::int<>2 then raise exception 'Comment count wrong';end if;
 token=public.nova_clip_watch('c0140000-0000-4000-8000-000000000001');
 perform public.nova_clip_watch('c0140000-0000-4000-8000-000000000001',token,100,true);
 if (public.nova_clip_metrics('c0140000-0000-4000-8000-000000000001')->>'views')::int<>0 then raise exception 'Instant fake view counted';end if;
end $test$;
reset role;
update private.clip_views set started_at=clock_timestamp()-interval '12 seconds' where user_id='c2140000-0000-4000-8000-000000000002';
select set_config('nova.test.token',(select token::text from private.clip_views where user_id='c2140000-0000-4000-8000-000000000002'),true);
set local role authenticated;
select public.nova_clip_watch('c0140000-0000-4000-8000-000000000001',current_setting('nova.test.token')::uuid,10,true);
select public.nova_clip_watch('c0140000-0000-4000-8000-000000000001',current_setting('nova.test.token')::uuid,10,true);
insert into public.clip_dismissals(user_id,clip_id) values(auth.uid(),'c0140000-0000-4000-8000-000000000001');
do $test$ begin
 if (public.nova_clip_metrics('c0140000-0000-4000-8000-000000000001')->>'views')::int<>1 then raise exception 'View deduplication failed';end if;
 if exists(select 1 from public.nova_clips_feed() r where r->>'id'='c0140000-0000-4000-8000-000000000001') then raise exception 'Dismissed clip shown';end if;
end $test$;
select set_config('request.jwt.claim.sub','c1140000-0000-4000-8000-000000000001',true);
update public.clips set comments_enabled=false,allow_saving=false where id='c0140000-0000-4000-8000-000000000001';
do $test$ begin
 if (public.nova_clip_metrics('c0140000-0000-4000-8000-000000000001')->>'subscriptions')::int<>1 then raise exception 'Subscription attribution/deduplication failed';end if;
 if (public.nova_clip_metrics('c0140000-0000-4000-8000-000000000001')->>'completed')::int<>1 then raise exception 'Creator completion missing';end if;
 if public.nova_clip_watch('c0140000-0000-4000-8000-000000000001') is not null then raise exception 'Own view counted';end if;
end $test$;
select set_config('request.jwt.claim.sub','c2140000-0000-4000-8000-000000000002',true);
do $test$ begin
 begin insert into public.clip_comments(clip_id,user_id,body) values('c0140000-0000-4000-8000-000000000001',auth.uid(),'Disabled');raise exception 'Disabled comments accepted';exception when raise_exception then if sqlerrm<>'Comments disabled' then raise;end if;when insufficient_privilege then null;end;
end $test$;
select set_config('request.jwt.claim.sub','c1140000-0000-4000-8000-000000000001',true);
delete from public.clip_comments where id='cc140000-0000-4000-8000-000000000001';
do $test$ begin if exists(select 1 from public.clip_comments where clip_id='c0140000-0000-4000-8000-000000000001') then raise exception 'Creator moderation/cascade failed';end if;end $test$;
reset role;
do $test$ begin if has_function_privilege('anon','public.nova_clips_feed(text,integer,integer)','execute') then raise exception 'Anon feed access';end if;end $test$;
rollback;
select 'PASS: Clips privacy, feed filters, covers, owner edits, comments/replies, likes/saves, watch timing/deduplication, creator moderation, anonymous denial. Fixtures rolled back.' as result;
