# SPDX-License-Identifier: GPL-3.0-only
# Loader of the Shovel compatibility overlay for Scoop.
#
# This file is dot-sourced from the single hook placed at the end of 'lib/core.ps1',
# which makes the whole overlay available to every scoop command, every bin/ script
# and to manifest scripts.
#
# Design rules of the overlay (see docs/SHOVEL-OVERLAY.md):
#   1. Overlay code lives in files which do not exist upstream => it never conflicts
#      when 'upstream/master' is merged.
#   2. Overlay files never redefine an upstream function, so the load order of
#      'lib/*.ps1' does not matter and upstream behaviour is never silently replaced.
#   3. Changes inside upstream files are kept to a minimum and are always wrapped
#      in '#region shovel-overlay: <id>' markers, tracked in '.shovel/overlay.json'
#      and verified by 'bin/shovel-verify-overlay.ps1'.

if ($SHOVEL_OVERLAY_FORCE_RELOAD -or !(Get-Command 'Get-ShovelOverlayVersion' -ErrorAction 'SilentlyContinue')) {
    @(
        'Shovel-Manifest.ps1'
        'Shovel-Helpers.ps1'
        'Shovel-ManifestHelpers.ps1'
        'Shovel-Hooks.ps1'
    ) | ForEach-Object {
        . (Join-Path $PSScriptRoot $_)
    }
}
