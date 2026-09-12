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

    It 'gives every device a unique address inside the range the seed zones cover' {
        # The reverse zone the seed creates covers 10.214.0.0/16 and nothing else, so an
        # address outside it would have no PTR and a duplicate would collide on one. What was
        # in this column before was neither: 269 of the 688 were blank and only 305 of the
        # rest were unique, which is why nothing could be written to DNS from it.
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADDevices.csv') -Encoding UTF8)

        @($devices | Where-Object { -not $_.IPAddress }) | Should-BeCollection -Count 0
        @($devices | Where-Object { $_.IPAddress -notmatch '^10\.214\.\d{1,3}\.\d{1,3}$' }) | Should-BeCollection -Count 0
        @($devices.IPAddress | Sort-Object -Unique).Count | Should-Be $devices.Count
        # The FreeIPA provider owns 10.213, so a hybrid estate can seed both.
        @($devices | Where-Object { $_.IPAddress -like '10.213.*' }) | Should-BeCollection -Count 0
    }

    It 'holds a service principal name on some accounts and not most, each naming a seeded server' {
        # Eight of twenty-five, which is the proportion a real domain has: a review that
        # assumes every service account holds one, or that none does, is wrong either way.
        $accounts = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADServiceAccounts.csv') -Encoding UTF8)
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADDevices.csv') -Encoding UTF8)
        $withSpn = @($accounts | Where-Object ServicePrincipalNames)

        $withSpn.Count | Should-Be 8
        $withSpn.Count | Should-BeLessThan $accounts.Count

        $deviceNames = @($devices.DeviceName | ForEach-Object { $_.ToLowerInvariant() })
        foreach ($account in $withSpn) {
            foreach ($spn in ($account.ServicePrincipalNames -split ';' | Where-Object { $_ })) {
                # class/host, with the host written against the seed's own zone.
                $spn | Should-MatchString '^[A-Za-z]+/'
                $spn | Should-MatchString '\{zone\}'
                $hostPart = (($spn -split '/', 2)[1] -split ':')[0]
                if ($hostPart -like '{prefix}*') {
                    $shortName = $hostPart -replace '^\{prefix\}', '' -replace '\.\{zone\}$', ''
                    $deviceNames | Should-ContainCollection $shortName
                }
            }
        }
    }

    It 'delegates only where an account holds a principal name, only to one that exists, and never without constraint' {
        # Unconstrained delegation is a live weakness rather than inert test data, so the seed
        # has none and there is no column that could ask for it.
        $accounts = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADServiceAccounts.csv') -Encoding UTF8)
        $allSpns = @($accounts | ForEach-Object { $_.ServicePrincipalNames -split ';' } | Where-Object { $_ })
        $delegating = @($accounts | Where-Object DelegateTo)

        $delegating.Count | Should-Be 1
        foreach ($account in $delegating) {
            $account.ServicePrincipalNames | Should-NotBe ''
            foreach ($target in ($account.DelegateTo -split ';' | Where-Object { $_ })) {
                $allSpns | Should-ContainCollection $target
            }
        }
        @($accounts[0] | Get-Member -MemberType NoteProperty).Name |
            Should-NotContainCollection @('TrustedForDelegation')
    }

    It 'names a seeded group on every password policy, at a precedence of its own' {
        $policies = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADPasswordPolicies.csv') -Encoding UTF8)
        $groups = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADSecurityGroups.csv') -Encoding UTF8)

        $policies.Count | Should-Be 3
        @($policies.Precedence | Sort-Object -Unique).Count | Should-Be $policies.Count
        foreach ($policy in $policies) {
            $groups.GroupName | Should-ContainCollection $policy.AppliesToGroup
            $policy.Precedence | Should-MatchString '^\d+$'
            $policy.ComplexityEnabled | Should-MatchString '^(TRUE|FALSE)$'
            $policy.ReversibleEncryption | Should-MatchString '^(TRUE|FALSE)$'
        }
        # One of each shape a review has to notice, and the weakest carries the highest
        # precedence number, so the strict policy wins wherever the two overlap.
        @($policies | Where-Object ReversibleEncryption -eq 'TRUE').Count | Should-Be 1
        @($policies | Where-Object ComplexityEnabled -eq 'FALSE').Name | Should-BeCollection @('contractors')
        [int]($policies | Where-Object ComplexityEnabled -eq 'FALSE').Precedence |
            Should-Be ([int](($policies.Precedence | Measure-Object -Maximum).Maximum))
        @($policies | Where-Object MaxPasswordAgeDays -eq '0').Name | Should-BeCollection @('privileged')
    }

    It 'writes DNS records only into the seed zones, naming seeded servers or deliberately nothing' {
        $records = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADDnsRecords.csv') -Encoding UTF8)
        $devices = @(Import-Csv -LiteralPath (Join-Path $script:DataRoot 'ADDevices.csv') -Encoding UTF8)
        $deviceNames = @($devices.DeviceName | ForEach-Object { $_.ToLowerInvariant() })

        foreach ($record in $records) {
            $record.Zone | Should-MatchString '^(Forward|Reverse)$'
            $record.Type | Should-MatchString '^(A|CNAME|TXT|PTR)$'
            if ($record.Type -eq 'PTR') { $record.Zone | Should-Be 'Reverse' } else { $record.Zone | Should-Be 'Forward' }
            # A name written against the zone carries the placeholder, never a literal domain.
            foreach ($value in ($record.Data -split ';' | Where-Object { $_ })) {
                if ($value -match '\.$') { $value | Should-MatchString '\{zone\}\.$' }
                if ($value -match '^\d+\.') { $value | Should-MatchString '^10\.214\.' }
            }
        }

        # The aliases and reverse records point at seeded servers, except the stale ones,
        # which are the point of them.
        $targets = @($records | Where-Object { $_.Type -in 'CNAME', 'PTR' } |
                ForEach-Object { $_.Data -replace '^\{prefix\}', '' -replace '\.\{zone\}\.$', '' })
        @($targets | Where-Object { $deviceNames -notcontains $_ } | Sort-Object) |
            Should-BeCollection @('decommissioned-01', 'ghost-01', 'retired-01')
    }
}
