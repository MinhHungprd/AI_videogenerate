$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$RuntimeDir = Join-Path $Root '.runtime'
$PidFile = Join-Path $RuntimeDir 'ollama.pid'
$Model = 'qwen3.5:4b'

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath;$env:Path"

$ollamaCmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
if ($ollamaCmd) {
    & $ollamaCmd.Source stop $Model 2>$null
}

& (Join-Path $Root 'stop_ai_video.ps1')

if (Test-Path -LiteralPath $PidFile) {
    $text = (Get-Content -Raw -LiteralPath $PidFile).Trim()
    $ownedPid = 0
    if ([int]::TryParse($text, [ref]$ownedPid)) {
        $process = Get-Process -Id $ownedPid -ErrorAction SilentlyContinue
        if ($process) {
            $info = Get-CimInstance Win32_Process -Filter "ProcessId=$ownedPid" -ErrorAction SilentlyContinue
            $commandLine = if ($info) { [string]$info.CommandLine } else { '' }
            if ($commandLine -match 'ollama(.exe)?\s+serve') {
                Stop-Process -Id $ownedPid -Force
            } else {
                Write-Warning "PID $ownedPid is not verified as an owned Ollama serve process; leaving it running."
            }
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

Write-Host '[DONE] Local agent/media stop sequence completed.'
