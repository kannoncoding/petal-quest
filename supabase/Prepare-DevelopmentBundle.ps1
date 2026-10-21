$ErrorActionPreference = 'Stop'
$pieces = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'migrations') -Filter '*.sql' | Sort-Object Name
$bundle = [Collections.Generic.List[string]]::new()
$bundle.Add('-- DEVELOPMENT ONLY: select Petal Quest Dev (hijtwgugzzpjjkuutyfy) in the dashboard.')
$bundle.Add('-- Atomic initial deployment; no synthetic Auth fixture. Stop if a schema already exists.')
$bundle.Add('begin;')
$bundle.Add(@'
do $preflight$
begin
 if exists(select 1 from information_schema.tables where table_schema='public' and table_name='families') then
  raise exception 'Phase 6 families table already exists. Stop; do not rerun the initial deployment.';
 end if;
end $preflight$;
'@)
foreach ($piece in $pieces) {
    $bundle.Add('-- SOURCE: migrations/' + $piece.Name)
    $source = Get-Content -Raw -LiteralPath $piece.FullName
    $bundle.Add([regex]::Replace($source, '(?m)^\s*(begin|commit);\s*$', ''))
}
$bundle.Add('commit;')
$bundle -join "`n" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'deploy-development.sql') -Encoding utf8
Write-Output ('Prepared atomic development bundle from ' + $pieces.Count + ' migrations. No SQL executed.')
