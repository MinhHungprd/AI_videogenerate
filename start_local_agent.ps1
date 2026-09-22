$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$Project = Join-Path $Root 'HypitProjects\TestVideo'
$RuntimeDir = Join-Path $Root '.runtime'
$PidFile = Join-Path $RuntimeDir 'ollama.pid'
$Model = 'qwen3-vl:4b'
$Health = 'http://127.0.0.1:11434/api/tags'

$env:LOCAL_GENERATION_ONLY = 'true'
$env:OLLAMA_HOST = '127.0.0.1:11434'

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath;$env:Path"
}

function Find-Ollama {
    Refresh-Path
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:LOCALAPPDATA\Ollama\ollama.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

function Test-OllamaApi {
    try {
        $null = Invoke-RestMethod -Uri $Health -Method Get -TimeoutSec 3 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Wait-Ollama([int]$TimeoutSeconds = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-OllamaApi) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

$ollama = Find-Ollama
if (-not $ollama) {
    throw 'Ollama is not installed. Run D:\AI\setup_local_agent.ps1 first.'
}

Write-Host '=== LOCAL AI VIDEO AGENT ==='
Write-Host '[1/3] Starting/checking local media stack...'
& (Join-Path $Root 'start_ai_video.ps1')

Write-Host '[2/3] Checking Ollama...'
if (-not (Test-OllamaApi)) {
    $process = Start-Process -FilePath $ollama -ArgumentList @('serve') -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ascii
    if (-not (Wait-Ollama 60)) {
        throw 'Ollama did not become ready at 127.0.0.1:11434.'
    }
}

$models = (& $ollama list | Out-String)
if ($models -notmatch [regex]::Escape($Model)) {
    throw "Local model $Model is missing. Run setup_local_agent.ps1 first."
}

Write-Host '[3/3] Launching Codex with LOCAL Ollama model...'
Write-Host "Model: $Model"
Write-Host 'Model inference is served by local Ollama, not the ChatGPT/Codex usage pool.'
Write-Host ''
Write-Host 'Tip: prepare the reference first with:'
Write-Host '  .\scripts\prepare_reference_local.ps1'
Write-Host ''

Push-Location $Project
try {
    & $ollama launch codex --model $Model
} finally {
    Pop-Location
}
