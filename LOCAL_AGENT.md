# Local agent mode

This project can run the orchestration model locally instead of consuming ChatGPT/Codex model credits.

## Local agent model

Default model:

    qwen3-vl:4b

Reason for this choice:

- local Ollama model
- vision input
- tool calling
- about 3.3 GB model size
- suitable starting point for RTX 4060 8 GB

The media models remain local:

    WhisperX -> local
    Z-Image -> ComfyUI local
    Wan 2.2 TI2V 5B -> ComfyUI local
    HyperFrames -> local
    FFmpeg -> local

## One-time setup

From D:\AI:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup_local_agent.ps1

This installs Ollama when missing and pulls qwen3-vl:4b.

## Prepare a reference video

Put the source at:

    D:\AI\HypitProjects\TestVideo\input\reference.mp4

Make sure the media stack is running, then:

    cd D:\AI\HypitProjects\TestVideo
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare_reference_local.ps1

The script creates:

    reference_analysis\metadata.json
    reference_analysis\transcript.json
    reference_analysis\frames\frame_*.jpg

The transcript is produced by the existing local WhisperX service.
Frames are extracted locally with FFmpeg.

## Start Codex with a local model

From D:\AI:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start_local_agent.ps1

The launcher uses:

    ollama launch codex --model qwen3-vl:4b

The Codex UI/tool shell is reused, but model inference is served by local Ollama.

## Prompt for video -> video remake

Inside the locally launched Codex session:

    /hypit

    LOCAL GENERATION ONLY.

    Reference:
    input/reference.mp4

    Before planning, inspect:
    - reference_analysis/metadata.json
    - reference_analysis/transcript.json
    - all useful images under reference_analysis/frames/

    Recreate the reference's:
    - hook
    - shot timing
    - pacing
    - composition
    - camera movement
    - subject movement
    - visual style
    - caption timing where applicable

    Use only:
    - local WhisperX
    - local ComfyUI
    - local Z-Image
    - local Wan 2.2 TI2V 5B
    - local HyperFrames
    - local FFmpeg

    Never use HypiHub or another hosted provider.
    Never request an API key.
    If local generation fails, fail clearly instead of falling back to cloud.

    IMPORTANT RTX 4060 8GB VRAM rule:
    Immediately before a GPU-heavy ComfyUI image/video generation command,
    run:
        ollama stop qwen3-vl:4b
    to free local-agent VRAM.
    Ollama may reload the model automatically for the next agent turn.

    Final output:
    output/reference_remake.mp4
    H.264
    1080x1920
    9:16

    Verify the finished file with ffprobe.

## Stop

Exit Codex first, then:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\AI\stop_local_agent.ps1

The script unloads qwen3-vl:4b, stops the media stack, and only terminates an Ollama server process if this workspace started that server itself.
