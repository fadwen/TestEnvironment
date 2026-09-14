#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Core/Data/SeedPeople.csv is the one place the shared people's names live: the nine people
    written in other writing systems and the nine core people every provider seeds. The four seed
    generators read it, so one identity exists in every lab and a name cannot drift between
    providers, which is what hybrid identity matching across them depends on.

    These pin the file itself - the codepoints an editor could silently normalise away - and then
    read every provider's users file and check that each shared person carries exactly these names
    there. That is the drift guard: a generator that stopped reading the shared file, or a hand edit
    to one provider's CSV, fails here.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
    $script:People = @(Import-Csv -LiteralPath (Join-Path $script:ModuleRoot 'Core\Data\SeedPeople.csv') -Encoding UTF8)
    $script:ByKey = @{}
    foreach ($person in $script:People) { $script:ByKey[$person.Key] = $person }
}

Describe 'The shared people' -Tag 'Unit', 'Contract' {

    It 'has a unique plain-ASCII key and a name for every row' {
        $script:People.Count | Should-BeGreaterThan 0
        @($script:People | Where-Object { $_.Key -notmatch '^[a-z0-9._-]+$' }) | Should-BeCollection -Count 0
        @($script:People.Key | Sort-Object -Unique).Count | Should-Be $script:People.Count
        @($script:People | Where-Object { -not $_.GivenName -or -not $_.Surname -or -not $_.DisplayName -or -not $_.Purpose }) | Should-BeCollection -Count 0
    }

    It 'carries the writing-system cohort' {
        foreach ($key in 'jjiang', 'tyoshida', 'dvolkov', 'gpapadopoulos', 'malahmad', 'jmarchetti', 'iisik', 'jweiss', 'schaudhary') {
            $script:ByKey.ContainsKey($key) | Should-BeTrue
        }
        @($script:People.Script | Sort-Object -Unique) | Should-ContainCollection @('Arabic', 'Cyrillic', 'Devanagari', 'Greek', 'Han', 'Latin')
    }

    It 'keeps the decomposed name decomposed, the ideographic space ideographic, and the astral surname above the basic plane' {
        # Checked on the codepoint, not with -eq: PowerShell compares strings linguistically and
        # calls the decomposed and precomposed forms equal. An editor that normalised this file on
        # save would erase the case without changing a visible character.
        $script:ByKey['jmarchetti'].GivenName.IndexOf([char]0x0301) | Should-BeGreaterThan 0
        $script:ByKey['jnino'].GivenName.IndexOf([char]0x0301) | Should-Be (-1)
        $script:ByKey['jjiang'].DisplayName.IndexOf([char]0x3000) | Should-BeGreaterThan 0
        [char]::IsHighSurrogate($script:ByKey['tyoshida'].Surname[0]) | Should-BeTrue
    }

    It 'is read by every seed generator, and none builds a name of its own for a shared person' {
        foreach ($tool in (Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Providers') -Filter 'New-*TestSeedData.ps1' -Recurse)) {
            $text = Get-Content -LiteralPath $tool.FullName -Raw
            $text | Should-MatchString 'SeedPeople\.csv'
            $text | Should-NotMatchString 'joseDecomposed'
        }
    }
}

Describe 'Every provider seeds the shared people under the shared names' -Tag 'Unit', 'Contract' {

    # The column each provider's users file keeps the name in.
    BeforeDiscovery {
        $script:ProviderFile = @(
            @{ Provider = 'Entra'; File = 'EntraUsers.csv'; Key = 'Key'; Given = 'GivenName'; Surname = 'Surname'; Display = 'DisplayName' }
            @{ Provider = 'Authentik'; File = 'AuthentikUsers.csv'; Key = 'Username'; Given = $null; Surname = $null; Display = 'Name' }
            @{ Provider = 'FreeIPA'; File = 'FreeIPAUsers.csv'; Key = 'Username'; Given = 'GivenName'; Surname = 'Surname'; Display = 'DisplayName' }
            @{ Provider = 'PingOne'; File = 'PingOneUsers.csv'; Key = 'Key'; Given = 'GivenName'; Surname = 'FamilyName'; Display = $null }
        )
    }

    It '<Provider> carries every shared person it seeds with exactly the shared names' -ForEach $script:ProviderFile {
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:ModuleRoot "Providers\$Provider\Data\$File") -Encoding UTF8)
        $seeded = @($rows | Where-Object { $script:ByKey.ContainsKey($_.$Key) })
        # Every provider seeds the nine cohort people and the core people in common.
        $seeded.Count | Should-BeGreaterThanOrEqual 15

        $wrong = foreach ($row in $seeded) {
            $person = $script:ByKey[$row.$Key]
            foreach ($pair in @(@($Given, 'GivenName'), @($Surname, 'Surname'), @($Display, 'DisplayName'))) {
                if (-not $pair[0]) { continue }
                $actual = [string]$row.($pair[0]); $expected = [string]$person.($pair[1])
                if (-not [string]::Equals($actual, $expected, [StringComparison]::Ordinal)) { "$($row.$Key).$($pair[0]) is '$actual', shared says '$expected'" }
            }
        }
        (@($wrong) -join '; ') | Should-Be ''
    }
}
