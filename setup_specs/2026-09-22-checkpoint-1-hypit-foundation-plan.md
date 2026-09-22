# Checkpoint 1 Hypit Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install and verify a reproducible Hypit foundation under `D:\AI` while leaving the existing Hypit checkout and existing system runtimes unchanged.

**Architecture:** Treat `D:\AI\hypit` as an immutable-after-verification source checkout and build the installed CLI from its exact commit. Install only the missing shared executables, keep all project state and audit records below `D:\AI`, and gate every mutation with a precheck and a fresh verification.

**Tech Stack:** Windows 11 PowerShell, Git 2.55.0, Node.js 24.21.0, Corepack 0.36.0, pnpm 10.33.0, Winget, uv, FFmpeg/FFprobe, Hypit 0.2.12 or the exact version present at the newly cloned commit.

**Spec:** `D:\AI\setup_specs\2026-09-22-checkpoint-1-hypit-foundation-design.md`

## Global Constraints

- Never modify `D:\2026_Part2\2026_Part2\Source\hypit`; verify its status and commit before and after the checkpoint.
- Keep Python 3.14.7, Node.js 24.21.0, NVIDIA driver 616.64, CUDA system state, registry, Windows Security, antivirus, and PowerShell execution policy unchanged.
- Use `npm.cmd`, `npx.cmd`, and `corepack.cmd` to avoid PowerShell script-policy ambiguity.
- Install only pnpm 10.33.0 through Corepack and system FFmpeg/uv when their prechecks still show them missing.
- Do not run `git pull`, `npm update`, `pnpm update`, an unfrozen install, or dependency-version experiments.
- Do not edit Hypit source to force a check or test to pass.
- Redact secrets by logging only selected commands and selected outputs, never the complete environment.
- Stop before any action outside the approved scope or any action that risks existing user data.

## Review Focus

- A stale current-shell PATH after Winget installation must be handled by executable discovery or a fresh process, never by manual PATH editing; Task 2 tests this.
- A pre-existing `D:\AI\hypit` must never be overwritten, reset, cleaned, or pulled; Task 3 tests identity and cleanliness before choosing clone behavior.
- Corepack may be unable to write beside the system Node installation without elevation; Task 4 detects this and stops rather than changing policy or improvising another package-manager version.
- Test-suite failures may come from optional external programs; Task 5 captures exact failing tests and separately verifies the required CLI path before any checkpoint decision.
- A pre-existing test-project Runtime profile must be backed up and preserved; Task 8 tests for the file before invoking initialization.

---

### Task 1: Establish the audit boundary and logging files

**Files:**
- Create: `D:\AI\setup_logs\environment.txt`
- Create: `D:\AI\setup_logs\hypit_install.log`
- Create: `D:\AI\setup_logs\checkpoint1_verification.log`
- Create: `D:\AI\setup_logs\rollback-checkpoint1.md`
- Use: `D:\AI\setup_specs\2026-09-22-checkpoint-1-hypit-foundation-design.md`

**Interfaces:**
- Consumes: approved design spec and current machine state.
- Produces: timestamped audit logs used by every later task.

- [ ] **Step 1: Verify the immutable source checkout before creating checkpoint artifacts**

Run from `D:\2026_Part2\2026_Part2\Source\hypit`:

```powershell
git status --short --branch
git rev-parse HEAD
git remote get-url origin
```

Expected: clean `main`, commit `9c9918d0cedf2f06574ab0d517b1b6b0afb56a66`, official Hypit remote. If it differs, record the actual state and do not modify it.

- [ ] **Step 2: Create only the approved checkpoint directories**

```powershell
$paths = @(
  'D:\AI\setup_logs',
  'D:\AI\config_backup',
  'D:\AI\HypitProjects'
)
$paths | ForEach-Object {
  if (-not (Test-Path -LiteralPath $_)) {
    New-Item -ItemType Directory -Path $_ | Out-Null
  }
}
```

Expected: each path resolves below `D:\AI`.

- [ ] **Step 3: Capture selected baseline data without dumping environment variables**

Run the approved hardware and executable probes and append their stdout/stderr plus ISO-8601 timestamp and exit code to `environment.txt`. Include `nvidia-smi`, RAM, physical disks, D-drive free space, versions, and `where.exe` results for Git, Node, npm, Corepack, pnpm, Python, py, uv, FFmpeg, FFprobe, Codex, and Winget.

Expected: no password, token, API key, or full environment-variable listing.

- [ ] **Step 4: Write initial rollback inventory**

Record that the only pre-existing checkpoint artifact is `D:\AI\setup_specs`; list every directory created in Step 2. State that shared Winget tools remain installed by default during rollback.

### Task 2: Install and verify only uv and FFmpeg

**Files:**
- Modify: `D:\AI\setup_logs\environment.txt`
- Modify: `D:\AI\setup_logs\hypit_install.log`
- Modify: `D:\AI\setup_logs\rollback-checkpoint1.md`

**Interfaces:**
- Consumes: baseline executable discovery from Task 1.
- Produces: verified absolute paths and versions for uv, FFmpeg, and FFprobe.

- [ ] **Step 1: Re-run missing-tool prechecks**

```powershell
Get-Command uv -ErrorAction SilentlyContinue
Get-Command ffmpeg -ErrorAction SilentlyContinue
Get-Command ffprobe -ErrorAction SilentlyContinue
winget list --id astral-sh.uv -e
winget list --id Gyan.FFmpeg.Shared -e
```

Expected from the audit: all are absent. If any are now present, skip its installation and verify the existing binary.

- [ ] **Step 2: Install uv if still absent**

```powershell
winget install --id astral-sh.uv -e --accept-package-agreements --accept-source-agreements
```

Expected: Winget reports success with exit code 0. Save full command output in `hypit_install.log`.

- [ ] **Step 3: Install FFmpeg if still absent**

```powershell
winget install --id Gyan.FFmpeg.Shared -e --accept-package-agreements --accept-source-agreements
```

Expected: Winget reports success with exit code 0. Save full command output in `hypit_install.log`.

- [ ] **Step 4: Discover binaries without editing PATH**

Start a fresh PowerShell child process and run:

```powershell
where.exe uv
where.exe ffmpeg
where.exe ffprobe
uv --version
ffmpeg -version
ffprobe -version
```

If the fresh process still cannot discover a binary, query the Winget package location and invoke the exact binary path for diagnosis. Do not edit PATH manually. Expected: all three version commands exit 0.

- [ ] **Step 5: Record shared-tool rollback facts**

Append package identifiers, installed versions, exact executable paths, and the policy that uninstall requires an explicit rollback request.

### Task 3: Create and freeze the new Hypit source checkout

**Files:**
- Create: `D:\AI\hypit\` by Git clone only when absent.
- Modify: `D:\AI\setup_logs\hypit_install.log`
- Modify: `D:\AI\setup_logs\rollback-checkpoint1.md`

**Interfaces:**
- Consumes: Git executable and empty-or-validated target path.
- Produces: official clean Hypit checkout with recorded commit, version, and package-manager pin.

- [ ] **Step 1: Test target-path state before clone**

```powershell
if (Test-Path -LiteralPath 'D:\AI\hypit') {
  git -C 'D:\AI\hypit' status --short --branch
  git -C 'D:\AI\hypit' remote -v
  git -C 'D:\AI\hypit' rev-parse HEAD
} else {
  'ABSENT'
}
```

Expected on first execution: `ABSENT`. If present, require the official remote and preserve all local changes; do not clone, pull, reset, clean, or checkout over it.

- [ ] **Step 2: Clone only when absent**

```powershell
git clone https://github.com/hypit-ai/hypit.git D:\AI\hypit
```

Expected: exit code 0 and an official `origin` remote.

- [ ] **Step 3: Record and validate repository identity**

```powershell
git -C 'D:\AI\hypit' status --short --branch
git -C 'D:\AI\hypit' remote get-url origin
git -C 'D:\AI\hypit' rev-parse HEAD
git -C 'D:\AI\hypit' branch --show-current
node -p "const p=require('D:/AI/hypit/package.json'); JSON.stringify({version:p.version,packageManager:p.packageManager,engines:p.engines})"
```

Expected: clean worktree, official remote, `main`, an exact commit, Node requirement satisfied, and `packageManager` equal to `pnpm@10.33.0`. These actual values supersede audit-reference version numbers.

### Task 4: Activate the pinned pnpm and install frozen dependencies

**Files:**
- Generate: dependency installation state below `D:\AI\hypit\node_modules`
- Must not modify: `D:\AI\hypit\pnpm-lock.yaml`
- Modify: `D:\AI\setup_logs\hypit_install.log`

**Interfaces:**
- Consumes: package-manager pin from Task 3.
- Produces: installed workspace dependencies using the exact lockfile.

- [ ] **Step 1: Hash the lockfile before installation**

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\AI\hypit\pnpm-lock.yaml'
```

Expected: one SHA-256 value saved to the install log.

- [ ] **Step 2: Enable and prepare the exact pnpm version**

```powershell
corepack.cmd enable
corepack.cmd prepare pnpm@10.33.0 --activate
pnpm.cmd --version
where.exe pnpm
```

Expected: pnpm `10.33.x`, specifically `10.33.0`. If `corepack enable` is denied at the protected Node location, stop and report the exact error; do not change policy or install a different version globally.

- [ ] **Step 3: Install dependencies from the frozen lockfile**

```powershell
Set-Location -LiteralPath 'D:\AI\hypit'
pnpm.cmd install --frozen-lockfile
```

Expected: exit code 0 without lockfile rewrite.

- [ ] **Step 4: Prove repository and lockfile integrity**

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'D:\AI\hypit\pnpm-lock.yaml'
git -C 'D:\AI\hypit' status --short --branch
```

Expected: lockfile hash unchanged and worktree clean.

### Task 5: Verify the Hypit source checkout

**Files:**
- Modify: `D:\AI\setup_logs\hypit_install.log`
- Modify: `D:\AI\setup_logs\checkpoint1_verification.log`

**Interfaces:**
- Consumes: frozen workspace from Task 4.
- Produces: exact type-check, test-suite, and direct-CLI evidence.

- [ ] **Step 1: Run the TypeScript check**

```powershell
Set-Location -LiteralPath 'D:\AI\hypit'
pnpm.cmd check
```

Expected: exit code 0. On failure, capture the exact diagnostics and investigate the first causal error before changing anything.

- [ ] **Step 2: Run the full repository suite**

```powershell
pnpm.cmd test
```

Expected: exit code 0. On failure, preserve the failing test names and output, identify whether they exercise required Runtime functionality or an unavailable optional external environment, and do not edit source to suppress them.

- [ ] **Step 3: Verify the direct CLI independently**

```powershell
node .\bin\hypit.mjs --version
```

Expected: exit code 0 and the same Hypit version recorded from `package.json`.

- [ ] **Step 4: Recheck source integrity**

```powershell
git status --short --branch
git diff -- pnpm-lock.yaml
```

Expected: clean worktree and no lockfile diff.

### Task 6: Build and install the exact Hypit distribution

**Files:**
- Generate: the single versioned `hypit-hypit-*.tgz` archive under `D:\AI\hypit\dist\release`
- Modify: npm global package state below `C:\Users\Khach\AppData\Roaming\npm`
- Modify: `D:\AI\setup_logs\hypit_install.log`
- Modify: `D:\AI\setup_logs\rollback-checkpoint1.md`

**Interfaces:**
- Consumes: verified clean source from Task 5.
- Produces: globally callable Hypit CLI traceable to a hashed local archive.

- [ ] **Step 1: Build the distribution**

```powershell
Set-Location -LiteralPath 'D:\AI\hypit'
npm.cmd run pack:distribution
```

Expected: exit code 0 and release artifacts only under `dist\release`.

- [ ] **Step 2: Require exactly one package archive and hash it**

```powershell
$archives = @(Get-ChildItem -LiteralPath 'D:\AI\hypit\dist\release' -Filter '*.tgz' -File)
if ($archives.Count -ne 1) { throw "Expected one release archive; found $($archives.Count)." }
$archive = $archives[0].FullName
Get-FileHash -Algorithm SHA256 -LiteralPath $archive
```

Expected: one absolute archive path and SHA-256 value.

- [ ] **Step 3: Install that exact archive globally**

```powershell
npm.cmd install -g $archive
```

Expected: exit code 0; do not install a registry version.

- [ ] **Step 4: Verify installed CLI and origin information**

```powershell
where.exe hypit
hypit --version
hypit version --check
npm.cmd prefix -g
```

Expected: global CLI resolves from the existing npm prefix, reports the built version, and `version --check` completes. A report that a newer upstream release exists is informational and must not trigger an update.

### Task 7: Install and verify the Hypit Codex skill

**Files:**
- Create or update through upstream installer: a `hypit` skill below the installer-selected user skill root.
- Modify: `D:\AI\setup_logs\hypit_install.log`
- Modify: `D:\AI\setup_logs\rollback-checkpoint1.md`

**Interfaces:**
- Consumes: official GitHub repository and upstream skill installer command.
- Produces: readable user-level Hypit `SKILL.md` and recorded resolved installation path.

- [ ] **Step 1: Inspect existing matching skill locations**

```powershell
$roots = @(
  'C:\Users\Khach\.agents\skills',
  'C:\Users\Khach\.codex\skills'
)
$roots | ForEach-Object {
  if (Test-Path -LiteralPath $_) {
    Get-ChildItem -LiteralPath $_ -Directory -Force | Where-Object Name -Match 'hypit'
  }
}
```

Expected: either no existing Hypit skill or an exact existing path that must be preserved and reported before installation.

- [ ] **Step 2: Run the upstream global skill installer**

```powershell
Set-Location -LiteralPath 'D:\AI\hypit'
npx.cmd skills add hypit-ai/hypit -g
```

Expected: exit code 0 and an explicit destination. Do not manually copy skill files after success.

- [ ] **Step 3: Verify the installed skill**

Resolve the destination reported by the installer and cross-check it by finding a skill whose `SKILL.md` declares the name `hypit`:

```powershell
$skillFiles = @($roots | ForEach-Object {
  if (Test-Path -LiteralPath $_) {
    Get-ChildItem -LiteralPath $_ -Recurse -Filter 'SKILL.md' -File
  }
} | Where-Object {
  (Get-Content -Raw -LiteralPath $_.FullName) -match '(?m)^name:\s*hypit\s*$'
})
if ($skillFiles.Count -ne 1) {
  throw "Expected one installed Hypit skill; found $($skillFiles.Count)."
}
Get-Item -LiteralPath $skillFiles[0].FullName
Get-Content -LiteralPath $skillFiles[0].FullName -TotalCount 20
```

Expected: readable file with Hypit skill metadata at the destination printed by the installer. Record whether Codex requires restart for discovery; do not alter Codex configuration when discovery is already correct.

### Task 8: Initialize and verify the standalone test project

**Files:**
- Create: `D:\AI\HypitProjects\TestVideo\`
- Create through Hypit: Runtime project files reported by `hypit runtime init`.
- Backup if present: a timestamped `TestVideo-hypit.runtime.json.*.bak` file under `D:\AI\config_backup`
- Modify: `D:\AI\setup_logs\checkpoint1_verification.log`
- Modify: `D:\AI\setup_logs\rollback-checkpoint1.md`

**Interfaces:**
- Consumes: installed global Hypit CLI.
- Produces: initialized project directory and confirmed local Runtime paths for checkpoint 2.

- [ ] **Step 1: Inspect project state before creation or initialization**

```powershell
$project = 'D:\AI\HypitProjects\TestVideo'
if (Test-Path -LiteralPath $project) {
  Get-ChildItem -LiteralPath $project -Force
}
```

Expected on first execution: absent or empty directory. If user data exists, stop before initialization.

- [ ] **Step 2: Create the project directory and protect an existing Runtime profile**

```powershell
if (-not (Test-Path -LiteralPath $project)) {
  New-Item -ItemType Directory -Path $project | Out-Null
}
$runtime = Join-Path $project 'hypit.runtime.json'
if (Test-Path -LiteralPath $runtime) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  Copy-Item -LiteralPath $runtime -Destination "D:\AI\config_backup\TestVideo-hypit.runtime.json.$stamp.bak"
}
```

Expected: project directory exists; any old profile has a byte-preserving backup.

- [ ] **Step 3: Initialize from the project directory**

```powershell
Set-Location -LiteralPath $project
hypit runtime init
hypit paths
```

Expected: both commands exit 0, Runtime files are project-local, and reported host state/data paths are recorded. Do not start Runtime programs in checkpoint 1.

- [ ] **Step 4: Inventory created project files**

```powershell
Get-ChildItem -LiteralPath $project -Recurse -Force | Select-Object FullName,Length,LastWriteTime
```

Expected: exact initialization artifact list saved to verification and rollback logs.

### Task 9: Execute the checkpoint verification gate

**Files:**
- Modify: `D:\AI\setup_logs\checkpoint1_verification.log`
- Modify: `D:\AI\setup_logs\rollback-checkpoint1.md`

**Interfaces:**
- Consumes: all Task 1-8 outputs.
- Produces: pass/fail checkpoint record and immutable version manifest for checkpoint 2.

- [ ] **Step 1: Run fresh version and path probes**

Run and log exit codes for `node --version`, `pnpm.cmd --version`, `uv --version`, `ffmpeg -version`, `ffprobe -version`, `hypit --version`, `hypit version --check`, and their `where.exe` paths.

Expected: Node remains 24.21.0, pnpm is 10.33.0, and every required binary exits 0.

- [ ] **Step 2: Re-run source and project probes**

```powershell
git -C 'D:\AI\hypit' status --short --branch
git -C 'D:\AI\hypit' rev-parse HEAD
git -C 'D:\AI\hypit' remote get-url origin
node 'D:\AI\hypit\bin\hypit.mjs' --version
Set-Location -LiteralPath 'D:\AI\HypitProjects\TestVideo'
hypit paths
```

Expected: clean official checkout, exact recorded commit, direct CLI success, and project path success.

- [ ] **Step 3: Verify the original checkout remained unchanged**

```powershell
git -C 'D:\2026_Part2\2026_Part2\Source\hypit' status --short --branch
git -C 'D:\2026_Part2\2026_Part2\Source\hypit' rev-parse HEAD
```

Expected: clean `main` at `9c9918d0cedf2f06574ab0d517b1b6b0afb56a66`.

- [ ] **Step 4: Write the checkpoint decision**

Record PASS only if the spec's complete Verification Gate has fresh supporting output. If any check fails, record FAIL, the exact command, error, determined cause, completed parts, and smallest safe next action. Do not begin checkpoint 2 on FAIL.

- [ ] **Step 5: Freeze the version manifest and rollback instructions**

Record exact Hypit commit/version/archive hash, Node, pnpm, uv, FFmpeg, FFprobe, Git, Codex, all executable paths, skill path, project path, and npm prefix. State explicitly that no automatic pull or dependency update is permitted after PASS.
