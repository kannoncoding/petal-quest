begin;
create function public.get_contract_version() returns jsonb
language sql security invoker set search_path='' as $$
 select jsonb_build_object('api_contract_version',1,'family_timezone','America/Costa_Rica','week_start','Sunday');
$$;
revoke execute on function public.get_contract_version() from public,anon;
grant execute on function public.get_contract_version() to authenticated;
notify pgrst, 'reload schema';
commit;
