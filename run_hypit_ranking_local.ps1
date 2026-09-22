param(
    [string]$HypitRoot = 'D:\AI\hypit',
    [string]$LocalProjectRoot = 'D:\AI\HypitProjects\TestVideo',
    [string]$Output = 'D:\AI\hypit\examples\ranking-football-local\output\final-local.mp4',
    [switch]$SkipStart
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot
$Workspace = Join-Path $HypitRoot 'examples\ranking-football-local'
$RunSource = Join-Path $Workspace 'reference-local.svrun'
$Runtime = Join-Path $Workspace 'hypit.runtime.local-ai.json'
$DeployScript = Join-Path $RepoRoot 'deploy_hypit_ranking_local.ps1'
$StartStack = Join-Path $RepoRoot 'start_ai_video.ps1'
$OutputDir = Split-Path -Parent $Output

function Test-Comfy {
    try {
        $stats = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/system_stats' -Method Get -TimeoutSec 5
        return $null -ne $stats
    } catch {
        return $false
    }
}

function Unload-OllamaModels {
    try {
        $running = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -Method Get -TimeoutSec 5
        foreach ($model in @($running.models)) {
            $name = [string]$model.name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $payload = @{
                model = $name
                prompt = ''
                stream = $false
                keep_alive = 0
            } | ConvertTo-Json -Compress

            $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/generate' -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 30
            Write-Host "  [OK] unloaded Ollama model: $name"
        }
    } catch {
        Write-Host '  [INFO] Ollama is not running or has no loaded models.'
    }
}

Write-Host '=== RUN HYPIT RANKING-FOOTBALL WITH LOCAL AI ==='

if (-not (Test-Path -LiteralPath $RunSource) -or -not (Test-Path -LiteralPath $Runtime)) {
    Write-Host '[SETUP] Local sample is not deployed yet. Deploying now...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $DeployScript
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed with exit code $LASTEXITCODE"
    }
}

if (-not $SkipStart -and -not (Test-Comfy)) {
    if (-not (Test-Path -LiteralPath $StartStack)) {
        throw "ComfyUI is offline and start script is missing: $StartStack"
    }

    Write-Host '[1/6] Starting/checking local media stack...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $StartStack
    if ($LASTEXITCODE -ne 0) {
        throw "start_ai_video.ps1 failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Host '[1/6] ComfyUI already ready or stack start was skipped.'
}

if (-not (Test-Comfy)) {
    throw 'ComfyUI is not ready at http://127.0.0.1:8188.'
}

Write-Host '[2/6] Freeing RTX 4060 VRAM before local generation...'
Unload-OllamaModels

$TestVideoRuntime = Join-Path $LocalProjectRoot 'hypit.runtime.json'
if (Test-Path -LiteralPath $TestVideoRuntime) {
    Push-Location $LocalProjectRoot
    try {
        & hypit.cmd programs down --endpoint whisperx.local
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'whisperx.local could not be stopped cleanly; continuing.'
        }
    } finally {
        Pop-Location
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $Workspace
try {
    Write-Host '[3/6] Checking local sample...'
    & hypit.cmd check .\reference-local.svrun
    if ($LASTEXITCODE -ne 0) {
        throw "hypit check failed with exit code $LASTEXITCODE"
    }

    Write-Host '[4/6] Planning against local ComfyUI endpoints...'
    & hypit.cmd plan .\reference-local.svrun --runtime .\hypit.runtime.local-ai.json
    if ($LASTEXITCODE -ne 0) {
        throw "hypit plan failed with exit code $LASTEXITCODE"
    }

    Write-Host '[5/6] Building complete Hypit sample locally...'
    Write-Host '      Expected heavy work: 3 Z-Image requests + 2 Wan 4-second video requests + HyperFrames render.'
    $buildText = (& hypit.cmd build .\reference-local.svrun --runtime .\hypit.runtime.local-ai.json --title ranking-football-local-ai --follow --max-wait-ms 2700000 --json | Out-String).Trim()

    if ($LASTEXITCODE -ne 0) {
        throw ('hypit build failed with exit code ' + $LASTEXITCODE + [Environment]::NewLine + $buildText)
    }

    $build = $buildText | ConvertFrom-Json
    $buildId = [string]$build.build.id
    $outcome = [string]$build.build.work.outcome

    if ([string]::IsNullOrWhiteSpace($buildId)) {
        throw ('Hypit build JSON did not contain build.id.' + [Environment]::NewLine + $buildText)
    }
    if ($outcome -ne 'complete') {
        throw "Hypit Build $buildId outcome is '$outcome'."
    }

    Write-Host "  [OK] Build complete: $buildId"

    Write-Host '[6/6] Exporting final.video...'
    & hypit.cmd get $buildId --output 'final.video' --to $Output
    if ($LASTEXITCODE -ne 0) {
        throw "hypit get final.video failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

if (Get-Command ffprobe.exe -ErrorAction SilentlyContinue) {
    Write-Host ''
    Write-Host '[VERIFY]'
    & ffprobe.exe -v error -show_entries format=duration -show_entries stream=index,codec_name,codec_type,width,height,r_frame_rate -of json $Output
}

Write-Host ''
Write-Host '[PASS] Hypit ranking-football local AI sample completed.'
Write-Host "Output: $Output"
