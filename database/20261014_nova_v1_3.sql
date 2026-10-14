-- Owner dashboard. No client-side role assignment, no access to private conversations.
begin;
create table private.admin_audit (
 id bigint generated always as identity primary key,
 actor_id uuid references auth.users(id) on delete set null,
 report_id uuid references public.reports(id) on delete set null,
 old_status text not null, new_status text not null,
 created_at timestamptz not null default now()
);
alter table private.admin_audit enable row level security;
revoke all on private.admin_audit from public,anon,authenticated;
create index reports_status_created on public.reports(status,created_at desc,id desc);
revoke update(status) on public.reports from authenticated;

create function private.nova_admin_summary() returns jsonb language plpgsql stable security definer set search_path='' as $fn$
begin
 if not private.is_admin() then return jsonb_build_object('is_admin',false); end if;
 return jsonb_build_object('is_admin',true,'users',(select count(*) from public.profiles),'groups',(select count(*) from public.nova_groups where kind='group'),'channels',(select count(*) from public.nova_groups where kind='channel'),'messages',(select count(*) from public.messages),'posts',(select count(*) from public.posts),'clips',(select count(*) from public.clips),'open_reports',(select count(*) from public.reports where status='open'),'checked_at',now());
end $fn$;
create function private.nova_admin_reports(p_status text default 'open',p_before timestamptz default 'infinity',p_before_id uuid default 'ffffffff-ffff-ffff-ffff-ffffffffffff') returns setof jsonb language plpgsql stable security definer set search_path='' as $fn$
begin
 if not private.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_status not in ('open','reviewed','resolved') then raise exception 'Invalid report status'; end if;
 return query select jsonb_build_object('id',r.id,'entity_type',r.entity_type,'entity_id',r.entity_id,'reason',r.reason,'status',r.status,'created_at',r.created_at,'reporter',p.username)
 from public.reports r left join public.profiles p on p.id=r.user_id
 where r.status=p_status and (r.created_at,r.id)<(p_before,p_before_id)
 order by r.created_at desc,r.id desc limit 50;
end $fn$;
create function private.nova_admin_resolve(p_report uuid,p_status text) returns void language plpgsql security definer set search_path='' as $fn$
declare previous text;
begin
 if not private.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_status not in ('open','reviewed','resolved') then raise exception 'Invalid report status'; end if;
 select status into previous from public.reports where id=p_report for update;
 if not found then raise exception 'Report not found'; end if;
 if previous=p_status then return; end if;
 update public.reports set status=p_status where id=p_report;
 insert into private.admin_audit(actor_id,report_id,old_status,new_status) values(auth.uid(),p_report,previous,p_status);
end $fn$;
create function private.nova_admin_audit() returns setof jsonb language plpgsql stable security definer set search_path='' as $fn$
begin
 if not private.is_admin() then raise exception 'Admin access required' using errcode='42501'; end if;
 return query select jsonb_build_object('id',a.id,'report_id',a.report_id,'old_status',a.old_status,'new_status',a.new_status,'actor',p.username,'created_at',a.created_at) from private.admin_audit a left join public.profiles p on p.id=a.actor_id order by a.id desc limit 50;
end $fn$;
create function public.nova_admin_summary() returns jsonb language sql security invoker set search_path='' as $$select private.nova_admin_summary()$$;
create function public.nova_admin_reports(p_status text default 'open',p_before timestamptz default 'infinity',p_before_id uuid default 'ffffffff-ffff-ffff-ffff-ffffffffffff') returns setof jsonb language sql security invoker set search_path='' as $$select * from private.nova_admin_reports(p_status,p_before,p_before_id)$$;
create function public.nova_admin_resolve(p_report uuid,p_status text) returns void language sql security invoker set search_path='' as $$select private.nova_admin_resolve(p_report,p_status)$$;
create function public.nova_admin_audit() returns setof jsonb language sql security invoker set search_path='' as $$select * from private.nova_admin_audit()$$;
revoke all on function private.nova_admin_summary(),private.nova_admin_reports(text,timestamptz,uuid),private.nova_admin_resolve(uuid,text),private.nova_admin_audit(),public.nova_admin_summary(),public.nova_admin_reports(text,timestamptz,uuid),public.nova_admin_resolve(uuid,text),public.nova_admin_audit() from public,anon,authenticated;
grant execute on function private.nova_admin_summary(),private.nova_admin_reports(text,timestamptz,uuid),private.nova_admin_resolve(uuid,text),private.nova_admin_audit(),public.nova_admin_summary(),public.nova_admin_reports(text,timestamptz,uuid),public.nova_admin_resolve(uuid,text),public.nova_admin_audit() to authenticated;
insert into public.nova_schema_versions(version) values('20261014_nova_v1_3');
commit;
