-- DEVELOPMENT OWNER SQL EDITOR ONLY. Run the whole file, including ROLLBACK.
-- Test Family 1 only. No clocks, sessions, health records or existing day facts change.
-- A disposable actor and its future occurrences exist only in this transaction.
-- If interrupted, issue ROLLBACK in the same SQL session. Never replace it with COMMIT.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
create temporary table phase10_vacation_checks(check_name text,passed boolean) on commit drop;
alter table pg_temp.phase10_vacation_checks enable row level security;
do $check$
declare
 f uuid; disposable uuid; dt date; overlay jsonb; baseline jsonb; snapshots jsonb;
 original_tasks text; original_wallet text; original_manifests text;
 all_totals boolean:=true; exclusions boolean:=true; removed boolean:=true;
 renamed boolean:=true; redistributed boolean:=true; deterministic boolean:=true;
 new_snapshots boolean:=true; rule_snapshots boolean:=true; count_days integer:=0;
begin
 if current_user in ('authenticated','anon') then raise exception 'Development owner SQL Editor required';end if;
 if (select count(*) from public.families where name='Test Family 1' and timezone='America/Costa_Rica')<>1 then
  raise exception 'Exactly one fictional Test Family 1 required; no fixture created';
 end if;
 select id into strict f from public.families where name='Test Family 1';
 if exists(select 1 from public.vacation_policy_versions where family_id=f) then
  raise exception 'Custom vacation schedule exists; stop and report before testing default policy';
 end if;
 if (select count(*) from public.task_definitions where family_id=f)<>28 then
  raise exception 'Expected complete 28-variant fictional catalogue; stop and report';
 end if;
 select md5(coalesce(jsonb_agg(to_jsonb(o) order by o.id)::text,'[]')) into original_tasks from public.task_occurrences o where family_id=f;
 select md5(coalesce(jsonb_agg(to_jsonb(w) order by w.id)::text,'[]')) into original_wallet from public.wallet_events w where family_id=f;
 select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.teen_id,m.local_date)::text,'[]')) into original_manifests from public.day_tasksets m where family_id=f;
 insert into pg_temp.phase10_vacation_checks values
 ('default_school_mode_on_November27',not petal_private.is_vacation(f,date '2026-11-27')),
 ('default_vacation_starts_November28',petal_private.is_vacation(f,date '2026-11-28'));

 insert into public.family_actors(family_id,role) values(f,'teen') returning id into disposable;
 for dt in select date '2026-11-28'+i from generate_series(0,6) s(i) loop
  count_days:=count_days+1;
  overlay:=petal_private.vacation_day_catalogue(f,dt);
  -- Independently reconstruct the effective ordinary baseline for this date.
  with base as (
   select d.catalogue_key,coalesce((v.payload->>'points')::integer,r.points) points,
    coalesce((v.payload->>'enabled')::boolean,d.enabled) enabled,
    case when v.id is null then r.weekdays else array(select value::integer from jsonb_array_elements_text(v.payload->'weekdays')) end weekdays
   from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version
   left join lateral(select * from public.catalogue_versions where family_id=f and catalogue_key=d.catalogue_key and kind in ('task','rule') and effective_from<=dt order by effective_from desc,created_at desc,id desc limit 1) v on true
   where d.family_id=f
  ) select jsonb_agg(jsonb_build_object('catalogue_key',catalogue_key,'points',points) order by catalogue_key) into baseline
   from base where enabled and extract(dow from dt)::integer=any(weekdays);
  all_totals:=all_totals and (select sum((value->>'points')::integer)=100 from jsonb_array_elements(overlay));
  removed:=removed and not exists(select 1 from jsonb_array_elements(overlay) where value->>'catalogue_key' in ('duty-wd-003','duty-we-004'));
  exclusions:=exclusions and not exists(
   select 1 from jsonb_array_elements(baseline) b
   left join lateral(select value from jsonb_array_elements(overlay) where value->>'catalogue_key'=b->>'catalogue_key') o on true
   where right(b->>'catalogue_key',3) in ('007','008','009','010','011','012','013')
    and (o.value is null or o.value->>'points' is distinct from b->>'points'));
  redistributed:=redistributed and not exists(
   select 1 from jsonb_array_elements(overlay) o join jsonb_array_elements(baseline) b on o->>'catalogue_key'=b->>'catalogue_key'
   where (o->>'points')::integer<(b->>'points')::integer);
  renamed:=renamed and not exists(select 1 from jsonb_array_elements(overlay)
   where (value->>'catalogue_key'='duty-wd-002' and value->>'title'<>'Shower + Room @4PM')
    or (value->>'catalogue_key'='duty-wd-005' and value->>'title'<>'Room clean up @6PM'));
  deterministic:=deterministic and overlay=petal_private.vacation_day_catalogue(f,dt);

  -- Exercise the real occurrence insertion triggers on a new disposable actor.
  insert into public.task_occurrences(family_id,definition_id,teen_id,rule_version_id,local_date,points_snapshot,due_at,title_snapshot)
   select d.family_id,d.id,disposable,r.id,dt,r.points,
    case when r.local_due_time is not null then (dt+r.local_due_time) at time zone 'America/Costa_Rica' end,d.title
   from public.task_definitions d join public.rule_versions r on r.definition_id=d.id and r.current_version
   where d.family_id=f and d.enabled and extract(dow from dt)::integer=any(r.weekdays);
  select jsonb_agg(jsonb_build_object('catalogue_key',d.catalogue_key,'title',o.title_snapshot,'points',o.points_snapshot) order by d.catalogue_key)
   into snapshots from public.task_occurrences o join public.task_definitions d on d.id=o.definition_id
   where o.family_id=f and o.teen_id=disposable and o.local_date=dt;
  new_snapshots:=new_snapshots and snapshots=(select jsonb_agg(jsonb_build_object('catalogue_key',value->>'catalogue_key','title',value->>'title','points',(value->>'points')::integer) order by value->>'catalogue_key') from jsonb_array_elements(overlay));
  rule_snapshots:=rule_snapshots and not exists(select 1 from public.task_occurrences o join public.rule_versions r on r.id=o.rule_version_id
   where o.family_id=f and o.teen_id=disposable and o.local_date=dt and o.points_snapshot<>r.points);
 end loop;
 insert into pg_temp.phase10_vacation_checks values
 ('all_seven_weekdays_preview_maximum100',count_days=7 and coalesce(all_totals,false)),
 ('excluded_optional_duties_keep_original_points',coalesce(exclusions,false)),
 ('school_study_duties_removed',coalesce(removed,false)),
 ('weekday_titles_change_as_approved',coalesce(renamed,false)),
 ('remaining_duties_never_lose_points',coalesce(redistributed,false)),
 ('repeated_preview_is_deterministic',coalesce(deterministic,false)),
 ('new_occurrence_snapshots_match_preview_all_seven_days',coalesce(new_snapshots,false)),
 ('immutable_rule_points_match_new_occurrences',coalesce(rule_snapshots,false)),
 ('original_occurrences_unchanged',original_tasks=(select md5(coalesce(jsonb_agg(to_jsonb(o) order by o.id)::text,'[]')) from public.task_occurrences o where family_id=f and teen_id<>disposable)),
 ('original_day_manifests_unchanged',original_manifests=(select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.teen_id,m.local_date)::text,'[]')) from public.day_tasksets m where family_id=f)),
 ('all_wallet_events_unchanged',original_wallet=(select md5(coalesce(jsonb_agg(to_jsonb(w) order by w.id)::text,'[]')) from public.wallet_events w where family_id=f));
 set constraints all immediate;
 insert into pg_temp.phase10_vacation_checks values ('all_deferred_constraints_pass_before_rollback',true);
end
$check$;
select check_name,passed from pg_temp.phase10_vacation_checks order by check_name;
rollback;
-- No COMMIT. No mutation survives this script; notification requests roll back too.
