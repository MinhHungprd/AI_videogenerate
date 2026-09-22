# AI Video Generate - Local Hypit + ComfyUI

Pipeline tao video AI local-only tren Windows, da trien khai va test tren RTX 4060 8 GB.

## Stack hien tai

- Hypit: 0.2.12
- Hypit source commit: 9c9918d0cedf2f06574ab0d517b1b6b0afb56a66
- ComfyUI: 0.37.0
- ComfyUI working commit trong qua trinh setup: e638023d54497dbe0579565e5de4bb7076899592
- WhisperX: small, CUDA, FP16, Vietnamese + English alignment
- Image: Z-Image Turbo INT8 + Qwen 3 4B FP8
- Video: Wan 2.2 TI2V 5B + UMT5 XXL FP8
- Final composition: Hypit HyperFrames + FFmpeg
- Generation endpoint: http://127.0.0.1:8188
- Hosted/cloud generation fallback: disabled

Repo co y khong commit Hypit/ComfyUI upstream checkout, Python environment, model weights, cache va generated media.

## Model files tren may da setup

ComfyUI can co cac file:

    models/diffusion_models/z_image_turbo_int8_convrot.safetensors
    models/text_encoders/qwen_3_4b_fp8_mixed.safetensors
    models/vae/ae.safetensors

    models/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors
    models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
    models/vae/wan2.2_vae.safetensors

Workflow:

    D:\AI\workflows\image.json
    D:\AI\workflows\video_i2v.json

## Chay tren may hien tai

Mo PowerShell:

    cd D:\AI
    git pull --ff-only
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start_ai_video.ps1

ExecutionPolicy Bypass trong lenh tren chi ap dung cho process PowerShell cua lenh nay. Script khong thay doi execution policy cua Windows.

Khi thanh cong, cuoi output se co:

    [READY] Local AI Video stack is running.
    ComfyUI: http://127.0.0.1:8188
    Cloud generation fallback: disabled

## Kiem tra

ComfyUI:

    curl.exe http://127.0.0.1:8188/system_stats

Hypit:

    cd D:\AI\HypitProjects\TestVideo
    hypit.cmd runtime status
    hypit.cmd programs status --verbose
    hypit.cmd doctor

Automation scripts:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\AI\HypitProjects\TestVideo\scripts\test_automation.ps1

Expected:

    AUTOMATION_TESTS=PASS

## Tat stack

    cd D:\AI
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\stop_ai_video.ps1

Stop script chi dung ComfyUI PID ma workspace nay da start. No khong kill tat ca Python/Node process.

## Rebuild provider Hypit <-> ComfyUI

Source cua provider duoc commit, nhung dist va node_modules bi ignore. Sau fresh clone, hoac sau khi sua provider:

    cd D:\AI\HypitProjects\TestVideo\packages\provider-comfyui-local
    npm.cmd install
    npm.cmd run build

    cd D:\AI\HypitProjects\TestVideo
    npm.cmd install

Sau do restart stack.

## Dung voi Codex / Hypit

Dat video tham chieu vao:

    D:\AI\HypitProjects\TestVideo\input\reference.mp4

Video input bi ignore boi Git.

Sau do:

    cd D:\AI\HypitProjects\TestVideo
    codex

Prompt mau:

    /hypit

    Use input/reference.mp4 as reference.

    Analyze its hook, pacing, scene structure, captions, transitions,
    camera movement and B-roll timing.

    Create a new video using LOCAL GENERATION ONLY.

    Use:
    - local WhisperX
    - local ComfyUI image generation
    - local Wan image-to-video
    - local HyperFrames
    - local FFmpeg

    Do not use any hosted provider.

    Output:
    1080x1920
    9:16
    MP4

## Pipeline da verify

    local_generation.svml
        image request
          -> @local/provider-comfyui-local -> Z-Image
        video request
          -> @local/provider-comfyui-local -> Wan 2.2 I2V

    hyperframes_overlay.svml
        -> local HyperFrames graphics/render

Provider local implements Hypit generation capability contracts va route request den localhost ComfyUI. Ten gpt-image-2 va seedance-2-mini trong binding la capability contracts; generation thuc te do local ComfyUI provider thuc hien, khong goi cloud service tuong ung.

## Gioi han hien tai

1. Wan provider hien gio chi support 9:16, 480p, 3-4 giay, khong generate audio.
2. Image workflow hien support 1K o cac aspect ratio da khai bao.
3. Final 1080x1920 duoc compose/upscale sau local generation; Wan khong generate native 1080x1920.
4. hypit.runtime.json dang co duong dan FFmpeg va D:/AI/workflows theo may hien tai.
5. scripts/start_whisperx_cuda.cmd dang co duong dan Hypit Program theo user C:\Users\Khach.
6. Neu chuyen sang Windows user/drive khac, can cap nhat cac path machine-specific.
7. Model weights va generated video khong duoc commit len Git.

## Cau truc

    D:\AI
    +-- start_ai_video.ps1
    +-- stop_ai_video.ps1
    +-- workflows/
    |   +-- image.json
    |   +-- video_i2v.json
    +-- HypitProjects/
    |   +-- TestVideo/
    |       +-- hypit.runtime.json
    |       +-- local_generation.svml
    |       +-- hyperframes_overlay.svml
    |       +-- packages/provider-comfyui-local/
    |       +-- scripts/
    +-- hypit/       # upstream checkout, ignored
    +-- ComfyUI/     # upstream checkout, ignored

## Safety

- ComfyUI bind chi 127.0.0.1:8188.
- Local provider reject ComfyUI URL khong phai loopback.
- Launcher set LOCAL_GENERATION_ONLY=true.
- Runtime profile hien tai khong cau hinh cloud generation fallback.


## Local agent (khong dung Codex credit)

Repo co them local orchestration mode qua Ollama.

Model mac dinh:

    qwen3.5:4b

Model nay co vision + tool calling va phu hop hon voi RTX 4060 8 GB.

One-time setup:

    cd D:\AI
    git pull --ff-only
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup_local_agent.ps1

Prepare reference:

    cd D:\AI\HypitProjects\TestVideo
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare_reference_local.ps1

Start local Codex:

    cd D:\AI
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start_local_agent.ps1

This launches Codex through local Ollama:

    ollama launch codex --model qwen3.5:4b

Full local-agent instructions are in LOCAL_AGENT.md.

Stop local mode after exiting Codex:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\AI\stop_local_agent.ps1
