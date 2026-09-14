#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The Active Directory orchestrator. Three things are pinned:

    - The order. The OU tree before anything is placed in it, users before the devices and
      groups that reference them, groups before the password policies applied to them.
    - Honesty. A step that returned errors is a failed step, a step that threw is recorded and
      the rest still run, and a domain controller that stops answering ends the run with one
      message rather than a failure per remaining object.
    - The result. -PassThru carries each step's own result object. It once carried nothing for
      four of the eight steps, because those were called without -PassThru, so a caller reading
      CreatedUsers from the returned object found no such property and no error.

    The step functions are mocked at the module boundary, and the RSAT cmdlets beneath them are
    mocked to throw, so a step added to the orchestrator without a mock here fails loudly rather
    than reaching a domain.
#>

BeforeAll {
    $moduleRoot = (Split-Path -Path (Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent)
    # RSAT, SecretManagement and GPMC are absent on the CI runner, which blocks the import
    # outright and leaves Pester with no command to mock. See Tests/Stubs/README.md.
    . (Join-Path $moduleRoot 'Tests\Stubs\Add-ADTestStubPath.ps1')

    # Imported once per run, not once per file: a warm forced import costs about 190 ms, and 111
    # files paid it. CI runs the suite shuffled, so state one file leaves behind for another
    # fails there rather than hiding in file order.
    if (-not (Get-Module TestEnvironment)) { Import-Module (Join-Path $moduleRoot 'TestEnvironment.psd1') }
}


Describe 'New-ADEnvironment' -Tag 'Unit', 'Public' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Write-TestMessage { }
            Mock Write-Host { }
            Mock Test-ADTestPrerequisite { $true }
            Mock Test-ADTestDirectoryReachable { $true }

            $script:StepOrder = [System.Collections.Generic.List[string]]::new()
            Mock New-ADTestOUStructure { $script:StepOrder.Add('OUStructure'); [PSCustomObject]@{ Created = @(); Skipped = @(1..33); Errors = @() } }
            Mock New-ADTestUser { $script:StepOrder.Add('Users'); [PSCustomObject]@{ CreatedUsers = 311; SkippedUsers = 0; ManagersSet = 310; Errors = @() } }
            Mock New-ADTestDevice { $script:StepOrder.Add('Devices'); [PSCustomObject]@{ CreatedDevices = 688; SkippedDevices = 0; Errors = @() } }
            Mock New-ADTestServiceAccount { $script:StepOrder.Add('ServiceAccounts'); [PSCustomObject]@{ CreatedAccounts = 25; Errors = @() } }
            Mock New-ADTestGroupPolicy { [PSCustomObject]@{ Warnings = @() } }
            Mock New-ADTestSecurityGroups { $script:StepOrder.Add('Groups'); [PSCustomObject]@{ CreatedGroups = 90; MembersAdded = 5969; GroupsNested = 42; Errors = @() } }
            Mock New-ADTestPasswordPolicy { $script:StepOrder.Add('PasswordPolicies'); [PSCustomObject]@{ CreatedPolicies = 3; SubjectsApplied = 3; Errors = @() } }
            Mock New-ADTestDnsZone { $script:StepOrder.Add('Dns'); [PSCustomObject]@{ ZonesCreated = 2; RecordsCreated = 8; DnsAvailable = $true; Errors = @() } }
            Mock New-ADTestEdgeCase { $script:StepOrder.Add('EdgeCases'); [PSCustomObject]@{ Created = @(); Errors = @() } }

            # The backstop. Every step is mocked above; anything that reaches for the directory
            # anyway is a step added without a mock, and it fails here rather than on a domain.
            foreach ($cmdlet in 'New-ADUser', 'New-ADComputer', 'New-ADGroup', 'New-ADOrganizationalUnit', 'Add-ADGroupMember', 'Get-ADUser', 'Get-ADGroup', 'Start-Job') {
                Mock $cmdlet { throw "A directory call escaped the mocks: $cmdlet" }
            }
        }
    }

    It 'runs the seven steps in dependency order, and the edge cases only when asked' {
        InModuleScope TestEnvironment {
            $null = New-ADEnvironment -Confirm:$false
            $script:StepOrder | Should-BeCollection @('OUStructure', 'Users', 'Devices', 'ServiceAccounts', 'Groups', 'PasswordPolicies', 'Dns')

            $script:StepOrder.Clear()
            $null = New-ADEnvironment -IncludeEdgeCase -Confirm:$false
            $script:StepOrder | Should-BeCollection @('OUStructure', 'Users', 'Devices', 'ServiceAccounts', 'Groups', 'PasswordPolicies', 'Dns', 'EdgeCases')
        }
    }

    It 'creates the deny-logon policy right after the service accounts it names, and not when they failed' {
        InModuleScope TestEnvironment {
            Mock New-ADTestGroupPolicy { $script:StepOrder.Add('GroupPolicy'); [PSCustomObject]@{ Warnings = @() } }

            $null = New-ADEnvironment -Confirm:$false
            $script:StepOrder.IndexOf('GroupPolicy') | Should-Be ($script:StepOrder.IndexOf('ServiceAccounts') + 1)

            # A policy naming accounts that were never created would deny logon to nobody, and
            # it used to be attempted anyway, including under -WhatIf.
            $script:StepOrder.Clear()
            Mock New-ADTestServiceAccount { $script:StepOrder.Add('ServiceAccounts'); throw 'refused' }
            $null = New-ADEnvironment -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
            $script:StepOrder | Should-NotContainCollection 'GroupPolicy'
        }
    }

    It 'skips what it is told to and attempts the rest' {
        InModuleScope TestEnvironment {
            $r = New-ADEnvironment -Skip Users, Devices -PassThru -Confirm:$false

            $script:StepOrder | Should-BeCollection @('OUStructure', 'ServiceAccounts', 'Groups', 'PasswordPolicies', 'Dns')
            $r.Operations.Users.Attempted | Should-BeFalse
            $r.Summary.TotalOperations | Should-Be 5
            $r.Summary.SuccessfulOperations | Should-Be 5
            $r.Summary.FailedOperations | Should-Be 0
        }
    }

    It 'carries every step result in the object -PassThru returns' {
        # The OU, user, device and group steps were once called without -PassThru, so these
        # four were empty in the returned object while the summary said they had succeeded.
        InModuleScope TestEnvironment {
            $r = New-ADEnvironment -PassThru -Confirm:$false

            $r.Operations.OUStructure.Results.Skipped.Count | Should-Be 33
            $r.Operations.Users.Results.CreatedUsers | Should-Be 311
            $r.Operations.Users.Results.ManagersSet | Should-Be 310
            $r.Operations.Devices.Results.CreatedDevices | Should-Be 688
            $r.Operations.ServiceAccounts.Results.CreatedAccounts | Should-Be 25
            $r.Operations.Groups.Results.MembersAdded | Should-Be 5969
            $r.Operations.PasswordPolicies.Results.CreatedPolicies | Should-Be 3
            $r.Operations.Dns.Results.ZonesCreated | Should-Be 2
            $r.Summary.SuccessfulOperations | Should-Be 7
        }
    }

    It 'returns nothing without -PassThru' {
        InModuleScope TestEnvironment {
            @(New-ADEnvironment -Confirm:$false) | Should-BeCollection -Count 0
        }
    }

    It 'counts a password policy or DNS step that returned errors as failed, without throwing' {
        InModuleScope TestEnvironment {
            Mock New-ADTestPasswordPolicy { $script:StepOrder.Add('PasswordPolicies'); [PSCustomObject]@{ CreatedPolicies = 2; SubjectsApplied = 2; Errors = @('group missing') } }

            $r = New-ADEnvironment -PassThru -Confirm:$false -WarningAction SilentlyContinue

            $r.Operations.PasswordPolicies.Success | Should-BeFalse
            $r.Summary.FailedOperations | Should-Be 1
            $r.Summary.SuccessfulOperations | Should-Be 6
            $script:StepOrder | Should-ContainCollection @('Dns')
        }
    }

    It 'keeps going when a step throws while the directory still answers' {
        InModuleScope TestEnvironment {
            Mock New-ADTestDevice { $script:StepOrder.Add('Devices'); throw 'device batch exploded' }

            $r = New-ADEnvironment -PassThru -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            $r.Operations.Devices.Success | Should-BeFalse
            $r.Operations.Devices.Results | Should-Be 'device batch exploded'
            $r.Summary.FailedOperations | Should-Be 1
            $script:StepOrder | Should-ContainCollection @('ServiceAccounts', 'Groups', 'PasswordPolicies', 'Dns')
        }
    }

    It 'stops after the step during which the domain controller stopped answering' {
        # The alternative is the same error once per remaining object: a live run once reported
        # it twenty-five times for the service accounts, again for the groups and again for the
        # policies, and then summarised four of seven steps as successful.
        InModuleScope TestEnvironment {
            Mock New-ADTestDevice { $script:StepOrder.Add('Devices'); throw 'unable to find a default server with Active Directory Web Services running' }
            Mock Test-ADTestDirectoryReachable { $false }

            $r = New-ADEnvironment -PassThru -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            $script:StepOrder | Should-BeCollection @('OUStructure', 'Users', 'Devices')
            $r.Operations.ServiceAccounts.Attempted | Should-BeFalse
            $r.Operations.Groups.Attempted | Should-BeFalse
            $r.Summary.FailedOperations | Should-Be 1
        }
    }

    It 'refuses to start when the prerequisites are not met' {
        InModuleScope TestEnvironment {
            Mock Test-ADTestPrerequisite { $false }

            { New-ADEnvironment -Confirm:$false } | Should-Throw -ExceptionMessage '*Prerequisites not met*'
            $script:StepOrder.Count | Should-Be 0
        }
    }

    It 'calls no step under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-ADEnvironment -WhatIf

            $script:StepOrder.Count | Should-Be 0
            Should-NotInvoke New-ADTestUser
            Should-NotInvoke New-ADTestGroupPolicy
        }
    }

    It 'says which steps were not attempted once the domain controller stopped answering, rather than calling them skipped as requested' {
        InModuleScope TestEnvironment {
            Mock New-ADTestDevice { $script:StepOrder.Add('Devices'); throw 'unable to find a default server' }
            Mock Test-ADTestDirectoryReachable { $false }

            $null = New-ADEnvironment -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

            Should-Invoke Write-TestMessage -Times 1 -Exactly -ParameterFilter { $Message -like 'Step 4: Not attempting Service Accounts*stopped answering*' }
            Should-NotInvoke Write-TestMessage -ParameterFilter { $Message -like '*(as requested)*' }
        }
    }

    It 'writes the service account passwords to a file by default, and to the vault when asked' {
        InModuleScope TestEnvironment {
            Mock New-ADTestServiceAccount { $script:StepOrder.Add('ServiceAccounts'); [PSCustomObject]@{ CreatedAccounts = 2; PasswordData = @(@{ Name = 'a' }, @{ Name = 'b' }); Errors = @() } }
            Mock Export-ADTestPasswordDocumentation { 'C:\pw\ServiceAccountPW.csv' }
            Mock Invoke-ADTestSecretStoreOrchestration { [PSCustomObject]@{ TotalStored = 2; Errors = @() } }

            $r = New-ADEnvironment -Skip Users, Devices, Groups, PasswordPolicies, Dns -PassThru -Confirm:$false
            $r.Operations.ServiceAccounts.Results.PasswordFile | Should-Be 'C:\pw\ServiceAccountPW.csv'
            Should-NotInvoke Invoke-ADTestSecretStoreOrchestration

            $password = ConvertTo-SecureString 'VaultPass123!' -AsPlainText -Force
            $r = New-ADEnvironment -Skip Users, Devices, Groups, PasswordPolicies, Dns -UseSecretStore -VaultName 'Lab' -VaultPassword $password -GlobalVault -PassThru -Confirm:$false
            Should-Invoke Invoke-ADTestSecretStoreOrchestration -Times 1 -Exactly -ParameterFilter { $VaultName -eq 'Lab' -and $GlobalVault -and $null -ne $VaultPassword -and @($PasswordData).Count -eq 2 }
            $r.Operations.ServiceAccounts.Results.UseSecretStore | Should-BeTrue
            $r.Operations.ServiceAccounts.Results.VaultName | Should-Be 'Lab'
            $r.Operations.ServiceAccounts.Results.SecretStoreResult.TotalStored | Should-Be 2
            Should-Invoke Export-ADTestPasswordDocumentation -Times 1 -Exactly
        }
    }

    It 'falls back to the file when the vault refuses the passwords, and the step still counts as done' {
        InModuleScope TestEnvironment {
            Mock New-ADTestServiceAccount { $script:StepOrder.Add('ServiceAccounts'); [PSCustomObject]@{ CreatedAccounts = 2; PasswordData = @(@{ Name = 'a' }); Errors = @() } }
            Mock Export-ADTestPasswordDocumentation { 'C:\pw\ServiceAccountPW.csv' }
            Mock Invoke-ADTestSecretStoreOrchestration { throw 'vault locked' }

            $r = New-ADEnvironment -Skip Users, Devices, Groups, PasswordPolicies, Dns -UseSecretStore -PassThru -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue

            $r.Operations.ServiceAccounts.Success | Should-BeTrue
            $r.Operations.ServiceAccounts.Results.PasswordFile | Should-Be 'C:\pw\ServiceAccountPW.csv'
            @($warnings | Where-Object { "$_" -like 'SecretStore orchestration failed: vault locked' }).Count | Should-Be 1
            # The policy still names accounts that exist.
            Should-Invoke New-ADTestGroupPolicy -Times 1 -Exactly
        }
    }
}
