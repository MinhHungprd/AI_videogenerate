$ErrorActionPreference = 'Stop'

# Stops only the local AI Video stack owned by this workspace.
$Root = $PSScriptRoot
$Project = Join-Path $Root 'HypitProjects\TestVideo'
$ComfyRoot = Join-Path $Root 'ComfyUI'
$RuntimeDir = Join-Path $Root '.runtime'
$PidFile = Join-Path $RuntimeDir 'comfyui.pid'

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath;$env:Path"
$env:LOCAL_GENERATION_ONLY = 'true'

Write-Host '=== Local AI Video: STOP ==='

if ((Test-Path -LiteralPath $Project) -and (Get-Command hypit.cmd -ErrorAction SilentlyContinue)) {
    Push-Location $Project
    try {
        Write-Host '[INFO] Stopping Hypit runtime...'
        & hypit.cmd runtime down
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "hypit runtime down exited with code $LASTEXITCODE"
        }

        Write-Host '[INFO] Stopping Hypit managed programs...'
        & hypit.cmd programs down
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "hypit programs down exited with code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Warning 'Hypit project or CLI is unavailable; skipping Hypit shutdown.'
}

if (Test-Path -LiteralPath $PidFile) {
    $pidText = (Get-Content -Raw -LiteralPath $PidFile).Trim()
    $ownedPid = 0

    if (-not [int]::TryParse($pidText, [ref]$ownedPid)) {
        Write-Warning "Invalid ComfyUI PID file: $PidFile"
        Remove-Item -LiteralPath $PidFile -Force
    } else {
        $process = Get-Process -Id $ownedPid -ErrorAction SilentlyContinue

        if ($null -eq $process) {
            Write-Host "[INFO] Owned ComfyUI PID $ownedPid is no longer running."
            Remove-Item -LiteralPath $PidFile -Force
        } else {
            $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$ownedPid" -ErrorAction SilentlyContinue
            $executable = if ($processInfo) { [string]$processInfo.ExecutablePath } else { '' }
            $commandLine = if ($processInfo) { [string]$processInfo.CommandLine } else { '' }

            $rootPattern = [regex]::Escape($ComfyRoot)
            $isOwnedComfy = ($executable -match $rootPattern) -or ($commandLine -match $rootPattern)

            if (-not $isOwnedComfy) {
                throw "Refusing to stop PID $ownedPid because it cannot be verified as this workspace's ComfyUI process."
            }

            Write-Host "[INFO] Stopping owned ComfyUI PID $ownedPid..."
            Stop-Process -Id $ownedPid -Force
            Remove-Item -LiteralPath $PidFile -Force
        }
    }
} else {
    Write-Host '[INFO] No owned ComfyUI PID file. Any independently started ComfyUI instance is left untouched.'
}

Write-Host '[DONE] Local AI Video stack stop sequence completed.'
