# Usage: scoop utils <utility> [<pattern>] [options] [--additional-options <opts>...]
# Summary: Wrapper around the bucket and manifest maintenance utilities.
# Help: Bucket maintainers do not need their own 'bin' folder, they can use this command instead.
#
# The <pattern> is resolved in two ways:
#     1. A path to an existing manifest file is used as is.
#     2. Anything else is treated as a name pattern (wildcards are supported) which is
#        searched in './bucket', or in the directory given by --bucketdir.
#
# Available utilities:
#   auto-pr, checkhashes, checkurls, checkver, describe, format, missing-checkver
#
# Options:
#   -b, --bucketdir <path>  Use the specified bucket directory instead of './bucket'
#   --additional-options    Everything after this flag is passed to the utility itself.
#                           Refer to the utility for all available parameters.
#
# Example usage:
#   'scoop utils checkver $env:SCOOP\buckets\main\bucket\pwsh.json'
#   'scoop utils checkver manifest*'
#   'scoop utils checkhashes manifest* --bucketdir ..\..\testbucket\bucket'
#   'scoop utils auto-pr --additional-options -Upstream "user/repo:branch" -Push'

. "$PSScriptRoot\..\lib\getopt.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1" # 'parse_json' (indirectly)
. "$PSScriptRoot\..\lib\json.ps1" # 'ConvertToPrettyJson' (indirectly)

$VALID_UTILITIES = @{
    'auto-pr'          = 'auto-pr'
    'checkhashes'      = 'checkhashes'
    'checkurls'        = 'checkurls'
    'checkver'         = 'checkver'
    'describe'         = 'describe'
    'format'           = 'formatjson'
    'formatjson'       = 'formatjson'
    'missing-checkver' = 'missing-checkver'
}

# Everything after '--additional-options' belongs to the utility, not to this wrapper
$wrapperArgs = $args
$additionalArgs = @()
if ($args -contains '--additional-options') {
    $index = [Array]::IndexOf([Array]$args, '--additional-options')
    $wrapperArgs = if ($index -gt 0) { $args[0..($index - 1)] } else { @() }
    if ($index -lt ($args.Count - 1)) { $additionalArgs = $args[($index + 1)..($args.Count - 1)] }
}

$opt, $rem, $err = getopt $wrapperArgs 'b:' 'bucketdir='
if ($err) { error "scoop utils: $err"; exit 2 }

$utility = $rem[0]
$target = $rem[1]

if (!$utility) {
    error 'scoop utils: <utility> missing'
    my_usage
    exit 1
}

if ($VALID_UTILITIES.Keys -notcontains $utility) {
    error "scoop utils: '$utility' is not a known utility"
    my_usage
    exit 1
}

$utilityPath = "$PSScriptRoot\..\bin\$($VALID_UTILITIES[$utility]).ps1"
if (!(Test-Path $utilityPath -PathType 'Leaf')) {
    error "scoop utils: utility '$utility' is not available in this installation"
    exit 3
}

$bucketDirectory = $opt.b, $opt.bucketdir, (Join-Path $PWD 'bucket') | Where-Object { $_ } | Select-Object -First 1

if ($target -and (Test-Path $target -PathType 'Leaf')) {
    # An explicitly passed manifest file wins over any bucket directory
    $manifestItem = Get-Item -LiteralPath $target
    $application = $manifestItem.BaseName
    $bucketDirectory = $manifestItem.Directory.FullName
} else {
    $application = if ($target) { $target } else { '*' }
}

if (!(Test-Path $bucketDirectory -PathType 'Container')) {
    error "scoop utils: '$bucketDirectory' is not a directory. Use --bucketdir to specify the bucket folder."
    exit 3
}

Write-Host "Running '$utility' on " -NoNewline
Write-Host $application -ForegroundColor 'Cyan' -NoNewline
Write-Host ' in ' -NoNewline
Write-Host (friendly_path $bucketDirectory) -ForegroundColor 'Cyan'

& $utilityPath -App $application -Dir $bucketDirectory @additionalArgs

if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
