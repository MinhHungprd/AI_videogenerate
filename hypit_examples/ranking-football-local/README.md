# Hypit ranking-football local AI

This is a **local-only adaptation** of Hypit's official:

    D:\AI\hypit\examples\ranking-football

The official sample is left untouched. The deploy script creates a sibling workspace:

    D:\AI\hypit\examples\ranking-football-local

## What this test covers

The local variant intentionally targets the capabilities already implemented by this repository:

    Hypit authoring
      -> Z-Image Turbo through @hypit/gpt-image@1#gpt-image-2
      -> Wan 2.2 TI2V 5B through @hypit/seedance@1#seedance-2-mini
      -> local media normalization
      -> local Media Track
      -> official Ranking TierBoard
      -> local soundtrack
      -> Film composition
      -> local HyperFrames
      -> local FFmpeg
      -> final.video

It makes:

- 1 local presenter image, 9:16, 1K
- 2 local B-roll images, 1:1, 1K
- 2 local Wan presenter takes, each 4 seconds, 480p, 9:16, no generated audio
- one 8-second Hypit composition using the official ranking sample's player photographs, soundtrack and recipes

This test deliberately does **not** use:

- HypiHub
- Fish Audio
- hosted GPT Image
- hosted Seedance
- generated speech
- WhisperX alignment

Those capabilities are outside the current local provider path for this test.

## Deploy

From the user's AI_videogenerate checkout:

    cd D:\AI
    git pull --ff-only

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy_hypit_ranking_local.ps1 -Force

The deployer:

1. copies the official ranking-football sample to ranking-football-local;
2. copies reference-local.svml and reference-local.svrun;
3. copies and builds the working local ComfyUI provider;
4. installs it into the sample;
5. derives a local-only Runtime Profile from HypitProjects/TestVideo/hypit.runtime.json;
6. runs hypit check and hypit plan.

A successful plan should show local requests routed to:

    comfyui.local (@local/provider-comfyui-local)

with no hosted Provider charge.

## Build the video

Run:

    cd D:\AI

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run_hypit_ranking_local.ps1

The runner starts the existing local media stack when needed, unloads Ollama models, stops the TestVideo WhisperX helper to free VRAM, then runs the complete Hypit Build.

Expected heavy generation:

    3 x Z-Image
    2 x Wan 2.2 4-second video
    1 x HyperFrames final render

On an RTX 4060 8 GB, the two Wan jobs dominate runtime.

## Output

Expected output:

    D:\AI\hypit\examples\ranking-football-local\output\final-local.mp4

## Why this is useful

The previous direct TestVideo workflow proved that the custom provider can generate media.

This sample tests a different question:

> Can an official Hypit-style composition use the local AI provider and continue through Hypit's own media, ranking, audio, film and rendering layers?

If this passes, the local stack is working as a real Hypit production backend rather than only as a standalone Wan generation script.
