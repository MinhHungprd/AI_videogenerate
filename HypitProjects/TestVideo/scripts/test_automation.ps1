$ErrorActionPreference = 'Stop'

$startPath = 'D:\AI\start_ai_video.ps1'
$stopPath = 'D:\AI\stop_ai_video.ps1'

foreach ($path in @($startPath, $stopPath)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Missing automation script: $path" }
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -ne 0) { throw "PowerShell parse errors in ${path}: $($errors.Message -join '; ')" }
}

$start = Get-Content -Raw -LiteralPath $startPath
$stop = Get-Content -Raw -LiteralPath $stopPath

if ($start -notmatch '127\.0\.0\.1' -or $start -notmatch '8188') { throw 'Start script must bind ComfyUI to loopback:8188' }
if ($start -notmatch 'LOCAL_GENERATION_ONLY') { throw 'Start script must enforce LOCAL_GENERATION_ONLY' }
if ($start -notmatch 'nvidia-smi') { throw 'Start script must check the GPU' }
if ($start -notmatch 'runtime up' -or $start -notmatch 'doctor') { throw 'Start script must start and verify Hypit' }
if ($start -match 'Set-ExecutionPolicy') { throw 'Start script must not alter PowerShell execution policy' }

if ($stop -notmatch 'runtime down' -or $stop -notmatch 'programs down') { throw 'Stop script must stop Hypit runtime and managed programs' }
if ($stop -match 'taskkill\s+.*(/IM|python|node)' -or $stop -match 'Stop-Process\s+.*-Name') {
  throw 'Stop script must not kill global Python or Node processes'
}

'AUTOMATION_TESTS=PASS'
