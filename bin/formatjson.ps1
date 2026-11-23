<#
.SYNOPSIS
    Format manifest.
.PARAMETER App
    Manifest to format.

    Wildcards are supported.
.PARAMETER Dir
    Where to search for manifest(s).
.EXAMPLE
    PS BUCKETROOT> .\bin\formatjson.ps1
    Format all manifests inside bucket directory.
.EXAMPLE
    PS BUCKETROOT> .\bin\formatjson.ps1 7zip
    Format manifest '7zip' inside bucket directory.
#>
param(
    [String] $App = '*',
    [Parameter(Mandatory = $true)]
    [ValidateScript( {
        if (!(Test-Path $_ -Type Container)) {
            throw "$_ is not a directory!"
        } else {
            $true
        }
    })]
    [String] $Dir
)

. "$PSScriptRoot\..\lib\core.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1"
. "$PSScriptRoot\..\lib\json.ps1"

$Dir = Convert-Path $Dir

Get-ShovelManifestItem -Path $Dir -Name $App | ForEach-Object { # shovel-overlay: manifest-extensions
    $file = $_.FullName
    # beautify; yaml typed manifests are rewritten as yaml
    # shovel-overlay: yaml-manifests
    $manifest = ConvertFrom-Manifest -Path $file
    if ($null -eq $manifest) { return }
    ConvertTo-Manifest -File $file -Manifest $manifest
}
