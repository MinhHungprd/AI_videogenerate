param(
    [string]$InputVideo = 'input\reference.mp4',
    [ValidateSet('vi','en')]
    [string]$Language = 'vi',
    [int]$MaxFrames = 8
)

$ErrorActionPreference = 'Stop'

$Project = Split-Path -Parent $PSScriptRoot
$InputPath = if ([IO.Path]::IsPathRooted($InputVideo)) { $InputVideo } else { Join-Path $Project $InputVideo }
$AnalysisDir = Join-Path $Project 'reference_analysis'
$FramesDir = Join-Path $AnalysisDir 'frames'
$TranscriptPath = Join-Path $AnalysisDir 'transcript.json'
$MetadataPath = Join-Path $AnalysisDir 'metadata.json'

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath;$env:Path"

foreach ($command in @('ffmpeg.exe','ffprobe.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command unavailable: $command"
    }
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Reference video not found: $InputPath"
}

New-Item -ItemType Directory -Force -Path $AnalysisDir, $FramesDir | Out-Null
Get-ChildItem -LiteralPath $FramesDir -Filter 'frame_*.jpg' -ErrorAction SilentlyContinue | Remove-Item -Force

$durationText = (& ffprobe.exe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $InputPath | Select-Object -First 1).Trim()
$duration = 0.0
if (-not [double]::TryParse($durationText, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$duration)) {
    throw "Could not determine reference duration: $durationText"
}
if ($duration -le 0) { throw 'Reference duration must be positive.' }

$fps = [Math]::Min(2.0, [Math]::Max(0.1, $MaxFrames / $duration))
$fpsText = $fps.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)

Write-Host "[INFO] Extracting up to $MaxFrames visual samples..."
& ffmpeg.exe -hide_banner -loglevel error -y -i $InputPath -vf "fps=$fpsText,scale=768:-2" -frames:v $MaxFrames (Join-Path $FramesDir 'frame_%02d.jpg')
if ($LASTEXITCODE -ne 0) { throw "Frame extraction failed with exit code $LASTEXITCODE" }

$audioProbe = (& ffprobe.exe -v error -select_streams a:0 -show_entries stream=index -of csv=p=0 $InputPath | Out-String).Trim()
$hasAudio = $audioProbe.Length -gt 0
$transcriptionStatus = 'no-audio'

if ($hasAudio) {
    try {
        $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8765/health' -Method Get -TimeoutSec 10
    } catch {
        throw 'WhisperX local service is not ready at 127.0.0.1:8765. Start the local AI stack first.'
    }

    if ($health.ok -ne $true) { throw 'WhisperX health check did not return ok=true.' }

    $tempWav = Join-Path ([IO.Path]::GetTempPath()) ("hypit-reference-" + [guid]::NewGuid().ToString('N') + '.wav')
    try {
        Write-Host '[INFO] Extracting canonical 16 kHz mono WAV...'
        & ffmpeg.exe -hide_banner -loglevel error -y -i $InputPath -vn -ac 1 -ar 16000 -c:a pcm_s16le $tempWav
        if ($LASTEXITCODE -ne 0) { throw "Audio extraction failed with exit code $LASTEXITCODE" }

        Write-Host "[INFO] Transcribing locally with WhisperX ($Language)..."
        $body = @{
            audio_path = $tempWav
            language = $Language
        } | ConvertTo-Json -Compress

        $request = @{
            Uri = 'http://127.0.0.1:8765/transcribe'
            Method = 'Post'
            ContentType = 'application/json'
            Body = $body
            TimeoutSec = 900
        }
        $transcript = Invoke-RestMethod @request

        $transcript | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $TranscriptPath -Encoding utf8
        $transcriptionStatus = 'ready'
    } finally {
        Remove-Item -LiteralPath $tempWav -Force -ErrorAction SilentlyContinue
    }
} else {
    @{ passages = @(); note = 'Reference contains no audio stream.' } |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $TranscriptPath -Encoding utf8
}

$frameCount = @(Get-ChildItem -LiteralPath $FramesDir -Filter 'frame_*.jpg').Count
$metadata = [ordered]@{
    source = $InputPath
    durationSeconds = [Math]::Round($duration, 3)
    sampledFrames = $frameCount
    language = $Language
    transcript = $transcriptionStatus
    createdAt = (Get-Date).ToString('o')
}
$metadata | ConvertTo-Json | Set-Content -LiteralPath $MetadataPath -Encoding utf8

Write-Host ''
Write-Host '[READY] Local reference package created:'
Write-Host "  Metadata:   $MetadataPath"
Write-Host "  Transcript: $TranscriptPath"
Write-Host "  Frames:     $FramesDir ($frameCount)"
Write-Host ''
Write-Host 'The local Qwen3-VL agent can now inspect transcript.json and frames/*.jpg.'
