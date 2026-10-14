-- NOVA v1.1: keep privileged implementations out of the exposed API schema.
begin;
do $migration$
declare r record;args text;sig text;ddl text;
begin
for r in select p.oid,p.proname,pg_get_function_arguments(p.oid) as arguments,pg_get_function_identity_arguments(p.oid) as identity_args,pg_get_function_result(p.oid) as result,p.proargnames from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and p.proname like 'nova_%'
loop
select string_agg(quote_ident(a),',') into args from unnest(r.proargnames) a;
execute format('alter function public.%I(%s) set schema private',r.proname,r.identity_args);
ddl=format('create function public.%I(%s) returns %s language sql security invoker set search_path=%L as %L',r.proname,r.arguments,r.result,'',format('select private.%I(%s)',r.proname,args));
execute ddl;
execute format('revoke all on function public.%I(%s) from public,anon,authenticated',r.proname,r.identity_args);
execute format('grant execute on function public.%I(%s) to authenticated',r.proname,r.identity_args);
end loop;
end $migration$;
insert into public.nova_schema_versions(version) values('20261014_nova_v1_1');
commit;
select 'Privileged implementations moved to private; RPC signatures preserved' as result;
