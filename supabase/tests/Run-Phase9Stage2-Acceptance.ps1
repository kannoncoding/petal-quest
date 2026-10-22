param()
$ErrorActionPreference = 'Stop'
$parents = @()
$launcherStage = 'runtime preflight'
try {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCommand) { $nodePath = $nodeCommand.Source }
    else { $nodePath = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' }
    if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) { throw 'Node unavailable' }
    $runtimeVersion = & $nodePath --version
    if ($LASTEXITCODE -ne 0 -or $runtimeVersion -notmatch '^v\d+\.\d+\.\d+$') { throw 'Node preflight failed' }
    $launcherStage = 'private credential entry'
    Write-Host 'Use three dedicated, confirmed QA parent accounts. Passwords stay hidden and are sent only to this local process in memory.'
    foreach ($letter in @('a','b','c')) {
        $defaultEmail = "qa-parent-$letter@example.com"
        $email = $defaultEmail
        if ([string]::IsNullOrWhiteSpace($email)) { $email = $defaultEmail }
        $secret = Read-Host "$email password" -AsSecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secret.Dispose() }
        $parents += @{email=$email; password=$password}
        $password = $null
    }
    $launcherStage = 'starting verification process'
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $nodePath
    $start.Arguments = '"' + (Join-Path $PSScriptRoot 'phase9-stage2-live.mjs') + '"'
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $process = [System.Diagnostics.Process]::Start($start)
    try {
        $launcherStage = 'sending credentials through private stdin'
        $payload = ConvertTo-Json -InputObject $parents -Compress
        $inputBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($payload)
        $process.StandardInput.BaseStream.Write($inputBytes,0,$inputBytes.Length)
        $process.StandardInput.BaseStream.Flush()
        $process.StandardInput.Close()
        [Array]::Clear($inputBytes,0,$inputBytes.Length)
        $inputBytes = $null
        $payload = $null
        foreach ($parent in $parents) { $parent.password = $null }; $parents = @()
        $process.WaitForExit()
        $result = $process.ExitCode
    } finally { $process.Dispose() }
    Write-Host "Finished. Exit code $result (0 complete, 1 failed, 2 blocked or owner audit unverified)."
} catch {
    Write-Host "Launcher stopped during: $launcherStage. No credentials or raw error details logged."
    $result = 1
} finally {
    $parents = $null
    $password = $null
    $payload = $null
    if ($inputBytes) { [Array]::Clear($inputBytes,0,$inputBytes.Length) }
    $inputBytes = $null
}
Read-Host 'Press Enter to close'
exit $result
