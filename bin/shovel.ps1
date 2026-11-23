#Requires -Version 5
# 'shovel' is an alias of 'scoop'. It exists so that manifests, documentation and
# habits from the Shovel fork (https://github.com/Ash258/Scoop-Core) keep working.
Set-StrictMode -Off

& "$PSScriptRoot\scoop.ps1" @args

if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
