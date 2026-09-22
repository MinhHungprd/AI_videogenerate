$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$RuntimeDir = Join-Path $Root '.runtime'
$PidFile = Join-Path $RuntimeDir 'ollama.pid'
$Model = 'qwen3-vl:4b'
$Health = 'http://127.0.0.1:11434/api/tags'

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

    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
        "$env:LOCALAPPDATA\Ollama\ollama.exe"
    )
    foreach ($candidate in $candidates) {
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

Write-Host '=== LOCAL AGENT SETUP ==='

$ollama = Find-Ollama
if (-not $ollama) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'Ollama is not installed and winget is unavailable.'
    }

    Write-Host '[INFO] Installing Ollama with winget...'
    & winget.exe install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Ollama installation failed with exit code $LASTEXITCODE"
    }

    $ollama = Find-Ollama
    if (-not $ollama) {
        throw 'Ollama was installed but ollama.exe cannot be located. Open a new PowerShell and run this script again.'
    }
}

Write-Host "[OK] Ollama: $ollama"
& $ollama --version

if (-not (Test-OllamaApi)) {
    Write-Host '[INFO] Starting local Ollama API...'
    $process = Start-Process -FilePath $ollama -ArgumentList @('serve') -WindowStyle Hidden -PassThru
    Set-Content -LiteralPath $PidFile -Value $process.Id -Encoding ascii

    if (-not (Wait-Ollama 60)) {
        throw 'Ollama API did not become ready at 127.0.0.1:11434.'
    }
}

Write-Host "[INFO] Pulling local agent model: $Model"
& $ollama pull $Model
if ($LASTEXITCODE -ne 0) {
    throw "ollama pull $Model failed with exit code $LASTEXITCODE"
}

Write-Host ''
Write-Host '[OK] Local agent model is installed.'
Write-Host "Model: $Model"
Write-Host 'API:   http://127.0.0.1:11434'
Write-Host ''
Write-Host 'Next:'
Write-Host '  powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\AI\start_local_agent.ps1'
