param(
    [string]$HypitRoot = 'D:\AI\hypit',
    [string]$LocalProjectRoot = 'D:\AI\HypitProjects\TestVideo',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$TemplateDir = Join-Path $RepoRoot 'hypit_examples\ranking-football-local'
$OfficialSample = Join-Path $HypitRoot 'examples\ranking-football'
$Target = Join-Path $HypitRoot 'examples\ranking-football-local'
$ProviderSource = Join-Path $LocalProjectRoot 'packages\provider-comfyui-local'
$BaseRuntimePath = Join-Path $LocalProjectRoot 'hypit.runtime.json'
$RuntimeOutput = Join-Path $Target 'hypit.runtime.local-ai.json'

function Copy-TreeClean {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    & robocopy.exe $Source $Destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD node_modules .hypit dist
    $code = $LASTEXITCODE
    if ($code -gt 7) {
        throw "robocopy failed from '$Source' to '$Destination' with exit code $code"
    }
}

Write-Host '=== DEPLOY HYPIT RANKING-FOOTBALL LOCAL AI ==='
Write-Host "Hypit repo:      $HypitRoot"
Write-Host "Official sample: $OfficialSample"
Write-Host "Target sample:   $Target"
Write-Host ''

foreach ($path in @($TemplateDir, $OfficialSample, $ProviderSource, $BaseRuntimePath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path is missing: $path"
    }
}

if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw 'npm.cmd is unavailable.'
}
if (-not (Get-Command hypit.cmd -ErrorAction SilentlyContinue)) {
    throw 'hypit.cmd is unavailable.'
}
if (-not (Get-Command robocopy.exe -ErrorAction SilentlyContinue)) {
    throw 'robocopy.exe is unavailable.'
}

if ((Test-Path -LiteralPath $Target) -and $Force) {
    Write-Host '[1/6] Removing previous local sample...'
    Remove-Item -LiteralPath $Target -Recurse -Force
}

if (-not (Test-Path -LiteralPath $Target)) {
    Write-Host '[1/6] Copying official ranking-football sample without runtime/build caches...'
    Copy-TreeClean -Source $OfficialSample -Destination $Target
} else {
    Write-Host '[1/6] Reusing existing ranking-football-local directory.'
}

Write-Host '[2/6] Installing local variant author files...'
Copy-Item -LiteralPath (Join-Path $TemplateDir 'reference-local.svml') -Destination (Join-Path $Target 'reference-local.svml') -Force
Copy-Item -LiteralPath (Join-Path $TemplateDir 'reference-local.svrun') -Destination (Join-Path $Target 'reference-local.svrun') -Force

Write-Host '[3/6] Copying the working ComfyUI provider package into the sample...'
$ProviderTarget = Join-Path $Target 'packages\provider-comfyui-local'
if (Test-Path -LiteralPath $ProviderTarget) {
    Remove-Item -LiteralPath $ProviderTarget -Recurse -Force
}
Copy-TreeClean -Source $ProviderSource -Destination $ProviderTarget

Write-Host '[4/6] Building and installing the local provider...'
Push-Location $ProviderTarget
try {
    & npm.cmd install
    if ($LASTEXITCODE -ne 0) {
        throw "npm.cmd install failed in provider package with exit code $LASTEXITCODE"
    }

    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) {
        throw "provider build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$PackagePath = Join-Path $Target 'package.json'
$pkg = Get-Content -Raw -LiteralPath $PackagePath | ConvertFrom-Json
if ($null -eq $pkg.dependencies) {
    $pkg | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{})
}
$pkg.dependencies | Add-Member -NotePropertyName '@local/provider-comfyui-local' -NotePropertyValue 'file:packages/provider-comfyui-local' -Force
$pkg | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $PackagePath -Encoding utf8

Push-Location $Target
try {
    & npm.cmd install
    if ($LASTEXITCODE -ne 0) {
        throw "npm.cmd install failed in ranking-football-local with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host '[5/6] Creating local-only Runtime Profile from the already-working TestVideo profile...'
$baseRuntime = Get-Content -Raw -LiteralPath $BaseRuntimePath | ConvertFrom-Json

if ($null -eq $baseRuntime.endpoints.'media.local') {
    throw 'Base Runtime is missing media.local.'
}
if ($null -eq $baseRuntime.endpoints.'hyperframes.local') {
    throw 'Base Runtime is missing hyperframes.local.'
}
if ($null -eq $baseRuntime.endpoints.'comfyui.local') {
    throw 'Base Runtime is missing comfyui.local.'
}

$runtime = [ordered]@{
    format = 'hypit.runtime-local@1'
    dataRoot = '.hypit/runtimes/local-ai'
    credentials = [ordered]@{}
    endpoints = [ordered]@{
        'media.local' = $baseRuntime.endpoints.'media.local'
        'hyperframes.local' = $baseRuntime.endpoints.'hyperframes.local'
        'comfyui.local' = $baseRuntime.endpoints.'comfyui.local'
    }
    bindings = [ordered]@{
        '@hypit/gpt-image@1#gpt-image-2' = 'comfyui.local'
        '@hypit/seedance@1#seedance-2-mini' = 'comfyui.local'
    }
}

$runtime | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $RuntimeOutput -Encoding utf8

Write-Host '[6/6] Validating the local sample and its generation plan...'
Push-Location $Target
try {
    & hypit.cmd check .\reference-local.svrun
    if ($LASTEXITCODE -ne 0) {
        throw "hypit check failed with exit code $LASTEXITCODE"
    }

    & hypit.cmd plan .\reference-local.svrun --runtime .\hypit.runtime.local-ai.json
    if ($LASTEXITCODE -ne 0) {
        throw "hypit plan failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host '[PASS] Local AI ranking-football sample is deployed.'
Write-Host "Workspace: $Target"
Write-Host ''
Write-Host 'Run it with:'
Write-Host '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\AI\run_hypit_ranking_local.ps1'
