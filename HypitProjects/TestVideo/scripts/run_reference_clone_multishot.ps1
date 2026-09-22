param(
    [string]$Reference = 'input\reference.mp4',
    [string]$Plan = 'plans\reference_clone_multishot_plan.json',
    [string]$FinalOutput = 'output\reference_remake.mp4'
)

$ErrorActionPreference = 'Stop'

$Project = Split-Path -Parent $PSScriptRoot
$ReferencePath = if ([IO.Path]::IsPathRooted($Reference)) { $Reference } else { Join-Path $Project $Reference }
$PlanPath = if ([IO.Path]::IsPathRooted($Plan)) { $Plan } else { Join-Path $Project $Plan }
$FinalPath = if ([IO.Path]::IsPathRooted($FinalOutput)) { $FinalOutput } else { Join-Path $Project $FinalOutput }

$GeneratedDir = Join-Path $Project '.generated\reference_clone'
$FrameDir = Join-Path $Project 'reference_analysis\shots'
$ShotOutputDir = Join-Path $Project 'output\reference_clone_shots'
$AuthorSource = Join-Path $GeneratedDir 'reference_clone.svml'
$RunSource = Join-Path $GeneratedDir 'reference_clone.svrun'

$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath;$env:Path"
$env:LOCAL_GENERATION_ONLY = 'true'

function Invariant([double]$Value) {
    return $Value.ToString('0.######', [Globalization.CultureInfo]::InvariantCulture)
}

function XmlEscape([string]$Value) {
    return [System.Security.SecurityElement]::Escape($Value)
}

foreach ($command in @('hypit.cmd', 'ffmpeg.exe', 'ffprobe.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command unavailable: $command"
    }
}

if (-not (Test-Path -LiteralPath $ReferencePath)) {
    throw "Reference video not found: $ReferencePath"
}
if (-not (Test-Path -LiteralPath $PlanPath)) {
    throw "Clone plan not found: $PlanPath"
}

$clonePlan = Get-Content -Raw -LiteralPath $PlanPath | ConvertFrom-Json
$shots = @($clonePlan.shots)
if ($shots.Count -lt 2) {
    throw 'Multishot clone plan must contain at least two shots.'
}

$durationRaw = (& ffprobe.exe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $ReferencePath | Select-Object -First 1).Trim()
$referenceDuration = 0.0
if (-not [double]::TryParse(
    $durationRaw,
    [Globalization.NumberStyles]::Float,
    [Globalization.CultureInfo]::InvariantCulture,
    [ref]$referenceDuration
)) {
    throw "Could not read reference duration: $durationRaw"
}
if ($referenceDuration -le 0) {
    throw 'Reference duration must be positive.'
}

$plannedDuration = 0.0
foreach ($shot in $shots) {
    $generationDuration = [int]$shot.generationDurationSeconds
    if ($generationDuration -ne 4) {
        throw "Current local Hypit/Wan contract requires generationDurationSeconds=4 for every shot. Shot '$($shot.id)' requested $generationDuration."
    }

    $finalDuration = [double]$shot.finalDurationSeconds
    if ($finalDuration -le 0 -or $finalDuration -gt $generationDuration) {
        throw "Invalid finalDurationSeconds for shot '$($shot.id)'."
    }

    $frameAt = [double]$shot.firstFrameAtSeconds
    if ($frameAt -lt 0 -or $frameAt -ge $referenceDuration) {
        throw "Invalid firstFrameAtSeconds for shot '$($shot.id)'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$shot.motionPrompt)) {
        throw "Shot '$($shot.id)' has an empty motionPrompt."
    }

    $plannedDuration += $finalDuration
}

if ([Math]::Abs($plannedDuration - $referenceDuration) -gt 0.15) {
    throw "Planned final duration $(Invariant $plannedDuration)s does not match reference duration $(Invariant $referenceDuration)s."
}

New-Item -ItemType Directory -Force -Path $GeneratedDir, $FrameDir, $ShotOutputDir, (Split-Path -Parent $FinalPath) | Out-Null

Write-Host '=== REFERENCE-FIRST MULTISHOT CLONE ==='
Write-Host "Reference: $ReferencePath"
Write-Host "Plan:      $PlanPath"
Write-Host "Duration:  $(Invariant $referenceDuration)s"
Write-Host "Shots:     $($shots.Count)"
Write-Host ''

Write-Host '[1/7] Extracting real first frames from reference...'
for ($i = 0; $i -lt $shots.Count; $i++) {
    $shot = $shots[$i]
    $indexText = '{0:D2}' -f ($i + 1)
    $fileName = [string]$shot.firstFrameFile
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = "shot_$($indexText)_first.jpg"
    }
    $framePath = Join-Path $FrameDir $fileName
    $frameTime = Invariant ([double]$shot.firstFrameAtSeconds)

    & ffmpeg.exe -hide_banner -loglevel error -y -ss $frameTime -i $ReferencePath -frames:v 1 -q:v 2 $framePath
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract first frame for shot '$($shot.id)' at $($frameTime)s."
    }

    $shot | Add-Member -NotePropertyName resolvedFirstFrameFile -NotePropertyValue $fileName -Force
    Write-Host "  [OK] shot $($i + 1): $($frameTime)s -> $framePath"
}

Write-Host '[2/7] Authoring Hypit source from plan...'
$svml = New-Object System.Collections.Generic.List[string]
$svml.Add('<?svml using="@hypit/markup@1"?>')
$svml.Add('')
$svml.Add('<svml>')
$svml.Add('  <import as="text" from="@hypit/text@1"/>')
$svml.Add('  <import as="asset" from="@hypit/media@1"/>')
$svml.Add('  <import as="seedance" from="@hypit/seedance@1"/>')
$svml.Add('')

$svrun = New-Object System.Collections.Generic.List[string]
$svrun.Add('<?svml using="@hypit/run-markup@1"?>')
$svrun.Add('')
$svrun.Add('<svrun version="1">')
$svrun.Add('  <author source="./reference_clone.svml"/>')

for ($i = 0; $i -lt $shots.Count; $i++) {
    $shot = $shots[$i]
    $indexText = '{0:D2}' -f ($i + 1)
    $frameId = "shot-$indexText-frame"
    $promptId = "shot-$indexText-prompt"
    $videoId = "shot-$indexText-video"
    $frameSrc = "../../reference_analysis/shots/$($shot.resolvedFirstFrameFile)"
    $prompt = XmlEscape ([string]$shot.motionPrompt)
    $personReference = if ([bool]$shot.personReference) { 'true' } else { 'false' }

    $svml.Add(('  <asset:Image id="{0}" src="{1}"/>' -f $frameId, $frameSrc))
    $svml.Add(('  <text:Value id="{0}">{1}</text:Value>' -f $promptId, $prompt))
    $svml.Add('  <seedance:FrameVideo')
    $svml.Add(('    id="{0}"' -f $videoId))
    $svml.Add('    model="mini"')
    $svml.Add(('    prompt={{{0}}}' -f $promptId))
    $svml.Add(('    duration="{0}"' -f [int]$shot.generationDurationSeconds))
    $svml.Add('    resolution="480p"')
    $svml.Add('    aspect-ratio="9:16"')
    $svml.Add('    generate-audio="false"')
    $svml.Add(('    first-frame={{{0}}}' -f $frameId))
    $svml.Add(('    first-frame-person-reference="{0}"' -f $personReference))
    $svml.Add('  />')
    $svml.Add('')

    $svrun.Add(('  <target output="{0}.video"/>' -f $videoId))
}

$svml.Add('</svml>')
$svrun.Add('</svrun>')

$svml -join [Environment]::NewLine | Set-Content -LiteralPath $AuthorSource -Encoding utf8
$svrun -join [Environment]::NewLine | Set-Content -LiteralPath $RunSource -Encoding utf8

Write-Host "  [OK] $AuthorSource"
Write-Host "  [OK] $RunSource"

Write-Host '[3/7] Releasing GPU memory used by local planners/transcription...'
try {
    $running = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -Method Get -TimeoutSec 5
    foreach ($model in @($running.models)) {
        $name = [string]$model.name
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $payload = @{
                model = $name
                prompt = ''
                stream = $false
                keep_alive = 0
            } | ConvertTo-Json -Compress
            $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/generate' -Method Post -ContentType 'application/json' -Body $payload -TimeoutSec 30
            Write-Host "  [OK] unloaded Ollama model: $name"
        }
    }
} catch {
    Write-Host '  [INFO] Ollama is not running or no model needed unloading.'
}

Push-Location $Project
try {
    & hypit.cmd programs down --endpoint whisperx.local
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'Could not stop whisperx.local cleanly; continuing.'
    }

    try {
        $null = Invoke-RestMethod -Uri 'http://127.0.0.1:8188/system_stats' -Method Get -TimeoutSec 5
    } catch {
        throw 'ComfyUI is not ready on http://127.0.0.1:8188. Run D:\AI\start_ai_video.ps1 first.'
    }

    Write-Host '[4/7] Validating and planning Hypit multishot Run...'
    & hypit.cmd check $AuthorSource
    if ($LASTEXITCODE -ne 0) {
        throw "hypit check failed with exit code $LASTEXITCODE"
    }

    & hypit.cmd plan $RunSource
    if ($LASTEXITCODE -ne 0) {
        throw "hypit plan failed with exit code $LASTEXITCODE"
    }

    Write-Host '[5/7] Generating Wan clips from REAL reference frames...'
    Write-Host '      This executes one 4-second local Wan generation per planned shot.'
    $buildText = (& hypit.cmd build $RunSource --title reference-first-multishot-clone --follow --max-wait-ms 1800000 --json | Out-String).Trim()
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

    Write-Host '[6/7] Retrieving generated shot artifacts...'
    $shotPaths = @()
    for ($i = 0; $i -lt $shots.Count; $i++) {
        $indexText = '{0:D2}' -f ($i + 1)
        $outputId = "shot-$indexText-video.video"
        $shotPath = Join-Path $ShotOutputDir "shot_$indexText.webm"

        & hypit.cmd get $buildId --output $outputId --to $shotPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to retrieve Hypit output '$outputId'."
        }

        $shotPaths += $shotPath
        Write-Host "  [OK] $outputId -> $shotPath"
    }

    Write-Host '[7/7] Trimming shots to reference timing, concatenating, restoring original audio and encoding H.264...'
    $filterParts = @()
    $concatInputs = ''
    for ($i = 0; $i -lt $shots.Count; $i++) {
        $trimDuration = Invariant ([double]$shots[$i].finalDurationSeconds)
        $filterParts += "[$($i):v]trim=duration=$trimDuration,setpts=PTS-STARTPTS[v$i]"
        $concatInputs += "[v$i]"
    }

    $filterParts += "$($concatInputs)concat=n=$($shots.Count):v=1:a=0,scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black[vout]"
    $filterComplex = $filterParts -join ';'

    $ffmpegArgs = @('-hide_banner', '-loglevel', 'warning', '-y')
    foreach ($shotPath in $shotPaths) {
        $ffmpegArgs += @('-i', $shotPath)
    }
    $ffmpegArgs += @('-i', $ReferencePath)

    $audioInputIndex = $shots.Count
    $ffmpegArgs += @(
        '-filter_complex', $filterComplex,
        '-map', '[vout]',
        '-map', "$($audioInputIndex):a:0?",
        '-c:v', 'libx264',
        '-preset', 'medium',
        '-crf', '18',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-b:a', '192k',
        '-t', (Invariant $referenceDuration),
        '-movflags', '+faststart',
        $FinalPath
    )

    & ffmpeg.exe @ffmpegArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Final FFmpeg encode failed with exit code $LASTEXITCODE"
    }

    $probeText = (& ffprobe.exe -v error -show_entries format=duration -show_entries stream=index,codec_name,codec_type,width,height,r_frame_rate -of json $FinalPath | Out-String)
    $probe = $probeText | ConvertFrom-Json
    $video = @($probe.streams | Where-Object { $_.codec_type -eq 'video' })[0]
    $finalDuration = [double]::Parse(
        [string]$probe.format.duration,
        [Globalization.CultureInfo]::InvariantCulture
    )

    if ([int]$video.width -ne 1080 -or [int]$video.height -ne 1920) {
        throw "Unexpected final resolution: $($video.width)x$($video.height)"
    }
    if ([Math]::Abs($finalDuration - $referenceDuration) -gt 0.15) {
        throw "Unexpected final duration: $(Invariant $finalDuration)s; reference is $(Invariant $referenceDuration)s."
    }

    Write-Host ''
    Write-Host '[PASS] Reference-first multishot clone completed.'
    Write-Host "Final:    $FinalPath"
    Write-Host "Duration: $(Invariant $finalDuration)s"
    Write-Host "Video:    $($video.codec_name) $($video.width)x$($video.height) $($video.r_frame_rate)"
    Write-Host "Build:    $buildId"
} finally {
    Pop-Location
}
