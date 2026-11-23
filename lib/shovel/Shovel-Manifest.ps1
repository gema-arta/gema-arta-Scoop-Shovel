# SPDX-License-Identifier: GPL-3.0-only
# Part of the Shovel compatibility overlay for Scoop.
# Derived from https://github.com/Ash258/Scoop-Core (Shovel, GPL-3.0-only),
# adapted to the current Scoop code base. See docs/SHOVEL-OVERLAY.md.
#
# Manifest handling which is not limited to the '.json' extension.
# Everything in this file is additive: no upstream function is redefined here.

# Manifest extensions understood by this installation, in order of preference.
$SHOVEL_MANIFEST_EXTENSIONS = @('json', 'yaml', 'yml')
$SHOVEL_MANIFEST_EXTENSION_REGEX = $SHOVEL_MANIFEST_EXTENSIONS -join '|'
$SHOVEL_YAML_EXTENSION_REGEX = 'yaml|yml'

function Get-ShovelOverlayVersion {
    <#
    .SYNOPSIS
        Version of the Shovel compatibility overlay.
    .DESCRIPTION
        Presence of this function is used as the "overlay is loaded" marker.
    #>
    return '1.0.0'
}

function Test-ShovelManifestExtension {
    <#
    .SYNOPSIS
        Test whether the given path/name ends with a supported manifest extension.
    .PARAMETER Path
        Specifies the path or file name to be tested.
    #>
    param([String] $Path)

    if ([String]::IsNullOrEmpty($Path)) { return $false }

    return $Path -match "\.($SHOVEL_MANIFEST_EXTENSION_REGEX)$"
}

function Test-ShovelYamlExtension {
    <#
    .SYNOPSIS
        Test whether the given path/name is a YAML typed manifest.
    .PARAMETER Path
        Specifies the path or file name to be tested.
    #>
    param([String] $Path)

    if ([String]::IsNullOrEmpty($Path)) { return $false }

    return $Path -match "\.($SHOVEL_YAML_EXTENSION_REGEX)$"
}

function Remove-ShovelManifestExtension {
    <#
    .SYNOPSIS
        Remove supported manifest extension from the given name.
    .PARAMETER Name
        Specifies the name to be trimmed.
    #>
    param([String] $Name)

    if ([String]::IsNullOrEmpty($Name)) { return $Name }

    return $Name -replace "\.($SHOVEL_MANIFEST_EXTENSION_REGEX)$", ''
}

function Get-ShovelManifestItem {
    <#
    .SYNOPSIS
        Multi-extension replacement of "Get-ChildItem <dir> -Filter '<name>.json' -Recurse".
    .PARAMETER Path
        Specifies the directories to be searched.
    .PARAMETER Name
        Specifies the manifest name without extension. Wildcards are supported.
    .OUTPUTS
        System.IO.FileInfo[]
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [String[]] $Path,
        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Name
    )

    begin {
        if ([String]::IsNullOrEmpty($Name)) { $Name = '*' }
        # Translate the wildcard pattern into regex to stay independent of provider globbing
        $namePattern = [Regex]::Escape($Name).Replace('\*', '.*').Replace('\?', '.')
        $pattern = "^$namePattern\.($SHOVEL_MANIFEST_EXTENSION_REGEX)$"
        $result = @()
    }

    process {
        foreach ($directory in $Path) {
            if ([String]::IsNullOrEmpty($directory)) { continue }
            if (!(Test-Path -LiteralPath $directory)) { continue }

            # No -Force: hidden directories such as '.git' are skipped, as with the
            # upstream 'Get-ChildItem <dir> -Filter *.json -Recurse' calls
            $result += Get-ChildItem -LiteralPath $directory -Recurse -File -ErrorAction 'SilentlyContinue' |
                Where-Object -Property 'Name' -Match -Value $pattern
        }
    }

    end {
        return $result
    }
}

function Find-ShovelManifestPath {
    <#
    .SYNOPSIS
        Resolve full path of a single manifest regardless of its extension.
    .DESCRIPTION
        When multiple extensions provide the same manifest name, the order of
        $SHOVEL_MANIFEST_EXTENSIONS decides, i.e. json wins over yaml/yml.
    .PARAMETER Directory
        Specifies the directories to be searched.
    .PARAMETER Name
        Specifies the manifest name without extension.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [Alias('Path')]
        [String[]] $Directory,
        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Name
    )

    $items = @(Get-ShovelManifestItem -Path $Directory -Name $Name)
    if ($items.Count -eq 0) { return $null }
    if ($items.Count -eq 1) { return $items[0].FullName }

    $sorted = $items | Sort-Object -Property @{
        Expression = { [Array]::IndexOf($SHOVEL_MANIFEST_EXTENSIONS, $_.Extension.TrimStart('.').ToLowerInvariant()) }
    }, 'FullName'

    return $sorted[0].FullName
}

function Import-ShovelYamlModule {
    <#
    .SYNOPSIS
        Import the vendored powershell-yaml module.
    .DESCRIPTION
        The module is imported with the 'Shovel' prefix, hence it never collides
        with a powershell-yaml installation of the user:
        ConvertFrom-ShovelYaml / ConvertTo-ShovelYaml.
    #>
    if (Get-Module -Name 'powershell-yaml' -ErrorAction 'SilentlyContinue') { return }

    $modulePath = Join-Path $PSScriptRoot '..\..\supporting\yaml\bin\powershell-yaml.psd1'
    if (!(Test-Path -LiteralPath $modulePath -PathType 'Leaf')) {
        error "Shovel overlay: vendored YAML module not found at '$modulePath'."
        return
    }

    Import-Module -Name $modulePath -Prefix 'Shovel' -Global -Verbose:$false -ErrorAction 'Stop'
}

function ConvertFrom-ShovelManifestString {
    <#
    .SYNOPSIS
        Parse manifest content into object.
    .PARAMETER Content
        Specifies the raw manifest content.
    .PARAMETER Extension
        Specifies the manifest extension deciding the used parser. Leading dot is optional.
    .PARAMETER Source
        Specifies the origin of the content. Used in error messages only.
    .PARAMETER Quiet
        Specifies that parsing errors are not reported to the user.
        Used when a parse failure is an expected outcome, e.g. while probing git history.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Content,
        [Parameter(Position = 1)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Extension,
        [Parameter(Position = 2)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Source,
        [Switch] $Quiet
    )

    if ([String]::IsNullOrWhiteSpace($Content)) { return $null }
    if ([String]::IsNullOrEmpty($Source)) { $Source = '<content>' }

    $ext = if ($Extension) { $Extension.TrimStart('.').ToLowerInvariant() } else { 'json' }

    try {
        if ($ext -match "^($SHOVEL_YAML_EXTENSION_REGEX)$") {
            Import-ShovelYamlModule
            # powershell-yaml emits ordered dictionaries. The JSON round trip keeps
            # the property order and produces the PSCustomObject shape Scoop expects.
            return ConvertFrom-ShovelYaml -Yaml $Content -Ordered | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        }

        return ConvertFrom-Json -InputObject $Content -ErrorAction 'Stop'
    } catch {
        if (!$Quiet) {
            warn "Error parsing manifest at '$Source'."
            debug $_.Exception.Message
        }
    }
}

function Get-ShovelManifestJsonText {
    <#
    .SYNOPSIS
        Get the json representation of any supported manifest as text.
    .DESCRIPTION
        Consumers which rely on json text (the sqlite cache, 'scoop search', ...)
        keep working with YAML typed manifests through this function.
        For json manifests the raw file content is returned unchanged.
    .PARAMETER Path
        Specifies the manifest file.
    #>
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [Alias('LiteralPath', 'FullName')]
        [String] $Path
    )

    process {
        if (!(Test-ShovelYamlExtension $Path)) { return [System.IO.File]::ReadAllText($Path) }

        $manifest = ConvertFrom-Manifest -Path $Path
        if ($null -eq $manifest) { return '' }

        if (Get-Command 'ConvertToPrettyJson' -ErrorAction 'SilentlyContinue') {
            return $manifest | ConvertToPrettyJson
        }

        return $manifest | ConvertTo-Json -Depth 100
    }
}

function ConvertFrom-Manifest {
    <#
    .SYNOPSIS
        Parse manifest file into object. Shovel compatible entry point.
    .PARAMETER Path
        Specifies the path to the file representing the manifest.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [Alias('LiteralPath', 'File', 'FullName')]
        [String] $Path
    )

    process {
        if ([String]::IsNullOrEmpty($Path)) { return $null }
        if (!(Test-Path -LiteralPath $Path -PathType 'Leaf')) { return $null }

        $content = Get-Content -LiteralPath $Path -Raw -Encoding 'UTF8'

        return ConvertFrom-ShovelManifestString -Content $content -Extension ([System.IO.Path]::GetExtension($Path)) -Source $Path
    }
}

function ConvertTo-Manifest {
    <#
    .SYNOPSIS
        Convert manifest object into string or save it into file. Shovel compatible entry point.
    .PARAMETER File
        Specifies the path of the file where the manifest will be saved.
    .PARAMETER Manifest
        Specifies the manifest object.
    .PARAMETER Extension
        Specifies the structure of the resulting string (json, yaml, yml).
        Ignored when File is provided.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [AllowEmptyString()]
        [AllowNull()]
        [Alias('Path', 'LiteralPath')]
        [String] $File,
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 1)]
        [Alias('InputObject', 'Content')]
        $Manifest,
        [Parameter(ValueFromPipelineByPropertyName)]
        [String] $Extension
    )

    process {
        $ext = if ($File) { [System.IO.Path]::GetExtension($File) } else { $Extension }
        if ($ext) { $ext = $ext.TrimStart('.').ToLowerInvariant() } else { $ext = 'json' }

        if ($ext -match "^($SHOVEL_YAML_EXTENSION_REGEX)$") {
            Import-ShovelYamlModule
            $content = ConvertTo-ShovelYaml -Data $Manifest
            # powershell-yaml appends an extra line ending
            $content = $content.TrimEnd("`r`n")
        } else {
            $content = $Manifest | ConvertToPrettyJson
            $content = $content -replace "`t", (' ' * 4)
        }

        if ($File) {
            Out-UTF8File -FilePath $File -InputObject $content
        } else {
            return $content
        }
    }
}

function Copy-ShovelManifest {
    <#
    .SYNOPSIS
        Save a bucket manifest as the installed manifest of an application.
    .DESCRIPTION
        YAML typed manifests are converted to json, so that every consumer of
        'scoop-manifest.json' keeps working without being YAML aware.
    .PARAMETER Path
        Specifies the source manifest.
    .PARAMETER Destination
        Specifies the destination file (always json).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Path,
        [Parameter(Mandatory, Position = 1)]
        [String] $Destination
    )

    if ([String]::IsNullOrEmpty($Path) -or !(Test-Path -LiteralPath $Path -PathType 'Leaf')) {
        warn "Shovel overlay: manifest '$Path' cannot be saved into '$Destination'."
        return
    }

    if (Test-ShovelYamlExtension $Path) {
        ConvertTo-Manifest -File $Destination -Manifest (ConvertFrom-Manifest -Path $Path)
    } else {
        Copy-Item -LiteralPath $Path -Destination $Destination -Force
    }
}

function Save-ShovelManifestContent {
    <#
    .SYNOPSIS
        Save downloaded/remote manifest content as the installed manifest (always json).
    .PARAMETER Content
        Specifies the raw manifest content.
    .PARAMETER Source
        Specifies the url/path the content originates from. Decides the used parser.
    .PARAMETER Destination
        Specifies the destination file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Content,
        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()]
        [AllowNull()]
        [String] $Source,
        [Parameter(Mandatory, Position = 2)]
        [String] $Destination
    )

    if (Test-ShovelYamlExtension $Source) {
        $manifest = ConvertFrom-ShovelManifestString -Content $Content -Extension 'yml' -Source $Source
        ConvertTo-Manifest -File $Destination -Manifest $manifest
    } else {
        Out-UTF8File -FilePath $Destination -InputObject $Content
    }
}
