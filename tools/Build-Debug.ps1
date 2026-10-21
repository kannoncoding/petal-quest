param(
    [string]$StudioDirectory = (Join-Path $env:ProgramFiles 'Android\Android Studio'),
    [switch]$IncludeParent
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot -Parent
$jdkDirectory = Join-Path $StudioDirectory 'jbr'
if (-not (Test-Path -LiteralPath (Join-Path $jdkDirectory 'bin\java.exe'))) {
    throw 'Android Studio bundled JDK not found. Supply -StudioDirectory with your Android Studio installation folder.'
}

# Keep Windows Java selector socket paths short and inside the project cache.
# OpenJDK supports this process-local property; no system setting is changed.
$socketDirectory = Join-Path $projectDirectory '.gradle\socket-tmp'
New-Item -ItemType Directory -Path $socketDirectory -Force | Out-Null
$previousJavaHome = $env:JAVA_HOME
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
try {
    $env:JAVA_HOME = $jdkDirectory
    $env:JAVA_TOOL_OPTIONS = ($previousJavaOptions + ' -Djdk.net.unixdomain.tmpdir="' + $socketDirectory + '"').Trim()
    Push-Location -LiteralPath $projectDirectory
    try {
        $buildTasks = @(':app:assembleDebug')
        if ($IncludeParent) { $buildTasks += ':parent:assembleDebug' }
        & .\gradlew.bat @buildTasks --console=plain --no-daemon
        if ($LASTEXITCODE -ne 0) { throw "Android debug build failed with exit code $LASTEXITCODE." }
    }
    finally { Pop-Location }
}
finally {
    $env:JAVA_HOME = $previousJavaHome
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
}
Write-Output ('Debug APK: ' + (Join-Path $projectDirectory 'app\build\outputs\apk\debug\app-debug.apk'))
if ($IncludeParent) { Write-Output ('Parent debug APK: ' + (Join-Path $projectDirectory 'parent\build\outputs\apk\debug\parent-debug.apk')) }
