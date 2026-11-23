BeforeAll {
    . "$PSScriptRoot\..\lib\json.ps1"
    . "$PSScriptRoot\..\lib\core.ps1"
    . "$PSScriptRoot\..\lib\manifest.ps1"
    . "$PSScriptRoot\..\lib\versions.ps1"

    $shovelFixtures = "$PSScriptRoot\fixtures\shovel\bucket"
    $repoRoot = (Get-Item "$PSScriptRoot\..").FullName
}

Describe 'Shovel overlay is loaded' -Tag 'Scoop', 'Shovel' {
    It 'exposes its version' {
        Get-ShovelOverlayVersion | Should -Not -BeNullOrEmpty
    }

    It 'exposes every function recorded in the inventory' {
        $inventory = Get-Content "$repoRoot\.shovel\overlay.json" -Raw -Encoding 'UTF8' | ConvertFrom-Json
        foreach ($function in $inventory.requiredFunctions) {
            Get-Command $function -ErrorAction 'SilentlyContinue' | Should -Not -BeNullOrEmpty -Because "'$function' is part of the overlay"
        }
    }

    It 'does not shadow upstream functions' {
        # Overlay files are additive. Nothing in lib/shovel may redefine an upstream function.
        $upstreamFunctions = @()
        Get-ChildItem "$repoRoot\lib" -Filter '*.ps1' -File | ForEach-Object {
            $upstreamFunctions += ([Regex]::Matches((Get-Content $_.FullName -Raw), '(?m)^function\s+([^\s({]+)')).ForEach({ $_.Groups[1].Value })
        }

        $overlayFunctions = @()
        Get-ChildItem "$repoRoot\lib\shovel" -Filter '*.ps1' -File | ForEach-Object {
            $overlayFunctions += ([Regex]::Matches((Get-Content $_.FullName -Raw), '(?m)^function\s+([^\s({]+)')).ForEach({ $_.Groups[1].Value })
        }

        $shadowed = $overlayFunctions | Where-Object { $upstreamFunctions -contains $_ }
        $shadowed | Should -BeNullOrEmpty
    }
}

Describe 'Shovel overlay hooks are intact' -Tag 'Scoop', 'Shovel' {
    BeforeDiscovery {
        $inventoryPath = "$PSScriptRoot\..\.shovel\overlay.json"
        $inventoryData = Get-Content $inventoryPath -Raw -Encoding 'UTF8' | ConvertFrom-Json
        # Hashtables keep '-ForEach' variable expansion predictable across Pester versions
        $hookedFiles = @($inventoryData.hookedFiles | ForEach-Object { @{ 'file' = $_.file; 'markers' = $_.markers } })
        $overlayFiles = @($inventoryData.overlayFiles)
    }

    It '<file> still carries its hooks' -ForEach $hookedFiles {
        $path = Join-Path (Get-Item "$PSScriptRoot\..").FullName $file
        $path | Should -Exist
        $found = ([Regex]::Matches((Get-Content $path -Raw -Encoding 'UTF8'), 'shovel-overlay')).Count
        $found | Should -BeGreaterOrEqual $markers -Because 'an upstream merge may have dropped a hook, see docs/SHOVEL-OVERLAY.md'
    }

    It '<_> exists' -ForEach $overlayFiles {
        Join-Path (Get-Item "$PSScriptRoot\..").FullName $_ | Should -Exist
    }
}

Describe 'Manifest extensions' -Tag 'Scoop', 'Shovel' {
    It 'recognizes every supported extension' {
        Test-ShovelManifestExtension 'app.json' | Should -BeTrue
        Test-ShovelManifestExtension 'app.yml' | Should -BeTrue
        Test-ShovelManifestExtension 'app.yaml' | Should -BeTrue
        Test-ShovelManifestExtension 'app.txt' | Should -BeFalse
        Test-ShovelManifestExtension '' | Should -BeFalse
    }

    It 'recognizes yaml typed manifests only' {
        Test-ShovelYamlExtension 'app.yml' | Should -BeTrue
        Test-ShovelYamlExtension 'app.yaml' | Should -BeTrue
        Test-ShovelYamlExtension 'app.json' | Should -BeFalse
    }

    It 'trims the extension' {
        Remove-ShovelManifestExtension 'app.yml' | Should -BeExactly 'app'
        Remove-ShovelManifestExtension 'app.yaml' | Should -BeExactly 'app'
        Remove-ShovelManifestExtension 'app.json' | Should -BeExactly 'app'
        Remove-ShovelManifestExtension 'app.exe' | Should -BeExactly 'app.exe'
    }

    It 'strips the extension of an url (appname_from_url)' {
        appname_from_url 'https://example.com/bucket/app.yml' | Should -BeExactly 'app'
        appname_from_url 'https://example.com/bucket/app.json' | Should -BeExactly 'app'
    }

    It 'parses an app reference with a yaml extension (parse_app)' {
        $app, $bucket, $version = parse_app 'ash258/app.yml@1.2.3'
        $app | Should -BeExactly 'app.yml'
        $bucket | Should -BeExactly 'ash258'
        $version | Should -BeExactly '1.2.3'
    }
}

Describe 'Manifest lookup' -Tag 'Scoop', 'Shovel' {
    It 'finds manifests of every extension' {
        $names = (Get-ShovelManifestItem -Path $shovelFixtures).BaseName | Sort-Object -Unique
        $names | Should -Contain 'alfa'
        $names | Should -Contain 'beta'
        $names | Should -Contain 'cosi'
        $names | Should -Contain 'pwsh'
    }

    It 'supports wildcards' {
        $names = (Get-ShovelManifestItem -Path $shovelFixtures -Name 'p*').BaseName | Sort-Object -Unique
        $names | Should -Be 'pwsh'
    }

    It 'ignores files which are not manifests' {
        (Get-ShovelManifestItem -Path $shovelFixtures -Name 'nonexistent') | Should -BeNullOrEmpty
    }

    It 'prefers json when a name is available twice' {
        Find-ShovelManifestPath -Directory $shovelFixtures -Name 'beta' | Should -BeLike '*beta.json'
    }

    It 'returns null for an unknown manifest' {
        Find-ShovelManifestPath -Directory $shovelFixtures -Name 'nonexistent' | Should -BeNullOrEmpty
    }
}

Describe 'YAML typed manifests' -Tag 'Scoop', 'Shovel' {
    It 'parses a yaml manifest' {
        $manifest = ConvertFrom-Manifest -Path "$shovelFixtures\pwsh.yml"
        $manifest | Should -Not -BeNullOrEmpty
        $manifest.version | Should -BeExactly '7.2.1'
        $manifest.bin | Should -Be 'pwsh.exe'
        $manifest.checkver.github | Should -BeExactly 'https://github.com/PowerShell/PowerShell'
    }

    It 'parses the .yaml extension too' {
        (ConvertFrom-Manifest -Path "$shovelFixtures\cosi.yaml").version | Should -BeExactly '1.0.0'
    }

    It 'produces the same object as the json twin' {
        $fromYaml = ConvertFrom-Manifest -Path "$shovelFixtures\pwsh.yml" | ConvertToPrettyJson
        $fromJson = ConvertFrom-Manifest -Path "$shovelFixtures\pwsh.json" | ConvertToPrettyJson
        $fromYaml | Should -BeExactly $fromJson
    }

    It 'is used by parse_json' {
        (parse_json "$shovelFixtures\pwsh.yml").version | Should -BeExactly '7.2.1'
        (parse_json "$shovelFixtures\pwsh.json").version | Should -BeExactly '7.2.1'
    }

    It 'returns null and warns for a broken yaml manifest' {
        Mock warn {}
        { ConvertFrom-Manifest -Path "$shovelFixtures\broken.yml" } | Should -Not -Throw
        ConvertFrom-Manifest -Path "$shovelFixtures\broken.yml" | Should -BeNullOrEmpty
        Should -Invoke -CommandName warn -Times 1
    }

    It 'returns null for a missing file' {
        ConvertFrom-Manifest -Path "$shovelFixtures\nonexistent.yml" | Should -BeNullOrEmpty
    }

    It 'converts any manifest to json text' {
        $text = Get-ShovelManifestJsonText -Path "$shovelFixtures\pwsh.yml"
        { $text | ConvertFrom-Json -ErrorAction 'Stop' } | Should -Not -Throw
        ($text | ConvertFrom-Json).version | Should -BeExactly '7.2.1'
    }

    It 'keeps json manifests byte identical in json text' {
        Get-ShovelManifestJsonText -Path "$shovelFixtures\pwsh.json" | Should -BeExactly ([System.IO.File]::ReadAllText("$shovelFixtures\pwsh.json"))
    }
}

Describe 'Writing manifests' -Tag 'Scoop', 'Shovel' {
    BeforeAll {
        $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "shovel-overlay-$([System.Guid]::NewGuid().ToString('N'))"
        New-Item -Path $workDir -ItemType 'Directory' -Force | Out-Null
    }

    AfterAll {
        Remove-Item $workDir -Recurse -Force -ErrorAction 'SilentlyContinue'
    }

    It 'round trips a yaml manifest' {
        $source = ConvertFrom-Manifest -Path "$shovelFixtures\pwsh.yml"
        $target = Join-Path $workDir 'pwsh.yml'
        ConvertTo-Manifest -File $target -Manifest $source
        $target | Should -Exist
        $reparsed = ConvertFrom-Manifest -Path $target
        $reparsed.version | Should -BeExactly $source.version
        $reparsed.bin | Should -Be $source.bin
        $reparsed.autoupdate.url | Should -BeExactly $source.autoupdate.url
    }

    It 'writes json when the target is json' {
        $target = Join-Path $workDir 'pwsh.json'
        ConvertTo-Manifest -File $target -Manifest (ConvertFrom-Manifest -Path "$shovelFixtures\pwsh.yml")
        (Get-Content $target -Raw) | Should -BeLike '*"version":*'
    }

    It 'converts a yaml manifest into the installed json manifest' {
        $target = Join-Path $workDir 'scoop-manifest.json'
        Copy-ShovelManifest -Path "$shovelFixtures\pwsh.yml" -Destination $target
        $target | Should -Exist
        (Get-Content $target -Raw | ConvertFrom-Json).version | Should -BeExactly '7.2.1'
    }

    It 'copies a json manifest untouched' {
        $target = Join-Path $workDir 'scoop-manifest-json.json'
        Copy-ShovelManifest -Path "$shovelFixtures\pwsh.json" -Destination $target
        (Get-Content $target -Raw) | Should -BeExactly ([System.IO.File]::ReadAllText("$shovelFixtures\pwsh.json"))
    }
}

Describe 'Manifest helpers' -Tag 'Scoop', 'Shovel' {
    BeforeAll {
        $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "shovel-helpers-$([System.Guid]::NewGuid().ToString('N'))"
    }

    BeforeEach {
        $dir = Join-Path $workDir 'app'
        $persist_dir = Join-Path $workDir 'persist'
        New-Item -Path $dir -ItemType 'Directory' -Force | Out-Null
        New-Item -Path $persist_dir -ItemType 'Directory' -Force | Out-Null
    }

    AfterEach {
        Remove-Item $workDir -Recurse -Force -ErrorAction 'SilentlyContinue'
    }

    It 'pre-creates a file with content (Test-Persistence)' {
        Test-Persistence 'config.ini' '[Settings]', 'Update=0'
        "$dir\config.ini" | Should -Exist
        (Get-Content "$dir\config.ini") -join '|' | Should -BeExactly '[Settings]|Update=0'
    }

    It 'pre-creates nested files (Test-Persistence)' {
        Test-Persistence 'nested\deep\config.ini'
        "$dir\nested\deep\config.ini" | Should -Exist
    }

    It 'does not overwrite an existing file (Test-Persistence)' {
        Out-UTF8File -FilePath "$dir\config.ini" -InputObject 'original'
        Test-Persistence 'config.ini' 'replaced'
        (Get-Content "$dir\config.ini") -join '' | Should -BeExactly 'original'
    }

    It 'skips already persisted files (Test-Persistence)' {
        Out-UTF8File -FilePath "$persist_dir\config.ini" -InputObject 'persisted'
        Test-Persistence 'config.ini' 'created'
        "$dir\config.ini" | Should -Not -Exist
    }

    It 'runs the script block when not persisted (Test-Persistence)' {
        Test-Persistence 'config.ini' -ScriptBlock { Out-UTF8File -FilePath $currentFileDir -InputObject 'from block' }
        (Get-Content "$dir\config.ini") -join '' | Should -BeExactly 'from block'
    }

    It 'replaces text in a file (Edit-File)' {
        Out-UTF8File -FilePath "$dir\file.txt" -InputObject 'alfa beta gamma'
        Edit-File 'file.txt' -Find 'beta' -Replace 'delta'
        (Get-Content "$dir\file.txt") -join '' | Should -BeExactly 'alfa delta gamma'
    }

    It 'replaces with a regular expression (Edit-File)' {
        Out-UTF8File -FilePath "$dir\file.txt" -InputObject 'version 1.2.3'
        Edit-File 'file.txt' -Find 'version [\d.]+' -Replace 'version 2.0.0' -Regex
        (Get-Content "$dir\file.txt") -join '' | Should -BeExactly 'version 2.0.0'
    }

    It 'removes items from the app directory (Remove-AppDirItem)' {
        New-Item -Path "$dir\uninstall.exe" -ItemType 'File' -Force | Out-Null
        New-Item -Path "$dir\keep.exe" -ItemType 'File' -Force | Out-Null
        Remove-AppDirItem 'uninst*'
        "$dir\uninstall.exe" | Should -Not -Exist
        "$dir\keep.exe" | Should -Exist
    }

    It 'creates a java wrapper (New-JavaShortcutWrapper)' {
        New-JavaShortcutWrapper 'app'
        "$dir\app.bat" | Should -Exist
        (Get-Content "$dir\app.bat") -join '' | Should -BeLike '*app.jar*'
    }

    It 'makes sure a directory exists (Confirm-DirectoryExistence)' {
        $target = Join-Path $workDir 'created'
        Confirm-DirectoryExistence -Directory $target | Out-Null
        $target | Should -Exist
    }

    It 'throws when a configuration value does not match (Assert-ScoopConfigValue)' {
        { Assert-ScoopConfigValue -ConfigOption 'shovel_overlay_nonexistent' -ExpectedValue 'expected' } | Should -Throw
    }

    It 'accepts a positional content argument (Out-UTF8File)' {
        # Shovel manifests call 'Out-UTF8File <path> <content>'
        Out-UTF8File "$dir\positional.txt" 'content'
        (Get-Content "$dir\positional.txt") -join '' | Should -BeExactly 'content'
    }
}
