#Requires -Version 5
<#
.SYNOPSIS
    Verify the integrity of the Shovel compatibility overlay.
.DESCRIPTION
    Run this after every merge of 'upstream/master' (bin/shovel-upstream-merge.ps1 does it
    automatically). It compares the repository with the inventory in '.shovel/overlay.json':

      - every overlay file is present,
      - every upstream file still carries its 'shovel-overlay' markers,
      - the overlay loads and exposes all required functions.

    A missing marker means an upstream change has removed a hook: the conflict was resolved
    in favour of upstream, the hooked code was rewritten or the whole function is gone.
    Re-apply the hook or adjust the inventory. Refer to docs/SHOVEL-OVERLAY.md.
.PARAMETER Update
    Rewrite the marker counts in '.shovel/overlay.json' instead of failing.
    Use it only after the hooks have been reviewed and re-applied.
.EXAMPLE
    .\bin\shovel-verify-overlay.ps1
.EXAMPLE
    .\bin\shovel-verify-overlay.ps1 -Update
#>
param(
    [Switch] $Update
)

Set-StrictMode -Off

$repoRoot = (Get-Item "$PSScriptRoot\..").FullName
$inventoryPath = Join-Path $repoRoot '.shovel\overlay.json'

if (!(Test-Path $inventoryPath -PathType 'Leaf')) {
    Write-Host "Inventory '$inventoryPath' not found." -ForegroundColor 'Red'
    exit 3
}

$inventory = Get-Content $inventoryPath -Raw -Encoding 'UTF8' | ConvertFrom-Json
$problems = @()
$warnings = @()

#region Overlay files
foreach ($file in $inventory.overlayFiles) {
    $full = Join-Path $repoRoot $file
    if (!(Test-Path $full -PathType 'Leaf')) {
        $problems += "Missing overlay file: $file"
    }
}
#endregion Overlay files

#region Hooks inside upstream files
$actualCounts = @{}
foreach ($entry in $inventory.hookedFiles) {
    $full = Join-Path $repoRoot $entry.file
    if (!(Test-Path $full -PathType 'Leaf')) {
        $problems += "Hooked file is gone: $($entry.file) (expected $($entry.markers) marker(s))"
        continue
    }

    $content = Get-Content $full -Raw -Encoding 'UTF8'
    $found = ([Regex]::Matches($content, 'shovel-overlay')).Count
    $actualCounts[$entry.file] = $found

    if ($found -lt $entry.markers) {
        $problems += "$($entry.file): $found of $($entry.markers) marker(s) left - a hook was lost"
    } elseif ($found -gt $entry.markers) {
        $warnings += "$($entry.file): $found marker(s) instead of $($entry.markers) - inventory is outdated"
    }
}
#endregion Hooks inside upstream files

#region Loaded functions
. (Join-Path $repoRoot 'lib\core.ps1')

foreach ($function in $inventory.requiredFunctions) {
    if (!(Get-Command $function -ErrorAction 'SilentlyContinue')) {
        $problems += "Overlay function is not available: $function"
    }
}
#endregion Loaded functions

if ($Update) {
    foreach ($entry in $inventory.hookedFiles) {
        if ($actualCounts.ContainsKey($entry.file)) { $entry.markers = $actualCounts[$entry.file] }
    }
    $inventory | ConvertTo-Json -Depth 10 | Out-UTF8File -FilePath $inventoryPath
    Write-Host 'Inventory updated.' -ForegroundColor 'Green'
}

foreach ($warning in $warnings) { Write-Host "WARN  $warning" -ForegroundColor 'DarkYellow' }

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) { Write-Host "ERROR $problem" -ForegroundColor 'Red' }
    Write-Host ''
    Write-Host "The overlay is broken: $($problems.Count) problem(s). See docs/SHOVEL-OVERLAY.md." -ForegroundColor 'Red'
    exit 1
}

Write-Host "Shovel overlay $(Get-ShovelOverlayVersion) is intact:" -ForegroundColor 'Green'
Write-Host "  overlay files    $($inventory.overlayFiles.Count)"
Write-Host "  hooked files     $($inventory.hookedFiles.Count)"
Write-Host "  hook markers     $(($actualCounts.Values | Measure-Object -Sum).Sum)"
Write-Host "  functions        $($inventory.requiredFunctions.Count)"
Write-Host "  upstream base    $($inventory.upstream.mergedRelease) ($($inventory.upstream.mergedCommit.Substring(0, 8)))"

exit 0
