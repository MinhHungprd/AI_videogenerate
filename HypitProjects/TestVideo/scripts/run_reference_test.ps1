param(
    [string]$Reference = 'input\reference.mp4',
    [string]$FinalOutput = 'output\reference_remake.mp4'
)

$ErrorActionPreference = 'Stop'

$Project = Split-Path -Parent $PSScriptRoot
$ReferencePath = if ([IO.Path]::IsPathRooted($Reference)) { $Reference } else { Join-Path $Project $Reference }
$FinalPath = if ([IO.Path]::IsPathRooted($FinalOutput)) { $FinalOutput } else { Join-Path $Project $FinalOutput }
$OutputDir = Split-Path -Parent $FinalPath
$GeneratedPath = Join-Path $OutputDir 'reference_test_generated.webm'
$RunSource = Join-Path $Project 'reference_test.svrun'
$AuthorSource = Join-Path $Project 'reference_test.svml'

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath;$env:Path"
$env:LOCAL_GENERATION_ONLY = 'true'

foreach ($command in @('hypit.cmd','ffmpeg.exe','ffprobe.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command unavailable: $command"
    }
}

if (-not (Test-Path -LiteralPath $ReferencePath)) {
    throw "Reference video not found: $ReferencePath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $Project
try {
    if (Get-Command ollama.exe -ErrorAction SilentlyContinue) {
        Write-Host '[INFO] Unloading local planner model to free VRAM...'
        & ollama.exe stop qwen3.5:4b 2>$null
    }

    Write-Host '[INFO] Stopping WhisperX helper for this GPU-heavy smoke test...'
    & hypit.cmd programs down --endpoint whisperx.local
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'whisperx.local did not stop cleanly; continuing because this Run does not require transcription.'
    }

    Write-Host '[1/5] Checking authored source...'
    & hypit.cmd check $AuthorSource
    if ($LASTEXITCODE -ne 0) {
        throw "hypit check failed with exit code $LASTEXITCODE"
    }

    Write-Host '[2/5] Planning local Run...'
    & hypit.cmd plan $RunSource
    if ($LASTEXITCODE -ne 0) {
        throw "hypit plan failed with exit code $LASTEXITCODE"
    }

    Write-Host '[3/5] Building Z-Image -> Wan locally. This can take several minutes...'
    $buildText = (& hypit.cmd build $RunSource --title reference-trampoline-smoke-test --follow --max-wait-ms 900000 --json | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw ("hypit build failed with exit code $LASTEXITCODE" + [Environment]::NewLine + $buildText)
    }

    $build = $buildText | ConvertFrom-Json
    $buildId = [string]$build.build.id
    $outcome = [string]$build.build.work.outcome

    if (-not $buildId) {
        throw ("Hypit build JSON did not contain build.id." + [Environment]::NewLine + $buildText)
    }
    if ($outcome -ne 'complete') {
        throw "Hypit Build $buildId outcome is '$outcome'."
    }

    Write-Host "[OK] Build complete: $buildId"

    Write-Host '[4/5] Retrieving generated Wan video...'
    & hypit.cmd get $buildId --output 'local-video.video' --to $GeneratedPath
    if ($LASTEXITCODE -ne 0) {
        throw "hypit get failed with exit code $LASTEXITCODE"
    }

    Write-Host '[5/5] Encoding 1080x1920 H.264 and reusing reference audio when present...'
    $filter = 'scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black'
    $ffmpegArgs = @(
        '-hide_banner','-loglevel','warning','-y',
        '-i',$GeneratedPath,
        '-i',$ReferencePath,
        '-map','0:v:0',
        '-map','1:a:0?',
        '-vf',$filter,
        '-c:v','libx264',
        '-preset','medium',
        '-crf','18',
        '-pix_fmt','yuv420p',
        '-c:a','aac',
        '-b:a','192k',
        '-shortest',
        '-movflags','+faststart',
        $FinalPath
    )
    & ffmpeg.exe @ffmpegArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Final FFmpeg encode failed with exit code $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '[VERIFY]'
    & ffprobe.exe -v error -show_entries format=duration -show_entries stream=index,codec_name,codec_type,width,height,r_frame_rate -of json $FinalPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffprobe verification failed with exit code $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host "[PASS] Reference smoke-test video: $FinalPath"
} finally {
    Pop-Location
}
