# Checkpoint 1: Windows and Hypit Foundation Design

Date: 2026-09-22

## Objective

Create a reproducible Hypit installation rooted at `D:\AI` without changing the existing checkout at `D:\2026_Part2\2026_Part2\Source\hypit` or replacing the machine's existing Python, Node.js, NVIDIA driver, CUDA runtime, or PowerShell execution policy.

Checkpoint 1 is complete only when the new Hypit checkout, dependencies, packaged CLI, Codex skill, test project, and local Runtime initialization have been verified from their intended locations.

## Confirmed Baseline

- GPU: NVIDIA GeForce RTX 4060, 8,188 MiB VRAM.
- NVIDIA driver: 616.64; driver-reported CUDA UMD runtime: 13.4.
- RAM: 34,111,557,632 bytes, approximately 32 GiB.
- Storage: Kingston SNV3S1000G SSD; drive D has approximately 473.55 GiB free.
- Git: 2.55.0.windows.3 at `C:\Program Files\Git\cmd\git.exe`.
- Node.js: 24.21.0 at `C:\Program Files\nodejs\node.exe`.
- npm: 12.0.2; invoke `npm.cmd` because the current PowerShell policy blocks `npm.ps1`.
- Corepack: 0.36.0 at `C:\Program Files\nodejs\corepack.cmd`.
- Python: 3.14.7. It is retained unchanged and is not selected for Hypit or WhisperX.
- Codex CLI: 0.155.1.
- Missing from PATH: pnpm, uv, FFmpeg, and FFprobe.
- Existing Hypit checkout: clean `main` at `9c9918d0cedf2f06574ab0d517b1b6b0afb56a66`. It is audit reference only and must remain unchanged.

## Target Layout

Checkpoint 1 creates or uses only these paths:

```text
D:\AI\
|-- hypit\
|-- HypitProjects\
|   `-- TestVideo\
|-- setup_logs\
|-- setup_specs\
`-- config_backup\
```

Later checkpoints may add `ComfyUI`, `models`, `workflows`, and project-local provider files. They are outside checkpoint 1.

## Installation Strategy

### Environment snapshot and logs

Before each mutation, record the relevant current state. Store command transcripts under `D:\AI\setup_logs`:

- `environment.txt`: hardware, disk, tool versions, and executable paths.
- `hypit_install.log`: clone, package manager, dependency, build, and CLI installation output.
- `checkpoint1_verification.log`: final verification commands and exit codes.
- `rollback-checkpoint1.md`: exact artifacts introduced by this checkpoint and their removal procedure.

Logs must not contain passwords, tokens, API keys, or unrelated environment variables.

### Missing system tools

Recheck FFmpeg and uv immediately before installation. Install only if still absent:

```powershell
winget install --id Gyan.FFmpeg.Shared -e
winget install --id astral-sh.uv -e
```

Do not alter PATH manually. Refresh command discovery in a new process or use the installed absolute path for verification if the current shell has stale PATH state. Do not continue until `ffmpeg`, `ffprobe`, and `uv` are executable and their exact paths and versions are recorded.

### Hypit source checkout

Before cloning, inspect `D:\AI\hypit` if it exists. If absent, clone:

```powershell
git clone https://github.com/hypit-ai/hypit.git D:\AI\hypit
```

If present, verify its remote, branch, worktree status, and identity. Never clone over it, reset it, clean it, or discard local changes. Do not run `git pull` automatically. Record the exact commit selected for this installation.

### pnpm and dependencies

Use the checked-out repository's `packageManager` field as the authority. The audited source pins `pnpm@10.33.0`.

```powershell
corepack.cmd enable
corepack.cmd prepare pnpm@10.33.0 --activate
pnpm.cmd --version
pnpm.cmd install --frozen-lockfile
```

If `corepack enable` would require changing protected system files or elevation, stop and report the smallest safe alternative instead of modifying system policy. Do not use `npm install` as a substitute for workspace dependency installation and do not change the lockfile.

### Repository verification

Run from `D:\AI\hypit`:

```powershell
pnpm.cmd check
pnpm.cmd test
node .\bin\hypit.mjs --version
```

On failure, retain the exact command and output, identify the failing test or subsystem, and distinguish source defects from optional or external-environment requirements. Do not edit Hypit source merely to make the suite green. A required CLI or Runtime failure blocks the checkpoint; an unrelated optional-environment test may be documented as a limitation only after the required path is independently verified.

### Distribution and global CLI

Build from the verified source:

```powershell
npm.cmd run pack:distribution
```

Select the single generated `.tgz` in `D:\AI\hypit\dist\release`, record its name and hash, then install that exact file:

```powershell
npm.cmd install -g <absolute-tgz-path>
hypit --version
hypit version --check
```

The npm global prefix is currently `C:\Users\Khach\AppData\Roaming\npm`. Do not change it.

### Codex Hypit skill

Use the upstream Hypit installation command from the selected checkout:

```powershell
npx.cmd skills add hypit-ai/hypit -g
```

Record the installer output and inspect the resulting directory. The expected user-level discovery root is `C:\Users\Khach\.agents\skills`. Do not copy the skill manually after a successful installer run. Verify that the installed skill has a readable `SKILL.md`; restart Codex only if the active process does not discover the newly installed skill.

### Test project and Runtime initialization

Create `D:\AI\HypitProjects\TestVideo` and run these commands from that directory, never from the Hypit source checkout:

```powershell
hypit runtime init
hypit paths
```

If initialization would replace an existing configuration, back up the file under `D:\AI\config_backup` first and merge intentionally. Record every created project file and the reported Runtime paths. Starting HyperFrames or WhisperX is checkpoint 2 and is not part of checkpoint 1.

## Safety and Failure Handling

- No command may modify the existing checkout at `D:\2026_Part2\2026_Part2\Source\hypit`.
- Do not uninstall or replace Python 3.14.7, Node 24.21.0, the NVIDIA driver, or the system CUDA runtime.
- Do not change PowerShell execution policy, registry settings, Windows Security, or antivirus.
- Do not run dependency upgrades, `git pull`, `npm update`, `pnpm update`, or an unfrozen install.
- Make one causal change at a time when debugging. Re-run the failed command after correcting its identified cause.
- Stop for user input only if a required action leaves this design's scope or risks the existing environment.

## Verification Gate

Checkpoint 1 passes only when fresh command output establishes all of the following:

- `D:\AI\hypit` has the official remote, a clean worktree, and a recorded exact commit.
- Node remains 24.21.0.
- pnpm reports 10.33.x.
- uv, FFmpeg, and FFprobe execute and have recorded paths and versions.
- `pnpm install --frozen-lockfile` completes without altering `pnpm-lock.yaml`.
- `pnpm check` passes, or a precisely classified non-runtime optional failure is documented.
- `pnpm test` passes, or a precisely classified non-runtime optional failure is documented.
- Direct Hypit CLI execution succeeds.
- The source-built `.tgz` is identified and installed; global `hypit --version` succeeds.
- `hypit version --check` executes and its result is recorded.
- The Hypit skill exists under the actual Codex discovery path with `SKILL.md` readable.
- `D:\AI\HypitProjects\TestVideo` is initialized successfully.
- `hypit paths` succeeds from the test project.
- Logs and rollback instructions exist and contain no secrets.

Only after this gate passes may checkpoint 2 prepare and start HyperFrames and WhisperX.

## Rollback Design

Rollback is scoped to artifacts introduced by checkpoint 1:

1. Stop any Hypit process started for verification, if one exists.
2. Uninstall only the globally installed source-built Hypit package using `npm.cmd`.
3. Remove only the Hypit skill directory created by this checkpoint after verifying its exact resolved path and backing it up.
4. Preserve logs and the spec unless the user requests their removal.
5. Remove or archive only `D:\AI\hypit` and `D:\AI\HypitProjects\TestVideo` after verifying their absolute paths and confirming they contain no pre-existing user data.
6. Leave Winget-installed FFmpeg and uv in place by default because they are shared tools; uninstall them only on an explicit rollback request.

Rollback never touches the pre-existing Hypit checkout, Python, Node, driver, CUDA runtime, registry, PowerShell policy, model caches, or unrelated processes.
