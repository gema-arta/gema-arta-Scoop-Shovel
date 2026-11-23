# SPDX-License-Identifier: GPL-3.0-only
# Part of the Shovel compatibility overlay for Scoop.
# Derived from https://github.com/Ash258/Scoop-Core (Shovel, GPL-3.0-only),
# adapted to the current Scoop code base. See docs/SHOVEL-OVERLAY.md.
#
# General purpose helpers used by the overlay and by Shovel manifests.
# Everything in this file is additive: no upstream function is redefined here.

function Write-UserMessage {
    <#
    .SYNOPSIS
        Print message to the user using Write-Host.
    .DESCRIPTION
        Based on the passed severity the message will have a different color and prefix.
    .PARAMETER Message
        Specifies the message to be displayed to the user.
    .PARAMETER Severity
        Specifies the severity of the message.
        Could be Message, Info, Warning, Error, Success
    .PARAMETER Output
        Specifies that the Write-Output cmdlet is used instead of Write-Host.
    .PARAMETER Info
        Same as -Severity Info
    .PARAMETER Warning
        Same as -Severity Warning
    .PARAMETER Err
        Same as -Severity Error
    .PARAMETER Success
        Same as -Severity Success
    .PARAMETER SkipSeverity
        Specifies that the output will not contain the severity prefix.
    .PARAMETER Color
        Specifies the foreground color of the message.
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromRemainingArguments, Position = 0)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [String[]] $Message,
        [ValidateSet('Message', 'Info', 'Warning', 'Error', 'Success')]
        [String] $Severity = 'Message',
        [Switch] $Output,
        [Switch] $Info,
        [Switch] $Warning,
        [Switch] $Err,
        [Switch] $Success,
        [Switch] $SkipSeverity,
        [Alias('ForegroundColor')]
        [System.ConsoleColor] $Color = $(if ($Host.UI.RawUI.ForegroundColor -and !$IsLinux) { $Host.UI.RawUI.ForegroundColor } else { 'White' })
    )

    begin {
        if ($Info) { $Severity = 'Info' }
        if ($Warning) { $Severity = 'Warning' }
        if ($Err) { $Severity = 'Error' }
        if ($Success) { $Severity = 'Success' }

        switch ($Severity) {
            'Info' { $sev = 'INFO  '; $foreColor = 'DarkGray' }
            'Warning' { $sev = 'WARN  '; $foreColor = 'DarkYellow' }
            'Error' { $sev = 'ERROR '; $foreColor = 'DarkRed' }
            'Success' { $sev = ''; $foreColor = 'DarkGreen' }
            default {
                $sev = ''
                $foreColor = 'White'
                # If the color is white (default) and there is no output => Write-Host
                # If a color other than White is passed => Write-Host
                if ((($Color -eq 'White') -and !$Output) -or ($Color -ne 'White')) {
                    $foreColor = $Color
                } else {
                    $Output = $true
                }
            }
        }
        $display = @()
    }

    process {
        $m = if ($SkipSeverity) { $Message } else { $Message -replace '^', "$sev" }
        $display += $m
    }

    end {
        $display = $display -join "`r`n"
        if ($Output) {
            Write-Output $display
        } else {
            Write-Host $display -ForegroundColor $foreColor
        }
    }
}

function Confirm-DirectoryExistence {
    <#
    .SYNOPSIS
        Make sure that the directory exists. 'ensure' replacement.
    .PARAMETER Directory
        Specifies the directory to be tested and created.
    .OUTPUTS
        System.Management.Automation.PathInfo
            Resolved path
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PathInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('Dir', 'Path', 'LiteralPath', 'InputObject')]
        [String] $Directory
    )

    process {
        if (!(Test-Path -LiteralPath $Directory -PathType 'Container')) {
            New-Item -Path $Directory -ItemType 'Directory' -Force | Out-Null
        }

        return Resolve-Path -LiteralPath $Directory
    }
}

function Out-UTF8Content {
    <#
    .SYNOPSIS
        Write an UTF8 (no BOM) file. Takes the file from the pipeline instead of the content.
    .PARAMETER File
        Specifies the file name to be written.
    .PARAMETER Content
        Specifies the content to be written into the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('Path', 'LiteralPath', 'FullName')]
        [String] $File,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position = 1)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [Alias('Value', 'InputObject')]
        $Content
    )

    process { Out-UTF8File -FilePath $File -InputObject $Content }
}

function Stop-ScoopExecution {
    <#
    .SYNOPSIS
        Print an error message and exit the scoop execution with the given exit code.
    .PARAMETER Message
        Specifies the message, which will be printed to the user.
    .PARAMETER ExitCode
        Specifies the exit code.
    .PARAMETER Usage
        Specifies the usage text printed below the message. Forces exit code 1.
    .PARAMETER SkipSeverity
        Specifies that the message is printed without the severity prefix.
    #>
    param(
        [Parameter(Position = 0, Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [String[]] $Message,
        [Parameter(Position = 1, ValueFromPipelineByPropertyName)]
        [Int] $ExitCode = 3,
        [String[]] $Usage,
        [Switch] $SkipSeverity
    )

    begin { if ($Usage) { $ExitCode = 1 } }

    process {
        Write-UserMessage -Message $Message -Err:(!$SkipSeverity)
        if ($Usage) { Write-UserMessage -Message $Usage -Output }
    }

    end { exit $ExitCode }
}

function Invoke-ScoopCommand {
    <#
    .SYNOPSIS
        Execute a scoop command inside the current session instead of spawning a new shell.
    .PARAMETER Command
        Specifies the scoop command to be executed, e.g. 'which'.
    .PARAMETER Arguments
        Specifies the arguments passed to the command.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Cmd')]
        [String] $Command,
        [Parameter(Position = 1, ValueFromRemainingArguments)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [Alias('Args')]
        $Arguments
    )

    if (!(Get-Command 'command_path' -ErrorAction 'SilentlyContinue')) {
        . (Join-Path $PSScriptRoot '..\commands.ps1')
    }

    $commandPath = command_path $Command

    if ($null -eq $Arguments) { $Arguments = @() }

    & $commandPath @Arguments
}
