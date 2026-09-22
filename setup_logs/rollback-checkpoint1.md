# Checkpoint 1 Rollback

Pre-existing checkpoint artifact: `D:\AI\setup_specs`.

Created during Task 1:
- `D:\AI\setup_logs`
- `D:\AI\config_backup`
- `D:\AI\HypitProjects`

Shared Winget tools remain installed unless the user explicitly requests their uninstall.

Task 2 installed shared packages:
- `astral-sh.uv` 0.12.17 through Winget.
- `Gyan.FFmpeg.Shared` 9.0.2 through Winget.
- These remain installed by default during rollback.

Task 3 created:
- `D:\AI\hypit` cloned from `https://github.com/hypit-ai/hypit.git`.
- Exact initial commit: $head.

Task 6 installed:
- Global Hypit CLI from $archive.
- Archive SHA-256: $hash.
- Roll back with `npm.cmd uninstall -g @hypit/hypit`; verify the resolved package before running.

Task 7 installed:
- Hypit skill at $(SKILL.md[0].Directory.FullName).
- Back up this exact directory before removal during an explicit rollback.

Task 8 created:
- `D:\AI\HypitProjects\TestVideo`.
- `D:\AI\HypitProjects\TestVideo\hypit.runtime.json` through `hypit runtime init`.
- Remove or archive only after verifying the absolute path and that no user data was later added.
