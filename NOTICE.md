# Licensing notice

This repository combines two code bases with different licenses.

## Upstream Scoop — Unlicense or MIT

Everything not listed below comes from [ScoopInstaller/Scoop](https://github.com/ScoopInstaller/Scoop)
and stays under its original terms; see [`LICENSE`](./LICENSE).

## Shovel overlay — GPL-3.0-only

The following files are derived from [Ash258/Scoop-Core](https://github.com/Ash258/Scoop-Core)
("Shovel") by Jakub Čábera, which is licensed **GPL-3.0-only**. They carry an
`SPDX-License-Identifier: GPL-3.0-only` header and the license text is in
[`LICENSE.GPL-3.0`](./LICENSE.GPL-3.0).

- `lib/shovel/Shovel-Overlay.ps1`
- `lib/shovel/Shovel-Manifest.ps1`
- `lib/shovel/Shovel-Helpers.ps1`
- `lib/shovel/Shovel-ManifestHelpers.ps1`
- `lib/shovel/Shovel-Hooks.ps1`
- `supporting/completion/Scoop-Completion.psd1`
- `supporting/completion/Scoop-Completion.psm1`
- `supporting/completion/scoop.lua`

The hooks inside upstream files (every line marked `shovel-overlay`) and
`libexec/scoop-utils.ps1`, `bin/shovel.ps1`, `bin/shovel-upstream-merge.ps1`,
`bin/shovel-verify-overlay.ps1` were written for this repository, but they exist to drive the
GPL-3.0 code above.

Because GPL-3.0 is a copyleft license, **a distribution of this repository as a whole has to
comply with the GPL-3.0**. The permissive upstream parts remain available under their own
license from upstream. If that is not acceptable for your use case, the options are:

- do not distribute the overlay files (the repository then behaves like plain Scoop), or
- reimplement the overlay's functionality independently, or
- obtain different terms from the Shovel author.

This notice describes the licenses of the files; it is not legal advice.

## Vendored third-party components — Apache-2.0

- `supporting/yaml/bin/powershell-yaml.ps*` — [cloudbase/powershell-yaml](https://github.com/cloudbase/powershell-yaml) 0.4.2
- `supporting/yaml/bin/lib/**/YamlDotNet.dll` — [YamlDotNet](https://github.com/aaubry/YamlDotNet)

Their license texts ship next to the files (`supporting/yaml/bin/LICENSE`,
`supporting/yaml/bin/lib/*/LICENSE`). `supporting/yaml.json` records their provenance and how
to update them.
