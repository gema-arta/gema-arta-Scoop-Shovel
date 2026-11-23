# SPDX-License-Identifier: GPL-3.0-only
# Part of the Shovel compatibility overlay for Scoop.
# Derived from https://github.com/Ash258/Scoop-Core (Shovel, GPL-3.0-only),
# adapted to the current Scoop code base. See docs/SHOVEL-OVERLAY.md.
#
# Helpers callable from manifest scripts (pre_download, pre_install, post_install,
# installer.script, pre_uninstall, post_uninstall, ...).
# Everything in this file is additive: no upstream function is redefined here.

#region Persistence
function Test-Persistence {
    <#
    .SYNOPSIS
        Persistence check helper for files.
    .DESCRIPTION
        This saves some lines, so manifests do not always need to write
        'if (!(Test-Path "$persist_dir\$file")) { New-Item "$dir\$file" | Out-Null }'.
        The variables $currentFile, $currentFilePersist and $currentFileDir are exposed
        and could be used inside the Execution block.
    .PARAMETER File
        Specifies the file to be checked.
        Do not prefix with $dir. All files are already checked against $dir and $persist_dir.
    .PARAMETER Content
        Specifies the content/value of the created file.
        The value should be an array of strings or a string.
    .PARAMETER Execution
        Specifies a custom scriptblock to run when the file is not persisted.
    .PARAMETER Force
        If the file does not exist in $persist_dir, but in $dir, -Force has to be used
        to overwrite the $dir file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('Path', 'LiteralPath', 'Name', 'InputObject')]
        [String[]] $File,
        [Parameter(ValueFromPipelineByPropertyName, Position = 1)]
        [Alias('Value')]
        [Object[]] $Content,
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('ScriptBlock')]
        [ScriptBlock] $Execution,
        [Switch] $Force
    )

    process {
        for ($ind = 0; $ind -lt $File.Count; ++$ind) {
            $currentFile = $File[$ind]
            $currentFileDir = Join-Path $dir $currentFile
            $currentFilePersist = Join-Path $persist_dir $currentFile

            if (!(Test-Path -LiteralPath $currentFilePersist -PathType 'Leaf')) {
                if ($Execution) {
                    if ($Force -or !(Test-Path -LiteralPath $currentFileDir -PathType 'Leaf')) {
                        Write-Verbose -Message "Executing ScriptBlock for '$currentFile' before persisting"
                        & $Execution
                    }
                } else {
                    # Do not overwrite the file in $dir, only if it does not exist or -Force
                    if ($Force -or !(Test-Path -LiteralPath $currentFileDir -PathType 'Leaf')) {
                        # Handle the edge case of one file and multiple contents:
                        # 'Test-Persistence alfa.txt @("new", "beta")' binds Content as a simple
                        # array with 2 values instead of an array with one nested array.
                        if (($File.Count -eq 1) -and ($Content.Count -gt 1)) {
                            $cont = $Content
                        } elseif ($ind -lt $Content.Count) {
                            $cont = $Content[$ind]
                        } else {
                            $cont = $null
                        }

                        Write-Verbose -Message "Pre-creating file '$currentFile' before persisting"
                        # The file needs to be pre-created in case of nested directories
                        New-Item -Path $currentFileDir -ItemType 'File' -Force | Out-Null
                        if ($null -ne $cont) { Out-UTF8File -FilePath $currentFileDir -InputObject $cont }
                    }
                }
            }
        }
    }
}
#endregion Persistence

function Remove-AppDirItem {
    <#
    .SYNOPSIS
        Removes the given item from the application directory ($dir).
    .PARAMETER Item
        Specifies the item which should be removed from $dir.
        Wildcards are supported.
    .PARAMETER Recurse
        Kept for compatibility with manifests. Items are always removed recursively.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [String[]] $Item,
        [Switch] $Recurse
    )

    process {
        # Get-ChildItem is not suitable as it does not support nested folders with -Include
        foreach ($it in $Item) {
            Join-Path $dir $it | Remove-Item -ErrorAction 'SilentlyContinue' -Force -Recurse
        }
    }
}

function Edit-File {
    <#
    .SYNOPSIS
        Finds and replaces text in the given file.
    .PARAMETER File
        Specifies the file which will be loaded.
        The file could be passed as a full path (used for changing files outside $dir)
        or just as a relative path to $dir.
    .PARAMETER Find
        Specifies the string to be replaced.
    .PARAMETER Replace
        Specifies the string for replacing all occurrences.
        An empty string is the default => the found string will be removed.
    .PARAMETER Regex
        Specifies that a regular expression is used instead of a simple match.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [Alias('Path', 'LiteralPath')]
        [String] $File,
        [Parameter(Mandatory, Position = 1)]
        [String[]] $Find,
        [Parameter(Position = 2)]
        [String[]] $Replace,
        [Switch] $Regex
    )

    begin {
        # Use the file from $dir when it exists there
        if ($dir -and (Join-Path $dir $File | Test-Path -PathType 'Leaf')) { $File = Join-Path $dir $File }
    }

    process {
        if (!(Test-Path -LiteralPath $File -PathType 'Leaf')) {
            Write-UserMessage -Message "File '$File' does not exist" -Err
            return
        }

        $content = Get-Content -LiteralPath $File

        for ($i = 0; $i -lt $Find.Count; ++$i) {
            $toFind = $Find[$i]
            if (!$Replace -or ($null -eq $Replace[$i])) {
                $toReplace = ''
            } else {
                $toReplace = $Replace[$i]
            }

            if ($Regex) {
                $content = $content -replace $toFind, $toReplace
            } else {
                $content = $content.Replace($toFind, $toReplace)
            }
        }

        Out-UTF8File -FilePath $File -InputObject $content
    }
}

function New-JavaShortcutWrapper {
    <#
    .SYNOPSIS
        Creates a new shim-like batch file wrapper to spawn jar files
        within the start menu (using a shortcut).
    .PARAMETER FileName
        Specifies the jar executable filename without the .jar extension.
        Do not pass a full path, just the FILENAME!
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('Name', 'InputObject')]
        [String[]] $FileName
    )

    process {
        foreach ($f in $FileName) {
            Out-UTF8File -FilePath (Join-Path $dir "$f.bat") -InputObject "@start javaw.exe -jar `"%~dp0$f.jar`" %*"
        }
    }
}

#region Asserts
function Assert-Administrator {
    <#
    .SYNOPSIS
        Test administrator privileges.
    #>
    if (!(is_admin)) {
        throw [System.InvalidOperationException]::new('Administrator privileges are required')
    }
}

function Assert-WindowsMinimalVersion {
    <#
    .SYNOPSIS
        Test the minimal windows version requirement.
    .PARAMETER Version
        Specifies the minimal required version of Windows.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [String] $Version
    )

    $cmp = Compare-Version -ReferenceVersion ([Environment]::OSVersion.Version.ToString()) -DifferenceVersion $Version
    if ($cmp -eq 1) {
        throw [System.InvalidOperationException]::new("Application requires at least '$Version' Windows version")
    }
}

function Assert-ScoopConfigValue {
    <#
    .SYNOPSIS
        Test a specific value of scoop's configuration.
    .PARAMETER ConfigOption
        Specifies the name of the configuration option.
    .PARAMETER ExpectedValue
        Specifies the expected value of the configuration option.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [String] $ConfigOption,
        [Parameter(Mandatory, Position = 1)]
        $ExpectedValue
    )

    $actualValue = get_config $ConfigOption
    if ($actualValue -ne $ExpectedValue) {
        throw [System.InvalidOperationException]::new("Configuration option '$ConfigOption' needs to be set to '$ExpectedValue'")
    }
}
#endregion Asserts
