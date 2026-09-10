#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Contract tests for the Active Directory provider's seed data.

    These are here rather than with the seeding tests because a shifted CSV column is a data
    defect, not a logic one, and it is silent: Import-Csv reports nothing at all when a row is
    short, and the missing value falls through to whatever the code treats as absent.

    The module went a long time without them. Its own contract suite checked the manifest, the
    exports and the file layout, but never opened a single one of the 1,099 rows that actually
    get written into a directory - so a SamAccountName over the twenty-character limit, or a
    manager naming somebody who does not exist, would have failed against a live domain rather
    than here.

    No domain is needed. Every assertion reads a CSV off disk.
#>

BeforeDiscovery {
    $script:SeedFile = @(
        @{ Name = 'ADUsers'; Key = 'SamAccountName'; Required = @('SamAccountName', 'Name', 'GivenName', 'Surname', 'Department', 'Enabled', 'UserPrincipalName') }
        @{ Name = 'ADServiceAccounts'; Key = 'SamAccountName'; Required = @('SamAccountName', 'Name', 'Department', 'Enabled', 'ServiceType', 'ServicePurpose') }
        @{ Name = 'ADSecurityGroups'; Key = 'GroupName'; Required = @('GroupName', 'GroupType', 'GroupScope', 'Description', 'Category') }
        @{ Name = 'ADDevices'; Key = 'DeviceName'; Required = @('DeviceName', 'DeviceType', 'OperatingSystem', 'Enabled', 'Department') }
    )
}

BeforeAll {
    # Tests/Unit/Providers/AD -> the module root is four folders up. The data sits beside the
    # provider's code rather than at the module root, which is the point of the provider
    # folders: an AD CSV is shared with nothing.
    $script:ModuleRoot = Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent
    $script:DataRoot = Join-Path $script:ModuleRoot 'Providers\AD\Data'
}

Describe 'AD seed data' -Tag 'Unit', 'Contract' {

    It '<Name>.csv exists and parses' -ForEach $script:SeedFile {
        $path = Join-Path $script:DataRoot "$Name.csv"
        Test-Path -LiteralPath $path | Should-BeTrue

        $rows = @(Import-Csv -LiteralPath $path -Encoding UTF8)
        $rows.Count | Should-BeGreaterThan 0
    }

    It '<Name>.csv carries every required column on every row' -ForEach $script:SeedFile {
        # A CSV row missing its trailing field shifts every column after it, and Import-Csv
        # reports nothing at all.
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot "$Name.csv") -Encoding UTF8)
        $columns = @($rows[0].PSObject.Properties.Name)

        foreach ($required in $Required) {
            $columns | Should-ContainCollection @($required)
        }

        $blank = @($rows | Where-Object { -not $_.$Key })
        $blank.Count | Should-Be 0
    }

    It '<Name>.csv has unique keys' -ForEach $script:SeedFile {
        $rows = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot "$Name.csv") -Encoding UTF8)
        $keys = @($rows.$Key)
        @($keys | Sort-Object -Unique).Count | Should-Be $keys.Count
    }

    It 'keeps every SamAccountName inside the 20-character limit' {
        # The hard one. sAMAccountName is capped at 20 characters and New-ADUser fails the whole
        # account when it is exceeded - partway through a seeding run, naming a length rather
        # than the row that caused it.
        $accounts = @(
            Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADUsers.csv') -Encoding UTF8
            Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADServiceAccounts.csv') -Encoding UTF8
        )

        $tooLong = @($accounts | Where-Object { $_.SamAccountName.Length -gt 20 } | ForEach-Object { $_.SamAccountName })
        ($tooLong -join ', ') | Should-Be ''
    }

    It 'carries UPN local parts only, never a whole address' {
        # The column is blank for every row today, and that is deliberate: the seeding code
        # falls back to the SamAccountName and appends the domain it is actually connected to,
        # so the data does not have to name a domain it cannot know. When a value IS present
        # it is treated as the local part and the domain is appended to it - so an address
        # here would come out as 'user@contoso.com@ad.contoso.com'.
        $accounts = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADUsers.csv') -Encoding UTF8)

        $bad = @($accounts | Where-Object { $_.UserPrincipalName -match '@' } |
                ForEach-Object { "$($_.SamAccountName)=$($_.UserPrincipalName)" })
        ($bad -join ', ') | Should-Be ''
    }

    It 'names only managers that exist' {
        # A dangling manager is not an error at creation time - the attribute is simply left
        # unset - so the org chart comes out quietly shallower than the data describes.
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADUsers.csv') -Encoding UTF8)
        $names = @($users.Name)

        # Manager is stored as 'CN=<Name>' rather than a bare name or a full distinguished
        # name, because the OU a person sits in is decided at seeding time and cannot be
        # written into the data. The prefix comes off before comparing.
        $dangling = @(
            $users | Where-Object { $_.Manager -and $_.Manager -ne 'CN=' } | Where-Object {
                $names -notcontains ($_.Manager -replace '^CN=', '')
            } | ForEach-Object { "$($_.SamAccountName) -> $($_.Manager)" }
        )
        ($dangling -join '; ') | Should-Be ''
    }

    It 'includes a user with no manager, because the chain has to terminate' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADUsers.csv') -Encoding UTF8)
        @($users | Where-Object { -not $_.Manager }).Count | Should-BeGreaterThan 0
    }

    It 'includes a disabled account, because offboarding is never finished' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADUsers.csv') -Encoding UTF8)
        @($users | Where-Object { $_.Enabled -eq 'FALSE' }).Count | Should-BeGreaterThan 0
    }

    It 'declares only group scopes and types AD can actually create' {
        # Get-ADGroup reports these exact spellings and New-ADGroup accepts no others, so a
        # typo here fails one group partway through a run.
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADSecurityGroups.csv') -Encoding UTF8)

        $badScope = @($groups | Where-Object { $_.GroupScope -notin @('DomainLocal', 'Global', 'Universal') } |
                ForEach-Object { "$($_.GroupName)=$($_.GroupScope)" })
        $badType = @($groups | Where-Object { $_.GroupType -notin @('Security', 'Distribution') } |
                ForEach-Object { "$($_.GroupName)=$($_.GroupType)" })

        ($badScope -join ', ') | Should-Be ''
        ($badType -join ', ') | Should-Be ''
    }

    It 'names only groups that exist, from the group nesting' {
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADSecurityGroups.csv') -Encoding UTF8)
        $names = @($groups.GroupName)

        # MemberOfGroup is a semicolon-separated list, not a single name - a group can nest
        # into several parents, and several rows do.
        $dangling = @(
            foreach ($group in ($groups | Where-Object { $_.MemberOfGroup })) {
                foreach ($parent in ($group.MemberOfGroup -split ';' | Where-Object { $_.Trim() })) {
                    if ($names -notcontains $parent.Trim()) { "$($group.GroupName) -> $($parent.Trim())" }
                }
            }
        )
        ($dangling -join '; ') | Should-Be ''
    }

    It 'keeps every device sAMAccountName inside the 20-character limit' {
        # The seeding code sets SamAccountName to the device name plus a trailing $, and the
        # attribute is capped at 20 characters - so the name itself has 19 to work with.
        #
        # Nineteen, not fifteen. The old NetBIOS ceiling of 15 is what most guidance still
        # quotes, and 27 of these names exceed it, so it is worth saying why that is fine:
        # verified against a live domain controller, New-ADComputer creates an 18-character
        # name with a 19-character sAMAccountName without complaint. Fifteen only governs
        # pre-Windows 2000 clients, and costs a warning rather than the object.
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADDevices.csv') -Encoding UTF8)

        $tooLong = @($devices | Where-Object { ($_.DeviceName.Length + 1) -gt 20 } |
                ForEach-Object { "$($_.DeviceName) ($($_.DeviceName.Length + 1))" })
        ($tooLong -join ', ') | Should-Be ''
    }

    It 'assigns devices only to users that exist' {
        $users = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADUsers.csv') -Encoding UTF8)
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADDevices.csv') -Encoding UTF8)
        $names = @($users.Name)

        $dangling = @($devices | Where-Object { $_.AssignedUser -and $names -notcontains $_.AssignedUser } |
                ForEach-Object { "$($_.DeviceName) -> $($_.AssignedUser)" })
        ($dangling -join '; ') | Should-Be ''
    }

    It 'covers more than one device type and operating system' {
        # A lab of 688 identical workstations proves nothing about a report that groups by
        # either field.
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADDevices.csv') -Encoding UTF8)

        @($devices.DeviceType | Sort-Object -Unique).Count | Should-BeGreaterThan 1
        @($devices.OperatingSystem | Sort-Object -Unique).Count | Should-BeGreaterThan 1
    }

    It 'shares its people with the Entra provider, because hybrid identity needs both sides' {
        # The Entra seed users were mapped from these, and matching on-premises and cloud
        # accounts is the whole point of having both providers in one module. If the two data
        # sets drift apart, nothing else notices.
        $adUsers = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADUsers.csv') -Encoding UTF8)
        $entraPath = Join-Path $script:ModuleRoot 'Providers\Entra\Data\EntraUsers.csv'
        $entraUsers = @(Import-Csv -LiteralPath $entraPath -Encoding UTF8)

        $adNames = @($adUsers.Name)
        $shared = @($entraUsers | Where-Object { $adNames -contains $_.DisplayName })

        $shared.Count | Should-BeGreaterThan 100
    }
}
