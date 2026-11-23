#Requires -Version 5
<#
.SYNOPSIS
    Merge the current state of upstream Scoop into this repository.
.DESCRIPTION
    The Shovel overlay is built so that upstream Scoop stays mergeable:
    overlay code lives in files which do not exist upstream and the changes inside
    upstream files are tiny and marked with 'shovel-overlay'.

    This script performs the whole routine:

      1. fetch the upstream remote,
      2. report the incoming commits and, separately, the incoming commits which touch
         a file carrying overlay hooks (those are the ones worth reviewing),
      3. merge (optional),
      4. verify that all hooks survived the merge and refresh '.shovel/overlay.json'.

    Conflicts are left in the working tree for a human to resolve. Resolve them in favour
    of upstream and re-apply the small marked hook afterwards.
.PARAMETER Remote
    Name of the upstream remote. Default 'upstream'.
.PARAMETER Branch
    Upstream branch to merge. Default 'master'.
.PARAMETER DryRun
    Only report what would be merged.
.PARAMETER NoVerify
    Skip the overlay verification after a successful merge.
.EXAMPLE
    .\bin\shovel-upstream-merge.ps1 -DryRun
.EXAMPLE
    .\bin\shovel-upstream-merge.ps1
#>
param(
    [String] $Remote = 'upstream',
    [String] $Branch = 'master',
    [Switch] $DryRun,
    [Switch] $NoVerify
)

Set-StrictMode -Off

$UPSTREAM_URL = 'https://github.com/ScoopInstaller/Scoop'
$repoRoot = (Get-Item "$PSScriptRoot\..").FullName
$inventoryPath = Join-Path $repoRoot '.shovel\overlay.json'

function Invoke-GitCommand {
    param([String[]] $ArgumentList, [Switch] $IgnoreExitCode)

    $output = & git -C $repoRoot @ArgumentList 2>&1
    if (($LASTEXITCODE -ne 0) -and !$IgnoreExitCode) {
        Write-Host "git $($ArgumentList -join ' ') failed:" -ForegroundColor 'Red'
        Write-Host ($output -join "`r`n") -ForegroundColor 'Red'
        exit 1
    }

    return $output
}

if (!(Get-Command 'git' -ErrorAction 'SilentlyContinue')) {
    Write-Host 'git is required.' -ForegroundColor 'Red'
    exit 3
}

if (!(Test-Path (Join-Path $repoRoot '.git'))) {
    Write-Host "'$repoRoot' is not a git repository." -ForegroundColor 'Red'
    exit 3
}

#region Preconditions
$dirty = Invoke-GitCommand @('status', '--porcelain')
if ($dirty) {
    Write-Host 'The working tree is not clean. Commit or stash your changes first:' -ForegroundColor 'Red'
    Write-Host ($dirty -join "`r`n")
    exit 1
}

$remotes = Invoke-GitCommand @('remote')
if ($remotes -notcontains $Remote) {
    Write-Host "Adding remote '$Remote' => $UPSTREAM_URL"
    Invoke-GitCommand @('remote', 'add', $Remote, $UPSTREAM_URL) | Out-Null
}
#endregion Preconditions

Write-Host "Fetching '$Remote'..." -ForegroundColor 'DarkCyan'
Invoke-GitCommand @('fetch', '--quiet', $Remote) | Out-Null

$target = "$Remote/$Branch"
$incoming = @(Invoke-GitCommand @('log', '--oneline', "HEAD..$target"))

if ($incoming.Count -eq 0) {
    Write-Host "Nothing to merge, already up to date with $target." -ForegroundColor 'Green'
    exit 0
}

Write-Host ''
Write-Host "$($incoming.Count) incoming commit(s) from ${target}:" -ForegroundColor 'DarkCyan'
$incoming | Select-Object -First 25 | ForEach-Object { Write-Host "  $_" }
if ($incoming.Count -gt 25) { Write-Host "  ... and $($incoming.Count - 25) more" }

#region Changes touching hooked files
$inventory = Get-Content $inventoryPath -Raw -Encoding 'UTF8' | ConvertFrom-Json
$hookedFiles = $inventory.hookedFiles.file
$changedFiles = @(Invoke-GitCommand @('diff', '--name-only', "HEAD...$target"))
$risky = @($changedFiles | Where-Object { $hookedFiles -contains ($_ -replace '\\', '/') })

Write-Host ''
if ($risky.Count -eq 0) {
    Write-Host 'No incoming change touches a hooked file. The merge should be trivial.' -ForegroundColor 'Green'
} else {
    Write-Host "$($risky.Count) hooked file(s) are modified upstream - review these after merging:" -ForegroundColor 'DarkYellow'
    $risky | ForEach-Object { Write-Host "  $_" -ForegroundColor 'DarkYellow' }
}
#endregion Changes touching hooked files

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run, nothing was merged.' -ForegroundColor 'DarkGray'
    exit 0
}

Write-Host ''
Write-Host "Merging $target..." -ForegroundColor 'DarkCyan'
$mergeOutput = Invoke-GitCommand @('merge', '--no-edit', $target) -IgnoreExitCode
$mergeFailed = $LASTEXITCODE -ne 0
Write-Host ($mergeOutput -join "`r`n")

if ($mergeFailed) {
    $conflicts = @(Invoke-GitCommand @('diff', '--name-only', '--diff-filter=U'))
    Write-Host ''
    Write-Host "Merge stopped with $($conflicts.Count) conflicted file(s):" -ForegroundColor 'DarkYellow'
    $conflicts | ForEach-Object { Write-Host "  $_" -ForegroundColor 'DarkYellow' }
    Write-Host ''
    Write-Host 'Resolve each conflict in favour of upstream, then re-apply the hook marked with' -ForegroundColor 'DarkYellow'
    Write-Host "'shovel-overlay' (git show HEAD:<file> shows the pre-merge state), commit and run" -ForegroundColor 'DarkYellow'
    Write-Host '.\bin\shovel-verify-overlay.ps1' -ForegroundColor 'DarkYellow'
    exit 1
}

if (!$NoVerify) {
    Write-Host ''
    & (Join-Path $PSScriptRoot 'shovel-verify-overlay.ps1')
    $verifyFailed = $LASTEXITCODE -ne 0

    if ($verifyFailed) {
        Write-Host ''
        Write-Host 'The merge succeeded but the overlay is broken. Re-apply the reported hooks,' -ForegroundColor 'Red'
        Write-Host 'then run .\bin\shovel-verify-overlay.ps1 again.' -ForegroundColor 'Red'
        exit 1
    }
}

#region Record the new upstream base
$mergedCommit = (Invoke-GitCommand @('rev-parse', $target)) -join ''
$inventory.upstream.mergedCommit = $mergedCommit
$inventory.upstream.repository = $UPSTREAM_URL
$inventory.upstream.branch = $Branch
$changelog = Join-Path $repoRoot 'CHANGELOG.md'
if (Test-Path $changelog -PathType 'Leaf') {
    $version = Select-String -Pattern '^## \[(v[\d.]+)\]' -Path $changelog | Select-Object -First 1
    if ($version) { $inventory.upstream.mergedRelease = $version.Matches.Groups[1].Value }
}
# UTF8 without BOM, the repository forbids a BOM
[System.IO.File]::WriteAllLines($inventoryPath, ($inventory | ConvertTo-Json -Depth 10))
#endregion Record the new upstream base

Write-Host ''
Write-Host "Merged $target ($($mergedCommit.Substring(0, 8))). Do not forget to commit '.shovel/overlay.json'." -ForegroundColor 'Green'

exit 0
