$ErrorActionPreference = 'Stop'

# Local AI Video stack launcher.
# Changes to PATH/environment are process-local only.
$Root = $PSScriptRoot
$Project = Join-Path $Root 'HypitProjects\TestVideo'
$ComfyRoot = Join-Path $Root 'ComfyUI'
$RuntimeDir = Join-Path $Root '.runtime'
$PidFile = Join-Path $RuntimeDir 'comfyui.pid'
$LogDir = Join-Path $Root 'setup_logs'
$ComfyStdout = Join-Path $LogDir 'comfyui.stdout.log'
$ComfyStderr = Join-Path $LogDir 'comfyui.stderr.log'
$ComfyHealthUrl = 'http://127.0.0.1:8188/system_stats'

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath;$env:Path"
$env:LOCAL_GENERATION_ONLY = 'true'

New-Item -ItemType Directory -Force -Path $RuntimeDir, $LogDir | Out-Null

function Test-ComfyHealth {
    try {
        $null = Invoke-RestMethod -Uri $ComfyHealthUrl -Method Get -TimeoutSec 4 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Wait-ComfyHealth([int]$TimeoutSeconds = 300) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-ComfyHealth) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command is unavailable: $Name"
    }
}

Write-Host '=== Local AI Video: START ==='

Assert-Command 'nvidia-smi.exe'
Assert-Command 'hypit.cmd'

& nvidia-smi.exe --query-gpu=name,memory.total,driver_version --format=csv,noheader
if ($LASTEXITCODE -ne 0) {
    throw "nvidia-smi failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $Project)) {
    throw "Hypit project not found: $Project"
}
if (-not (Test-Path -LiteralPath $ComfyRoot)) {
    throw "ComfyUI checkout not found: $ComfyRoot"
}

if (Test-ComfyHealth) {
    Write-Host '[OK] ComfyUI is already healthy on 127.0.0.1:8188.'
} else {
    if (Test-Path -LiteralPath $PidFile) {
        $existingPidText = (Get-Content -Raw -LiteralPath $PidFile).Trim()
        $existingPid = 0
        if ([int]::TryParse($existingPidText, [ref]$existingPid)) {
            $existingProcess = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($null -ne $existingProcess) {
                Write-Host "[INFO] Previously owned ComfyUI PID $existingPid is still running; waiting for health."
                if (-not (Wait-ComfyHealth 90)) {
                    throw "Owned ComfyUI process PID $existingPid is running but 127.0.0.1:8188 is not healthy. Check $ComfyStderr"
                }
            } else {
                Remove-Item -LiteralPath $PidFile -Force
            }
        } else {
            Remove-Item -LiteralPath $PidFile -Force
        }
    }

    if (-not (Test-ComfyHealth)) {
        $pythonCandidates = @(
            (Join-Path $ComfyRoot '.venv\Scripts\python.exe'),
            (Join-Path $ComfyRoot 'venv\Scripts\python.exe'),
            (Join-Path $ComfyRoot 'python_embeded\python.exe'),
            (Join-Path $ComfyRoot 'python_embedded\python.exe')
        )
        $comfyPython = $pythonCandidates |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1

        if (-not $comfyPython) {
            throw "ComfyUI Python environment was not found. Checked: $($pythonCandidates -join ', ')"
        }

        Write-Host "[INFO] Starting ComfyUI with $comfyPython"
        $startParams = @{
            FilePath = $comfyPython
            ArgumentList = @('main.py', '--listen', '127.0.0.1', '--port', '8188', '--lowvram')
            WorkingDirectory = $ComfyRoot
            RedirectStandardOutput = $ComfyStdout
            RedirectStandardError = $ComfyStderr
            WindowStyle = 'Hidden'
            PassThru = $true
        }
        $comfyProcess = Start-Process @startParams

        Set-Content -LiteralPath $PidFile -Value $comfyProcess.Id -Encoding ascii

        if (-not (Wait-ComfyHealth 300)) {
            throw "ComfyUI did not become healthy within 300 seconds. PID=$($comfyProcess.Id). Check $ComfyStdout and $ComfyStderr"
        }
        Write-Host "[OK] ComfyUI healthy. Owned PID=$($comfyProcess.Id)"
    }
}

Push-Location $Project
try {
    Write-Host '[INFO] Starting Hypit managed local programs...'
    & hypit.cmd programs up
    if ($LASTEXITCODE -ne 0) {
        throw "hypit programs up failed with exit code $LASTEXITCODE"
    }

    Write-Host '[INFO] Starting Hypit runtime...'
    & hypit.cmd runtime up
    if ($LASTEXITCODE -ne 0) {
        throw "hypit runtime up failed with exit code $LASTEXITCODE"
    }

    Write-Host '[INFO] Running Hypit doctor...'
    & hypit.cmd doctor
    if ($LASTEXITCODE -ne 0) {
        throw "hypit doctor failed with exit code $LASTEXITCODE"
    }

    & hypit.cmd runtime status
    if ($LASTEXITCODE -ne 0) {
        throw "hypit runtime status failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host '[READY] Local AI Video stack is running.'
Write-Host 'ComfyUI: http://127.0.0.1:8188'
Write-Host "Project: $Project"
Write-Host 'Cloud generation fallback: disabled'
