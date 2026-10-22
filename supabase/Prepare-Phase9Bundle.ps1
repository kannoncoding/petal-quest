$ErrorActionPreference='Stop'
$files=@('202610210008_phase9_parent.sql','202610210009_phase9_tasksets.sql','202610210010_phase9_review_guard.sql','202610220011_phase9_accounting.sql','202610220012_phase9_legacy_materialization.sql')
$parts=[Collections.Generic.List[string]]::new()
$parts.Add('-- LOCAL PHASE9 FORWARD UPGRADE. Review before applying. This generator executes no SQL.')
$parts.Add('begin;')
$parts.Add(@'
do $phase9_preflight$
begin
 if to_regprocedure('public.get_teen_dashboard(date,date)') is null
 or to_regclass('public.day_appeals') is null then
  raise exception 'Accepted Phase8 prerequisite missing; stop and report this message.';
 end if;
 if to_regclass('public.catalogue_versions') is not null then
  raise exception 'Phase9 already exists; do not rerun this initial forward upgrade.';
 end if;
end $phase9_preflight$;
'@)
foreach($file in $files){
 $source=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot ('migrations\'+$file))
 $parts.Add('-- SOURCE: migrations/'+$file)
 $parts.Add([regex]::Replace($source,'(?m)^\s*(begin|commit);\s*$',''))
}
$parts.Add('commit;')
$parts.Add(@'
-- Schema readiness only; this does not execute or certify business workflows.
select
 to_regprocedure('public.get_parent_dashboard(uuid,uuid,date,date)') is not null as parent_dashboard_ready,
 to_regprocedure('public.correct_occurrence(uuid,text,integer,text,uuid)') is not null as corrections_ready,
 to_regprocedure('public.review_bonus(uuid,text,integer,text,uuid)') is not null as bonus_ready,
 to_regprocedure('public.save_reflection_note(uuid,date,text,integer,uuid)') is not null as notes_ready,
 (select count(*)=11 and bool_and(c.relrowsecurity)
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where (n.nspname='public' and c.relname in ('catalogue_versions','parent_actions','day_tasksets','occurrence_corrections','deduction_reversals','bonus_activities','bonus_reviews','appeal_resolutions','reflection_notes','reflection_note_history'))
   or (n.nspname='petal_private' and c.relname='day_edit_versions')) as rls_enabled;
'@)
$parts -join "`n" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'phase9-parent-upgrade.sql') -Encoding utf8
Write-Output 'Prepared local Phase9 forward bundle. No SQL executed.'
