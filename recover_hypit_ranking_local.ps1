param(
    [Parameter(Mandatory=$true)][string]$FailedBuildId,
    [string]$HypitRoot = 'D:\AI\hypit',
    [string]$Output = 'D:\AI\hypit\examples\ranking-football-local\output\final-local-recovered.mp4'
)

$ErrorActionPreference = 'Stop'

$Workspace = Join-Path $HypitRoot 'examples\ranking-football-local'
$Runtime = Join-Path $Workspace 'hypit.runtime.local-ai.json'
$RecoveryRun = Join-Path $Workspace 'recover-local.svrun'
$OutputDir = Split-Path -Parent $Output

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

if (-not (Test-Path -LiteralPath $Workspace)) {
    throw "Workspace missing: $Workspace"
}
if (-not (Test-Path -LiteralPath $Runtime)) {
    throw "Runtime profile missing: $Runtime"
}

Write-Host '=== RECOVER FAILED HYPIT RANKING BUILD ==='
Write-Host "Failed build: $FailedBuildId"
Write-Host ''

# The first deploy on Windows PowerShell 5.1 wrote package.json with UTF-8 BOM.
# HyperFrames/Producer has a strict JSON.parse(readFileSync(..., "utf-8")) path and
# rejects that BOM during render preparation. Normalize the authored workspace JSON
# before invoking HyperFrames.
$PackagePath = Join-Path $Workspace 'package.json'
if (Test-Path -LiteralPath $PackagePath) {
    $packageText = Get-Content -Raw -LiteralPath $PackagePath
    Write-Utf8NoBom -Path $PackagePath -Content $packageText
}

# Force software browser mode so this recovery also bypasses the separate Chrome
# hardware-GPU probe path on this Windows machine.
$runtimeJson = Get-Content -Raw -LiteralPath $Runtime | ConvertFrom-Json
if ($null -eq $runtimeJson.endpoints.'hyperframes.local'.config) {
    $runtimeJson.endpoints.'hyperframes.local' | Add-Member -NotePropertyName config -NotePropertyValue ([pscustomobject]@{})
}
$runtimeJson.endpoints.'hyperframes.local'.config | Add-Member -NotePropertyName browserGpu -NotePropertyValue 'software' -Force
Write-Utf8NoBom -Path $Runtime -Content ($runtimeJson | ConvertTo-Json -Depth 30)

# Reuse the four expensive public outputs that feed the final composition.
# Reusing take-one/take-two also prunes their presenter.image dependency.
$run = @"
<?svml using="@hypit/run-markup@1"?>

<svrun version="1">
  <author source="./reference-local.svml"/>

  <build-record id="reuse-broll-goat" build="$FailedBuildId" output="broll-goat.image"/>
  <build-record id="reuse-broll-hattrick" build="$FailedBuildId" output="broll-hattrick.image"/>
  <build-record id="reuse-take-one" build="$FailedBuildId" output="take-one.video"/>
  <build-record id="reuse-take-two" build="$FailedBuildId" output="take-two.video"/>

  <satisfy output="broll-goat.image" candidate="reuse-broll-goat"/>
  <satisfy output="broll-hattrick.image" candidate="reuse-broll-hattrick"/>
  <satisfy output="take-one.video" candidate="reuse-take-one"/>
  <satisfy output="take-two.video" candidate="reuse-take-two"/>

  <target output="final.video"/>
</svrun>
"@

Write-Utf8NoBom -Path $RecoveryRun -Content $run
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $Workspace
try {
    Write-Host '[1/4] Inspecting failed build outputs...'
    & hypit.cmd inspect $FailedBuildId --verbose
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect failed build $FailedBuildId"
    }

    Write-Host '[2/4] Planning recovery run...'
    & hypit.cmd plan .\recover-local.svrun --runtime .\hypit.runtime.local-ai.json
    if ($LASTEXITCODE -ne 0) {
        throw 'Recovery plan failed. Confirm the failed build contains broll-goat.image, broll-hattrick.image, take-one.video and take-two.video.'
    }

    Write-Host '[3/4] Building only the remaining deterministic/render steps...'
    $buildText = (& hypit.cmd build .\recover-local.svrun --runtime .\hypit.runtime.local-ai.json --title ranking-football-local-recovery --follow --max-wait-ms 1800000 --json | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw ('Recovery build failed with exit code ' + $LASTEXITCODE + [Environment]::NewLine + $buildText)
    }

    $build = $buildText | ConvertFrom-Json
    $buildId = [string]$build.build.id
    $outcome = [string]$build.build.work.outcome
    if ([string]::IsNullOrWhiteSpace($buildId) -or $outcome -ne 'complete') {
        throw "Recovery Build outcome was '$outcome'."
    }

    Write-Host "  [OK] Recovery build complete: $buildId"
    Write-Host '[4/4] Exporting final.video...'
    & hypit.cmd get $buildId --output 'final.video' --to $Output
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to export recovered final.video.'
    }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host '[PASS] Recovery completed without re-running Z-Image/Wan.'
Write-Host "Output: $Output"
