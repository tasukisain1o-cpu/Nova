-- Run in SQL editor as postgres. Every fixture and role assignment rolls back.
begin;
insert into auth.users(id,email,raw_user_meta_data) values
 ('f0130000-0000-4000-8000-000000000001','nova-test-admin-v13@example.invalid','{"display_name":"Admin test"}'),
 ('f0230000-0000-4000-8000-000000000002','nova-test-member-v13@example.invalid','{"display_name":"Member test"}');
insert into private.app_admins(user_id) values('f0130000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','f0230000-0000-4000-8000-000000000002',true);
insert into public.reports(id,user_id,entity_type,entity_id,reason) values('f0130000-0000-4000-8000-000000000003',auth.uid(),'profile','f0130000-0000-4000-8000-000000000001','Transaction-only fixture');
do $test$
begin
 if public.nova_admin_summary()<>jsonb_build_object('is_admin',false) then raise exception 'Member received stats'; end if;
 begin perform public.nova_admin_reports(); raise exception 'Member read reports'; exception when insufficient_privilege then null; end;
 begin perform public.nova_admin_audit(); raise exception 'Member read audit'; exception when insufficient_privilege then null; end;
 begin perform public.nova_admin_resolve('f0130000-0000-4000-8000-000000000003','resolved'); raise exception 'Member changed report'; exception when insufficient_privilege then null; end;
 begin update public.reports set status='resolved'; raise exception 'Direct update allowed'; exception when insufficient_privilege then null; end;
 begin insert into private.app_admins(user_id) values(auth.uid()); raise exception 'Self promotion allowed'; exception when insufficient_privilege then null; end;
end $test$;
select set_config('request.jwt.claim.sub','f0130000-0000-4000-8000-000000000001',true);
do $test$
begin
 if not (public.nova_admin_summary()->>'is_admin')::boolean then raise exception 'Admin missing'; end if;
 if not exists(select 1 from public.nova_admin_reports() r where r->>'id'='f0130000-0000-4000-8000-000000000003') then raise exception 'Report missing'; end if;
 perform public.nova_admin_resolve('f0130000-0000-4000-8000-000000000003','reviewed');
 perform public.nova_admin_resolve('f0130000-0000-4000-8000-000000000003','resolved');
 if (select count(*) from public.nova_admin_audit() a where a->>'report_id'='f0130000-0000-4000-8000-000000000003')<>2 then raise exception 'Audit missing'; end if;
 if not exists(select 1 from public.nova_admin_reports('resolved') r where r->>'id'='f0130000-0000-4000-8000-000000000003') then raise exception 'Status not saved'; end if;
 begin perform public.nova_admin_resolve('f0130000-0000-4000-8000-000000000003','invalid'); raise exception 'Invalid status accepted'; exception when raise_exception then if sqlerrm<>'Invalid report status' then raise; end if; end;
end $test$;
reset role;
do $test$ begin
 if has_function_privilege('anon','public.nova_admin_summary()','execute') then raise exception 'Anon can execute'; end if;
end $test$;
rollback;
select 'PASS: admin/member isolation, no self-promotion, reports workflow, audit, anonymous denial; fixtures rolled back' as result;
