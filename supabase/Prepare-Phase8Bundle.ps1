$ErrorActionPreference='Stop'
$files=@('202610210005_phase8_teen.sql','202610210006_phase8_deductions.sql','202610210007_phase8_owner_followup.sql')
$parts=[Collections.Generic.List[string]]::new()
$parts.Add('-- LOCAL PHASE8 UPGRADE ONLY. Review owner readiness decisions before applying. No SQL is executed by this script.')
$parts.Add('begin;')
$parts.Add(@'
-- Forward upgrade of the accepted Phase7 development schema only.
do $phase8_preflight$
begin
 if to_regclass('public.health_installations') is null
    or to_regprocedure('public.get_checkin_policy()') is null then
  raise exception 'Phase7 prerequisite missing; stop and report this message.';
 end if;
 if to_regclass('public.daily_accounting') is not null then
  raise exception 'Phase8 schema already exists; do not rerun this initial upgrade.';
 end if;
end $phase8_preflight$;
'@)
foreach($file in $files){
 $source=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot ('migrations\'+$file))
 $parts.Add('-- SOURCE: migrations/'+$file)
 $parts.Add([regex]::Replace($source,'(?m)^\s*(begin|commit);\s*$',''))
}
$parts.Add('commit;')
$parts.Add(@'
select effective_from,
 jsonb_array_length(catalogue->'duties') as task_variants,
 jsonb_array_length(catalogue->'rewards') as rewards,
 jsonb_array_length(catalogue->'achievements') as achievements
from petal_private.phase8_catalogue where singleton;
'@)
$parts -join "`n" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'phase8-teen-upgrade.sql') -Encoding utf8
Write-Output 'Prepared local Phase8 upgrade bundle. No SQL executed.'
