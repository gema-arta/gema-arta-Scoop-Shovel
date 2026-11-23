# SPDX-License-Identifier: GPL-3.0-only
# Part of the Shovel compatibility overlay for Scoop.
# Derived from https://github.com/Ash258/Scoop-Core (Shovel, GPL-3.0-only),
# adapted to the current Scoop code base. See docs/SHOVEL-OVERLAY.md.
#
# Manifest script properties which upstream Scoop does not know about.
# Everything in this file is additive: no upstream function is redefined here.

function Invoke-ShovelHookScript {
    <#
    .SYNOPSIS
        Execute a manifest script property which is not handled by upstream Invoke-HookScript.
    .DESCRIPTION
        Used for the Shovel specific 'pre_download' property. Contrary to upstream hooks,
        a terminating error inside the script is reported as a plain message, because
        'pre_download' is mostly used for early bail outs
        (Assert-Administrator, "throw 'Deprecated'", ...).
    .PARAMETER HookType
        Specifies the manifest property holding the script.
    .PARAMETER Manifest
        Specifies the manifest object.
    .PARAMETER ProcessorArchitecture
        Specifies the architecture of the installation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('pre_download')]
        [String] $HookType,
        [Parameter(Mandatory)]
        [AllowNull()]
        [PSCustomObject] $Manifest,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [Alias('Arch', 'Architecture')]
        [String] $ProcessorArchitecture
    )

    if ($null -eq $Manifest) { return }

    $script = arch_specific $HookType $Manifest $ProcessorArchitecture
    if (!$script) { return }

    Write-Host "Running $($HookType -replace '_', '-') script... " -NoNewline
    try {
        Invoke-Command ([scriptblock]::Create($script -join "`r`n"))
        Write-Host 'Done.' -ForegroundColor 'Green'
    } catch {
        Write-Host ''
        abort "Aborted by the '$HookType' script: $($_.Exception.Message)"
    }
}
