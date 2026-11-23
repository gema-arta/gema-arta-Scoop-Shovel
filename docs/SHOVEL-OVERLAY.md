# Shovel compatibility overlay

This repository is upstream [Scoop](https://github.com/ScoopInstaller/Scoop) plus the
functionality of [Shovel](https://github.com/Ash258/Scoop-Core) (`Ash258/Scoop-Core`),
arranged so that **updates from upstream Scoop keep merging cleanly**.

- Upstream base: `ScoopInstaller/Scoop`, branch `master` (see `.shovel/overlay.json`)
- Ported from: `Ash258/Scoop-Core` (Shovel), last upstream activity December 2021
- Target bucket: [`Ash258/Shovel-Ash258`](https://github.com/Ash258/Shovel-Ash258) — 291 YAML manifests

## Why not a plain `git merge` of the two forks

Shovel forked in October 2020. Since then Scoop moved 550 commits ahead (v0.6.0, including
a reorganised `lib/`, the sqlite search cache, `scoop download`, `scoop shim`, arm64
support), while Shovel refactored the same files in its own direction and stopped in
December 2021. A direct `git merge` of `Ash258/Scoop-Core` into current Scoop conflicts in
**90 of 143 files** — effectively the whole code base, with no way to keep merging upstream
afterwards.

So the functionality was ported instead, as an *overlay*.

## Architecture

```
lib/shovel/                     the overlay itself (does not exist upstream)
  Shovel-Overlay.ps1            loader, dot-sourced from the single hook in lib/core.ps1
  Shovel-Manifest.ps1           YAML typed manifests, multi-extension manifest lookup
  Shovel-Helpers.ps1            Write-UserMessage, Confirm-DirectoryExistence, ...
  Shovel-ManifestHelpers.ps1    helpers callable from manifests (Test-Persistence, ...)
  Shovel-Hooks.ps1              manifest script properties upstream does not know (pre_download)
libexec/scoop-utils.ps1         'scoop utils' command
bin/shovel.ps1                  'shovel' alias of 'scoop'
bin/shovel-upstream-merge.ps1   merge upstream and check the overlay afterwards
bin/shovel-verify-overlay.ps1   verify that every hook is still in place
supporting/yaml/                vendored powershell-yaml + YamlDotNet (Apache-2.0)
supporting/completion/          native PowerShell tab completion, clink completion
.shovel/overlay.json            inventory of overlay files, hooks and functions
test/Shovel-Overlay.Tests.ps1   tests of the overlay, including hook integrity
```

Three rules keep this mergeable:

1. **Overlay code lives in files that do not exist upstream.** Those files can never
   conflict during a merge.
2. **The overlay never redefines an upstream function.** It only adds new ones, so the load
   order of `lib/*.ps1` is irrelevant and upstream behaviour is never silently replaced by a
   stale copy. A test enforces this.
3. **Changes inside upstream files are kept minimal and marked.** Every one of them carries a
   `shovel-overlay` marker, is listed in `.shovel/overlay.json` and is checked by
   `bin/shovel-verify-overlay.ps1`. The complete footprint in upstream files is about
   70 added and 45 removed lines over 19 files — mostly one-line changes such as
   `'*.json'` becoming a call to `Get-ShovelManifestItem`.

## What was ported

| Feature | Where | Notes |
| --- | --- | --- |
| YAML typed manifests (`.yml`, `.yaml`) | `lib/shovel/Shovel-Manifest.ps1` + hooks | install, update, search, cat, info, status, sqlite cache, checkver/autoupdate |
| `ConvertFrom-Manifest` / `ConvertTo-Manifest` | `lib/shovel/Shovel-Manifest.ps1` | Shovel compatible entry points |
| `Test-Persistence` | `lib/shovel/Shovel-ManifestHelpers.ps1` | used by 90 manifests of the bucket |
| `Assert-Administrator`, `Assert-WindowsMinimalVersion`, `Assert-ScoopConfigValue` | same | terminating errors |
| `Remove-AppDirItem`, `Edit-File`, `New-JavaShortcutWrapper` | same | `-Recurse` on `Remove-AppDirItem` is accepted and ignored |
| `Write-UserMessage`, `Confirm-DirectoryExistence`, `Out-UTF8Content`, `Stop-ScoopExecution` | `lib/shovel/Shovel-Helpers.ps1` | |
| `Invoke-ScoopCommand` | same | in-process `scoop <command>` for manifests |
| `pre_download` manifest property | `lib/shovel/Shovel-Hooks.ps1` + hook in `lib/download.ps1` | runs for install, update and `scoop download` |
| `Out-UTF8File <path> <content>` | hook in `lib/core.ps1` | 58 manifests of the bucket call it positionally |
| `scoop utils <utility>` | `libexec/scoop-utils.ps1` | wrapper around `bin/checkver`, `checkhashes`, `format`, ... |
| Native tab completion | `supporting/completion/` | command and option tables generated from this repository's `libexec` |
| `shovel` command | `bin/shovel.ps1` + hook in `libexec/scoop-update.ps1` | shim is created on the first `scoop update` |

### Deliberate design decisions

- **Installed manifests stay json.** A YAML bucket manifest is converted when it is saved as
  `scoop-manifest.json`, so `scoop list`, `scoop export`, `scoop status`, uninstall and the
  sqlite cache keep working untouched.
- **`json` wins over `yaml`/`yml`** when a bucket contains the same app name twice.
- **`scoop cat` prints json** for YAML manifests (the parsed object is formatted as json).
- **`checkver`/`autoupdate` write back in the manifest's own format**: a `.yml` manifest stays
  YAML, a `.json` manifest stays json.
- The overlay only reads YAML through the vendored `powershell-yaml`; no other dependency is
  introduced.

## How mergeable is it, in numbers

| Merge | Conflicted files |
| --- | --- |
| `Ash258/Scoop-Core` (Shovel) into current Scoop - the naive approach | **90 of 143** |
| `upstream/develop` (44 commits of real upstream work) into this overlay | **4** |

The four were `lib/database.ps1`, `lib/install.ps1`, `lib/manifest.ps1` and
`libexec/scoop-update.ps1`; no overlay file conflicted. Each was the documented case: upstream
had rewritten the code next to a one-line hook. Note that `upstream/develop` also moves the
update flow into a new `lib/update.ps1`, so the hooks currently living in
`libexec/scoop-update.ps1` will have to be re-homed when that lands in a release - exactly the
kind of drift `bin/shovel-upstream-merge.ps1 -DryRun` and the weekly workflow report.

## Updating from upstream Scoop

```powershell
# report what is coming and whether it touches a hooked file
.\bin\shovel-upstream-merge.ps1 -DryRun

# merge, then verify every hook survived
.\bin\shovel-upstream-merge.ps1
```

`master` is kept as a pristine mirror of `upstream/master`; the overlay lives on `shovel`.
That keeps `git merge upstream/master` a normal, reviewable merge.

If a conflict appears in a hooked file:

1. resolve it **in favour of upstream**,
2. re-apply the small marked hook (`git show HEAD:<file>` shows the pre-merge state; search
   for `shovel-overlay` there),
3. commit, then run `.\bin\shovel-verify-overlay.ps1`.

If upstream rewrote the hooked code so thoroughly that a hook no longer applies, remove it
from the file, drop or adjust its entry with `.\bin\shovel-verify-overlay.ps1 -Update`, and
note it here.

A lost hook is not a crash — it is a silently missing feature (for example YAML manifests
disappearing from `scoop search`). This is why the markers, the inventory and the test exist.

## Verifying

```powershell
.\bin\shovel-verify-overlay.ps1          # hooks, overlay files, functions
.\test\bin\test.ps1                      # the full test suite, including Shovel-Overlay.Tests.ps1
```

## Licensing

Upstream Scoop is Unlicense/MIT. Shovel is **GPL-3.0-only**, and the files listed as
"overlay files" above are derived from it, so they carry `SPDX-License-Identifier: GPL-3.0-only`
headers and the combined work is distributed under the terms of the GPL-3.0; see `NOTICE.md`.
The vendored `powershell-yaml` and `YamlDotNet` are Apache-2.0.
