function New-ADTestEdgeCase {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the awkward directory states that CSV-driven test data cannot express
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('All', 'AclDelegation', 'OrphanedSid', 'LegacyEncryption',
                     'PasswordExpiry', 'AmbiguousName', 'MoveTarget', 'CommaName',
                     'MissingUpn', 'MixedMembership', 'FineGrainedPolicy',
                     'GovernanceAttribute')]
        [string[]]$EdgeCase = 'All',

        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestEdgeCase - CorrelationId: $correlationId"

        $domain = Get-ADTestDomain
        $testDataOU = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
        $edgeOU = "OU=EdgeCases,$testDataOU"

        $wanted = { param($name) $EdgeCase -contains 'All' -or $EdgeCase -contains $name }

        $script:Created = [System.Collections.Generic.List[object]]::new()
        $script:EdgeErrors = [System.Collections.Generic.List[string]]::new()

    }

    process {
        try {
            Write-TestMessage -Message "Creating Active Directory Test Edge Cases" -Type Header

            if (-not (Get-ADOrganizationalUnit -Filter ("DistinguishedName -eq " +
                "'$testDataOU'") -ErrorAction SilentlyContinue)) {
                throw "Test OU structure not found at $testDataOU. Run New-ADTestOUStructure first."
            }

            if (-not $PSCmdlet.ShouldProcess($edgeOU, 'Create edge case OU structure')) {
                Write-TestMessage -Message "Would create edge cases under $edgeOU" -Type Info
                return
            }

            $null = (New-ADTestOU -Name 'EdgeCases' -Path $testDataOU `
                -Description 'Deliberately awkward directory states for script testing' `
                    -Unprotected).DistinguishedName

            #region AclDelegation
            if (& $wanted 'AclDelegation') {
                Write-TestMessage -Message "Creating delegated permissions..." -Type Info

                try {
                    $delegatedOU = (New-ADTestOU -Name 'Delegated' -Path $edgeOU `
                        -Description 'Objects an edge case group holds explicit rights over' `
                            -Unprotected).DistinguishedName

                    $delegateName = 'EdgeCase Delegated Admins'
                    $delegate = Get-ADGroup -Filter "Name -eq '$delegateName'" -ErrorAction SilentlyContinue

                    if (-not $delegate) {
                        $delegate = New-ADGroup -Name $delegateName -SamAccountName 'EdgeCaseDelegatedAdmins' `
                            -GroupScope Global -GroupCategory Security -Path $edgeOU `
                            -Description 'Holds delegated rights over OU=Delegated' -PassThru
                    }

                    # Something for the delegation to apply to, so a permissions report has
                    # rows to return rather than an empty result that reads as "no rights".
                    foreach ($n in 1..3) {
                        $sam = "EdgeCaseTarget$n"
                        if (-not (Get-ADGroup -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
                            New-ADGroup -Name "EdgeCase Target $n" -SamAccountName $sam `
                                -GroupScope Global -GroupCategory Security -Path $delegatedOU `
                                -Description "Inherits the delegation applied to OU=Delegated"
                        }
                    }

                    # GenericAll with All inheritance: the group gets one explicit entry on
                    # the OU and an inherited entry on every object inside it, which is what
                    # real delegation looks like and lets a report distinguish the two.
                    $sid = New-Object System.Security.Principal.SecurityIdentifier($delegate.SID)
                    $acl = Get-Acl -Path "AD:\$delegatedOU"
                    $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                        $sid,
                        [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
                        [System.Security.AccessControl.AccessControlType]::Allow,
                        [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All)
                    $acl.AddAccessRule($rule)
                    Set-Acl -Path "AD:\$delegatedOU" -AclObject $acl

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'AclDelegation'
                        Detail   = "$delegateName granted GenericAll over $delegatedOU (inherited by 3 objects)"
                    })
                }
                catch {
                    $script:EdgeErrors.Add("AclDelegation: $($_.Exception.Message)")
                }
            }
            #endregion

            #region OrphanedSid
            if (& $wanted 'OrphanedSid') {
                Write-TestMessage -Message "Planting orphaned SIDs..." -Type Info

                try {
                    $orphanOU = (New-ADTestOU -Name 'Orphaned' -Path $edgeOU `
                        -Description 'Objects carrying access control entries for deleted principals' `
                            -Unprotected).DistinguishedName

                    foreach ($n in 1..2) {
                        $sam = "EdgeCaseOrphanHost$n"
                        if (-not (Get-ADGroup -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) {
                            New-ADGroup -Name "EdgeCase Orphan Host $n" -SamAccountName $sam `
                                -GroupScope Global -GroupCategory Security -Path $orphanOU `
                                -Description 'Carries an access control entry for a SID that no longer resolves'
                        }
                    }

                    # A RID far above anything the domain has issued. The SID is well-formed
                    # and belongs to this domain, so it is stored, but it resolves to nothing
                    # - exactly the residue a deleted account leaves in an ACL. Get-Acl hands
                    # such an entry back as a SecurityIdentifier rather than an NTAccount,
                    # which is how cleanup scripts recognise it.
                    $domainSid = (Get-ADDomain).DomainSID.Value
                    $orphanRid = 90000

                    foreach ($target in @(Get-ADGroup -Filter * -SearchBase $orphanOU)) {
                        $orphanRid++
                        $orphanSid = New-Object System.Security.Principal.SecurityIdentifier(
                            "$domainSid-$orphanRid")

                        $acl = Get-Acl -Path "AD:\$($target.DistinguishedName)"
                        $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                            $orphanSid,
                            [System.DirectoryServices.ActiveDirectoryRights]::GenericRead,
                            [System.Security.AccessControl.AccessControlType]::Allow)
                        $acl.AddAccessRule($rule)
                        Set-Acl -Path "AD:\$($target.DistinguishedName)" -AclObject $acl

                        $script:Created.Add([PSCustomObject]@{
                            EdgeCase = 'OrphanedSid'
                            Detail   = "$domainSid-$orphanRid planted on $($target.Name)"
                        })
                    }
                }
                catch {
                    $script:EdgeErrors.Add("OrphanedSid: $($_.Exception.Message)")
                }
            }
            #endregion

            #region LegacyEncryption
            if (& $wanted 'LegacyEncryption') {
                Write-TestMessage -Message "Creating accounts with legacy Kerberos encryption..." -Type Info

                try {
                    $kerbOU = (New-ADTestOU -Name 'Kerberos' -Path $edgeOU `
                        -Description 'Accounts carrying legacy Kerberos encryption settings' `
                            -Unprotected).DistinguishedName

                    # The values matter individually.
                    #
                    #   0  no explicit value beyond the default, which is the RC4-only state
                    #      an RC4-to-AES migration looks for
                    #   1  DES-CBC-CRC alone
                    #   2  DES-CBC-MD5 alone
                    #   3  both DES types
                    #   24 AES128+AES256, already remediated - the negative control
                    #
                    # 1 and 2 exist specifically because an AD filter written as
                    # "-band 3" requires BOTH bits and silently passes over an account
                    # offering only one, which is the more common misconfiguration and was a
                    # real defect in the DES remediation script.
                    $kerbAccount = @(
                        @{ Sam = 'EdgeCaseKerbRc4'; Name = 'EdgeCase Kerb RC4 Only'; Enc = 0
                           Desc = 'RC4-only: no explicit encryption types set' }
                        @{ Sam = 'EdgeCaseKerbDesCrc'; Name = 'EdgeCase Kerb DES CRC'; Enc = 1
                           Desc = 'DES-CBC-CRC only: missed by a -band 3 filter' }
                        @{ Sam = 'EdgeCaseKerbDesMd5'; Name = 'EdgeCase Kerb DES MD5'; Enc = 2
                           Desc = 'DES-CBC-MD5 only: missed by a -band 3 filter' }
                        @{ Sam = 'EdgeCaseKerbDesBoth'; Name = 'EdgeCase Kerb DES Both'; Enc = 3
                           Desc = 'Both DES types set' }
                        @{ Sam = 'EdgeCaseKerbAes'; Name = 'EdgeCase Kerb AES'; Enc = 24
                           Desc = 'AES only: negative control, must not be selected for remediation' }
                    )

                    foreach ($account in $kerbAccount) {
                        $null = New-ADTestEdgeUser -Name $account.Name -SamAccountName $account.Sam `
                            -Path $kerbOU -Description $account.Desc

                        # Written as a literal 0, not cleared. An absent attribute and an
                        # attribute set to 0 are different things to an LDAP filter: the
                        # RC4-to-AES script selects on "-eq 0", which an absent attribute
                        # does not satisfy, so clearing it produced a fixture that script
                        # could never see.
                        Set-ADUser -Identity $account.Sam `
                            -Replace @{ 'msDS-SupportedEncryptionTypes' = $account.Enc }

                        $script:Created.Add([PSCustomObject]@{
                            EdgeCase = 'LegacyEncryption'
                            Detail   = "$($account.Sam): msDS-SupportedEncryptionTypes = $($account.Enc)"
                        })
                    }

                    # USE_DES_KEY_ONLY, the other half of the DES filter. Set by OR-ing the
                    # bit into the existing userAccountControl rather than assigning it, so
                    # the account's other flags survive.
                    #
                    # 'EdgeCaseKerbDesOnly', not 'EdgeCaseKerbDesKeyOnly': sAMAccountName is
                    # capped at 20 characters for user objects and the longer name failed
                    # with "The name provided is not a properly formed account name", which
                    # does not obviously mean "too long".
                    $desOnlySam = 'EdgeCaseKerbDesOnly'
                    $null = New-ADTestEdgeUser -Name 'EdgeCase Kerb DES Key Only' -SamAccountName $desOnlySam `
                        -Path $kerbOU -Description 'USE_DES_KEY_ONLY set in userAccountControl'

                    $current = (Get-ADUser -Identity $desOnlySam -Properties userAccountControl).userAccountControl
                    Set-ADUser -Identity $desOnlySam `
                        -Replace @{ userAccountControl = ($current -bor 0x200000) }

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'LegacyEncryption'
                        Detail   = "${desOnlySam}: USE_DES_KEY_ONLY (0x200000) set in userAccountControl"
                    })
                }
                catch {
                    $script:EdgeErrors.Add("LegacyEncryption: $($_.Exception.Message)")
                }
            }
            #endregion

            #region PasswordExpiry
            if (& $wanted 'PasswordExpiry') {
                Write-TestMessage -Message "Creating accounts with varied password expiry..." -Type Info

                try {
                    $pwOU = (New-ADTestOU -Name 'PasswordPolicy' -Path $edgeOU `
                        -Description 'Accounts exercising each password expiry outcome' `
                            -Unprotected).DistinguishedName

                    # Every account the rest of the module creates has PasswordNeverExpires
                    # set, so a password expiry report only ever reaches one of its branches.
                    #
                    # msDS-UserPasswordExpiryTimeComputed has three distinct outcomes, and
                    # these accounts produce all three (values confirmed against the live
                    # directory, not assumed):
                    #
                    #   expires      a real filetime            -> a date and a day count
                    #   never        Int64.MaxValue             -> reported as never expiring
                    #   mustchange   0, from pwdLastSet = 0     -> also reported as no expiry,
                    #                                             but for a different reason
                    #
                    # Int64.MaxValue comes from PasswordNeverExpires. It is worth being
                    # explicit that it does NOT come from requiring a smart card, which is
                    # the intuitive guess: a smart-card account's password still expires on
                    # the domain schedule. The smartcard account below is therefore not extra
                    # branch coverage - it is kept because it is a real configuration a
                    # report will meet, and because it documents that non-equivalence.
                    $pwExpires = @{
                        Name           = 'EdgeCase Password Expires'
                        SamAccountName = 'EdgeCasePwExpires'
                        Path           = $pwOU
                        Description    = 'Password expires on the domain schedule'
                        Extra          = @{ PasswordNeverExpires = $false }
                    }
                    $null = New-ADTestEdgeUser @pwExpires

                    $pwNever = @{
                        Name           = 'EdgeCase Password Never Expires'
                        SamAccountName = 'EdgeCasePwNever'
                        Path           = $pwOU
                        Description    = 'PasswordNeverExpires: reports no expiry'
                        Extra          = @{ PasswordNeverExpires = $true }
                    }
                    $null = New-ADTestEdgeUser @pwNever

                    $pwMustChange = @{
                        Name           = 'EdgeCase Password Must Change'
                        SamAccountName = 'EdgeCasePwMustChange'
                        Path           = $pwOU
                        Description    = 'Must change at next logon: expiry computes to 0'
                        Extra          = @{ PasswordNeverExpires = $false; ChangePasswordAtLogon = $true }
                    }
                    $null = New-ADTestEdgeUser @pwMustChange

                    $pwSmartcard = @{
                        Name           = 'EdgeCase Password Smartcard'
                        SamAccountName = 'EdgeCasePwSmartcard'
                        Path           = $pwOU
                        Description    = 'Smart card required: password still expires normally'
                        Extra          = @{ PasswordNeverExpires = $false; SmartcardLogonRequired = $true }
                    }
                    $null = New-ADTestEdgeUser @pwSmartcard

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'PasswordExpiry'
                        Detail   = 'Four accounts covering expires / never / must-change / smart-card'
                    })
                }
                catch {
                    $script:EdgeErrors.Add("PasswordExpiry: $($_.Exception.Message)")
                }
            }
            #endregion

            #region AmbiguousName
            if (& $wanted 'AmbiguousName') {
                Write-TestMessage -Message "Creating an ambiguous group name..." -Type Info

                try {
                    $ambiguousOU = (New-ADTestOU -Name 'Ambiguous' -Path $edgeOU `
                        -Description 'Holds the second group sharing an ambiguous display name' `
                            -Unprotected).DistinguishedName

                    # A common name is unique only within its container, so the same display
                    # name can exist twice in one domain as long as the two live in different
                    # OUs. sAMAccountName is domain-wide unique and so still differs.
                    #
                    # Several scripts resolve a group by Name and implement a branch for
                    # "matched more than one" - a branch nothing in a generated environment
                    # can otherwise reach, because generated names never collide.
                    $ambiguousName = 'EdgeCase Ambiguous Group'

                    foreach ($pair in @(@{ Path = $edgeOU; Sam = 'EdgeCaseAmbiguousA' },
                                        @{ Path = $ambiguousOU; Sam = 'EdgeCaseAmbiguousB' })) {
                        if (-not (Get-ADGroup -Filter ("SamAccountName -eq " +
                            "'$($pair.Sam)'") -ErrorAction SilentlyContinue)) {
                            New-ADGroup -Name $ambiguousName -SamAccountName $pair.Sam `
                                -GroupScope Global -GroupCategory Security -Path $pair.Path `
                                -Description "Shares a display name with another group in a different OU"
                        }
                    }

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'AmbiguousName'
                        Detail   = "'$ambiguousName' exists twice (EdgeCaseAmbiguousA, EdgeCaseAmbiguousB)"
                    })
                }
                catch {
                    $script:EdgeErrors.Add("AmbiguousName: $($_.Exception.Message)")
                }
            }
            #endregion

            #region MoveTarget
            if (& $wanted 'MoveTarget') {
                Write-TestMessage -Message "Creating a move target OU..." -Type Info

                try {
                    $moveOU = (New-ADTestOU -Name 'MoveTarget' -Path $edgeOU `
                        -Description 'Empty destination for group move and migration scripts' `
                            -Unprotected).DistinguishedName

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'MoveTarget'
                        Detail   = "Empty OU available at $moveOU"
                    })
                }
                catch {
                    $script:EdgeErrors.Add("MoveTarget: $($_.Exception.Message)")
                }
            }
            #endregion

            #region CommaName
            if (& $wanted 'CommaName') {
                Write-TestMessage -Message "Creating objects whose name contains a comma..." -Type Info

                try {
                    $commaOU = (New-ADTestOU -Name 'CommaNames' -Path $edgeOU `
                        -Description 'Objects whose common name contains a comma' `
                            -Unprotected).DistinguishedName

                    # "Surname, Given" is one of the most common naming conventions there is,
                    # and AD stores the resulting CN escaped: CN=Nakamura\, Yuki. Code that
                    # recovers a name with Split(',')[0] returns "Nakamura\", and code that
                    # strips the leading RDN with a regex like ^CN=[^,]+, stops at the escaped
                    # comma and reports a parent container that does not exist. Neither
                    # throws, so both produce confident nonsense.
                    #
                    # A group and a user, because the two parse sites this exercises operate
                    # on different object types.
                    $commaGroupSam = 'EdgeCaseCommaGroup'
                    if (-not (Get-ADGroup -Filter ("SamAccountName -eq " +
                        "'$commaGroupSam'") -ErrorAction SilentlyContinue)) {
                        New-ADGroup -Name 'Acme, Inc Contractors' -SamAccountName $commaGroupSam `
                            -GroupScope Global -GroupCategory Security -Path $commaOU `
                            -Description 'Common name contains a comma; AD stores it escaped'
                    }

                    $null = New-ADTestEdgeUser -Name 'Nakamura, Yuki' -SamAccountName 'EdgeCaseCommaUser' `
                        -Path $commaOU -Description 'Common name in Surname, Given form'

                    Add-ADGroupMember -Identity $commaGroupSam -Members 'EdgeCaseCommaUser' `
                        -ErrorAction SilentlyContinue

                    # A child group nested INTO the comma-named one. This is the part that
                    # matters: a nesting report names the PARENT, so the escaped comma only
                    # reaches the parsing code when the awkward name is somebody's parent.
                    # A comma-named leaf on its own proves nothing.
                    $commaChildSam = 'EdgeCaseCommaChild'
                    if (-not (Get-ADGroup -Filter ("SamAccountName -eq " +
                        "'$commaChildSam'") -ErrorAction SilentlyContinue)) {
                        New-ADGroup -Name 'EdgeCase Comma Child' -SamAccountName $commaChildSam `
                            -GroupScope Global -GroupCategory Security -Path $commaOU `
                            -Description 'Nested into a group whose name contains a comma'
                    }

                    Add-ADGroupMember -Identity $commaGroupSam -Members $commaChildSam `
                        -ErrorAction SilentlyContinue

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'CommaName'
                        Detail   = "'Acme, Inc Contractors' and 'Nakamura, Yuki' created with escaped commas"
                    })
                }
                catch {
                    $script:EdgeErrors.Add("CommaName: $($_.Exception.Message)")
                }
            }
            #endregion

            #region MissingUpn
            if (& $wanted 'MissingUpn') {
                Write-TestMessage -Message "Creating an account with no userPrincipalName..." -Type Info

                try {
                    $null = New-ADTestEdgeUser -Name 'EdgeCase No UPN' -SamAccountName 'EdgeCaseNoUpn' `
                        -Path $edgeOU -Description 'No userPrincipalName: exercises the SamAccountName fallback' `
                        -NoUserPrincipalName

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'MissingUpn'
                        Detail   = 'EdgeCaseNoUpn has no userPrincipalName'
                    })
                }
                catch {
                    $script:EdgeErrors.Add("MissingUpn: $($_.Exception.Message)")
                }
            }
            #endregion

            #region MixedMembership
            if (& $wanted 'MixedMembership') {
                Write-TestMessage -Message "Creating a group with non-user, non-group members..." -Type Info

                try {
                    $mixedOU = (New-ADTestOU -Name 'MixedMembership' -Path $edgeOU `
                        -Description 'A group whose members are not all users or groups' `
                            -Unprotected).DistinguishedName

                    $mixedSam = 'EdgeCaseMixedMembers'
                    if (-not (Get-ADGroup -Filter ("SamAccountName -eq " +
                        "'$mixedSam'") -ErrorAction SilentlyContinue)) {
                        New-ADGroup -Name 'EdgeCase Mixed Members' -SamAccountName $mixedSam `
                            -GroupScope Global -GroupCategory Security -Path $mixedOU `
                            -Description 'Contains a computer and a contact as well as a user'
                    }

                    if (-not (Get-ADComputer -Filter "Name -eq 'EDGECASE-PC01'" -ErrorAction SilentlyContinue)) {
                        New-ADComputer -Name 'EDGECASE-PC01' -SamAccountName 'EDGECASE-PC01$' `
                            -Path $mixedOU -Description 'Group member that is a computer'
                    }

                    # A contact has no sAMAccountName and no SID at all, which is a stronger
                    # test than the computer: code that reaches for either gets nothing back
                    # rather than getting something unexpected.
                    $contactDn = "CN=EdgeCase Contact,$mixedOU"
                    if (-not (Get-ADObject -Filter ("DistinguishedName -eq " +
                        "'$contactDn'") -ErrorAction SilentlyContinue)) {
                        New-ADObject -Name 'EdgeCase Contact' -Type 'contact' -Path $mixedOU `
                            -OtherAttributes @{ mail = "edgecase.contact@$($domain.DNSName)" }
                    }

                    $null = New-ADTestEdgeUser -Name 'EdgeCase Mixed User' -SamAccountName 'EdgeCaseMixedUser' `
                        -Path $mixedOU -Description 'The one member that is an ordinary user'

                    # The computer and the user go in with Add-ADGroupMember. The contact
                    # cannot: Add-ADGroupMember resolves -Members as a security principal and
                    # a contact has no SID, so it fails with "Cannot find an object with
                    # identity" even though the object plainly exists. Writing the member
                    # attribute directly is the way to put a non-principal in a group - and
                    # that asymmetry is itself worth having in the fixture.
                    foreach ($memberDn in @((Get-ADComputer 'EDGECASE-PC01').DistinguishedName,
                                            (Get-ADUser 'EdgeCaseMixedUser').DistinguishedName)) {
                        Add-ADGroupMember -Identity $mixedSam -Members $memberDn -ErrorAction SilentlyContinue
                    }

                    $mixedGroupDn = (Get-ADGroup -Identity $mixedSam).DistinguishedName
                    if (@((Get-ADGroup -Identity $mixedSam -Properties member).member) -notcontains $contactDn) {
                        Set-ADObject -Identity $mixedGroupDn -Add @{ member = $contactDn }
                    }

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'MixedMembership'
                        Detail   = "'EdgeCase Mixed Members' holds a computer, a contact and a user"
                    })
                }
                catch {
                    $script:EdgeErrors.Add("MixedMembership: $($_.Exception.Message)")
                }
            }
            #endregion

            #region FineGrainedPolicy
            if (& $wanted 'FineGrainedPolicy') {
                Write-TestMessage -Message "Creating a fine-grained password policy..." -Type Info

                try {
                    $fgppSubjectSam = 'EdgeCaseFgppSubjects'
                    if (-not (Get-ADGroup -Filter ("SamAccountName -eq " +
                        "'$fgppSubjectSam'") -ErrorAction SilentlyContinue)) {
                        New-ADGroup -Name 'EdgeCase FGPP Subjects' -SamAccountName $fgppSubjectSam `
                            -GroupScope Global -GroupCategory Security -Path $edgeOU `
                            -Description 'Members are governed by the edge case password settings object'
                    }

                    $null = New-ADTestEdgeUser -Name 'EdgeCase FGPP User' -SamAccountName 'EdgeCaseFgppUser' `
                        -Path $edgeOU -Description 'Password expiry comes from an FGPP, not the domain default' `
                        -Extra @{ PasswordNeverExpires = $false }

                    Add-ADGroupMember -Identity $fgppSubjectSam -Members 'EdgeCaseFgppUser' `
                        -ErrorAction SilentlyContinue

                    # A one-day maximum age against a domain default of several weeks. That
                    # difference is the whole point: an expiry report that reads the computed
                    # attribute reports about a day for this account and the domain default
                    # for everyone else, which is what proves the FGPP is being honoured.
                    #
                    # It also gives the environment its only account expiring imminently, so
                    # a "expiring within the next N days" query returns something. A genuinely
                    # past-due expiry cannot be manufactured: pwdLastSet is set by the
                    # directory and cannot be backdated.
                    $policyName = 'EdgeCase Short Expiry'
                    if (-not (Get-ADFineGrainedPasswordPolicy -Filter ("Name -eq " +
                        "'$policyName'") -ErrorAction SilentlyContinue)) {
                        New-ADFineGrainedPasswordPolicy -Name $policyName `
                            -Precedence 500 `
                            -MaxPasswordAge '1.00:00:00' `
                            -MinPasswordAge '00:00:00' `
                            -MinPasswordLength 8 `
                            -PasswordHistoryCount 1 `
                            -ComplexityEnabled $true `
                            -Description 'Short maximum password age for edge case testing'
                    }

                    Add-ADFineGrainedPasswordPolicySubject -Identity $policyName `
                        -Subjects $fgppSubjectSam -ErrorAction SilentlyContinue

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'FineGrainedPolicy'
                        Detail   = "'$policyName' (1 day max age) applied to $fgppSubjectSam"
                    })
                }
                catch {
                    $script:EdgeErrors.Add("FineGrainedPolicy: $($_.Exception.Message)")
                }
            }
            #endregion

            #region GovernanceAttribute
            if (& $wanted 'GovernanceAttribute') {
                Write-TestMessage -Message "Populating governance attributes..." -Type Info

                try {
                    $govOU = (New-ADTestOU -Name 'Governance' -Path $edgeOU `
                        -Description 'Groups carrying base-schema attributes a governance export can read' `
                            -Unprotected).DistinguishedName

                    # See the note in .NOTES: extensionAttribute1-15 need the Exchange schema,
                    # so these are the base-schema attributes that come closest in meaning and
                    # were confirmed writable on the group class in this forest.
                    $govGroup = @(
                        @{ Sam = 'EdgeCaseGovPayroll'; Name = 'EdgeCase Gov Payroll'
                           Note = 'SOX in scope; recertified quarterly'
                           Doc = 'https://runbooks.example/groups/payroll'
                           MultiValued = 'Payroll' }
                        @{ Sam = 'EdgeCaseGovSourceCtl'; Name = 'EdgeCase Gov Source Control'
                           Note = 'Export-controlled content'
                           Doc = 'https://runbooks.example/groups/source-control'
                           MultiValued = 'SourceControl' }
                        @{ Sam = 'EdgeCaseGovUnmanaged'; Name = 'EdgeCase Gov Unmanaged'
                           Note = ''; Doc = ''; MultiValued = '' }
                    )

                    foreach ($item in $govGroup) {
                        if (-not (Get-ADGroup -Filter ("SamAccountName -eq " +
                            "'$($item.Sam)'") -ErrorAction SilentlyContinue)) {
                            New-ADGroup -Name $item.Name -SamAccountName $item.Sam `
                                -GroupScope Global -GroupCategory Security -Path $govOU `
                                -Description 'Carries governance attributes for export testing'
                        }

                        # The third group is left deliberately blank so an export has both a
                        # populated and an unpopulated row to render.
                        $attribute = @{}
                        if ($item.Note) { $attribute['info'] = $item.Note }
                        if ($item.Doc) { $attribute['wWWHomePage'] = $item.Doc }

                        # extensionName as well, and it is NOT in the recommended map above.
                        # It is multi-valued, and an export that writes an attribute straight
                        # into a CSV cell renders a multi-valued one as the literal string
                        # "Microsoft.ActiveDirectory.Management.ADPropertyValueCollection"
                        # rather than its contents. Kept populated on purpose so that
                        # behaviour stays reproducible by pointing a map at extensionName.
                        if ($item.MultiValued) { $attribute['extensionName'] = $item.MultiValued }

                        if ($attribute.Count -gt 0) {
                            Set-ADGroup -Identity $item.Sam -Replace $attribute
                        }
                    }

                    $script:Created.Add([PSCustomObject]@{
                        EdgeCase = 'GovernanceAttribute'
                        Detail   = 'extensionName / info / wWWHomePage populated on 2 of 3 ' +
                               'groups under OU=Governance'
                    })
                }
                catch {
                    $script:EdgeErrors.Add("GovernanceAttribute: $($_.Exception.Message)")
                }
            }
            #endregion

            $results = [PSCustomObject]@{
                CorrelationId = $correlationId
                EdgeCaseRoot  = $edgeOU
                Requested     = $EdgeCase
                Created       = $script:Created
                Errors        = @($script:EdgeErrors)
            }

            Write-TestMessage -Message "Edge Case Creation Summary" -Type Success
            Write-Host "  Root: $edgeOU" -ForegroundColor Cyan

            foreach ($item in $script:Created) {
                Write-Host "  [$($item.EdgeCase)] $($item.Detail)" -ForegroundColor Green
            }

            # Every object above now carries the seed tag, which is what teardown requires
            # before it will delete anything. Swept once here rather than threaded through a
            # dozen creation calls across four nested containers - the thirteenth call added
            # later would be the one that got forgotten, and an untagged object is one teardown
            # leaves behind for somebody to find by hand.
            #
            # The password settings object is named separately because it lives in the Password
            # Settings Container, not with the objects it applies to.
            if (-not $WhatIfPreference) {
                $pso = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'EdgeCase Short Expiry'" -ErrorAction SilentlyContinue
                $stamped = Set-ADTestSeedTag -SearchBase $edgeOU -Identity @($pso.DistinguishedName) -Confirm:$false
                Write-Verbose "Stamped the seed tag on $stamped edge case object(s)"
            }
            if ($script:EdgeErrors.Count -gt 0) {
                Write-Host "  Errors: $($script:EdgeErrors.Count)" -ForegroundColor Red
                $script:EdgeErrors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }

            Write-Host ''
            $edgeNote = '  Remove-ADEnvironment removes OU=EdgeCases and everything in it,'
            Write-Host $edgeNote -ForegroundColor Yellow
            Write-Host '  including the access control entries written above.' -ForegroundColor Yellow

            if ($PassThru) {
                return $results
            }
        }
        catch {
            Write-Error "Failed to create edge cases: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed New-ADTestEdgeCase - CorrelationId: $correlationId"
    }
}
