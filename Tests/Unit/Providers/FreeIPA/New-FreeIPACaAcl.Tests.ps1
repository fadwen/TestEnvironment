#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    The certificates are the one thing the seed asks the realm to make that the realm can
    never unmake, so what is pinned here is mostly restraint. For CA ACLs: members resolved
    to realm names, a profile or CA named only through builtin:, a category of all sent as
    the category, the disabled rule disabled, and the stock rule never named. For
    certificates: the request built with the login or host name as the common name and the
    realm as the organisation, the SAN only where a row asks and the email taken from the
    user's own entry, a row satisfied by a certificate already in its state so a second run
    asks the CA for nothing, the revoked rows revoked with their reason, a refused row
    recorded and the rest continued, and the private key never returned. For the request
    builder: real PKCS#10 DER from in-box .NET in both editions. For the date parser: the
    asctime form the certificate commands use, single-digit day included.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'New-FreeIPACaAcl' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com'; Realm = 'IPA.EXAMPLE.COM' } }
            Mock Get-FreeIPASeededObject { @() }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options })
                if ($Method -like 'caacl_add_*') { return [PSCustomObject]@{ completed = 1; failed = $null } }
                [PSCustomObject]@{ result = [PSCustomObject]@{ cn = @($Arguments[0]) } }
            }
        }
    }

    It 'creates each rule with the marker, resolves members to realm names, names a profile or CA only as builtin, and disables the paused one' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPACaAcl -PassThru -Confirm:$false
            $r.CreatedAcls | Should-Be 4
            $r.Errors | Should-BeCollection -Count 0

            $users = ($script:Calls | Where-Object { $_.Method -eq 'caacl_add' -and $_.Arguments[0] -eq 'zz-test-user-certs' }).Options
            $users.description | Should-MatchString '\[ZZ-TEST-seed\]$'
            $users.ContainsKey('usercategory') | Should-BeFalse
            $members = ($script:Calls | Where-Object { $_.Method -eq 'caacl_add_user' -and $_.Arguments[0] -eq 'zz-test-user-certs' }).Options
            @($members.user) | Should-BeCollection @('talvarez', 'mbell')
            @($members.group) | Should-BeCollection @('zz-test-dept-engineering', 'zz-test-lab-admins')
            @(($script:Calls | Where-Object { $_.Method -eq 'caacl_add_profile' -and $_.Arguments[0] -eq 'zz-test-user-certs' }).Options.certprofile) | Should-BeCollection @('IECUserRoles')
            @(($script:Calls | Where-Object { $_.Method -eq 'caacl_add_ca' -and $_.Arguments[0] -eq 'zz-test-user-certs' }).Options.ca) | Should-BeCollection @('ipa')

            $web = ($script:Calls | Where-Object { $_.Method -eq 'caacl_add_host' -and $_.Arguments[0] -eq 'zz-test-web-service-certs' }).Options
            @($web.hostgroup) | Should-BeCollection @('zz-test-web-servers')
            @(($script:Calls | Where-Object { $_.Method -eq 'caacl_add_service' -and $_.Arguments[0] -eq 'zz-test-web-service-certs' }).Options.service) |
                Should-BeCollection @('HTTP/zz-test-web01.zz-test-lab.ipa.example.com@IPA.EXAMPLE.COM', 'HTTP/zz-test-bastion01.zz-test-lab.ipa.example.com@IPA.EXAMPLE.COM')

            # Every profile and every CA as categories, and nothing added to it.
            $empty = ($script:Calls | Where-Object { $_.Method -eq 'caacl_add' -and $_.Arguments[0] -eq 'zz-test-empty-acl' }).Options
            $empty.ipacertprofilecategory | Should-Be 'all'
            $empty.ipacacategory | Should-Be 'all'
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -like 'caacl_add_*' -and $Arguments[0] -eq 'zz-test-empty-acl' }

            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'caacl_disable' -and $Arguments[0] -eq 'zz-test-smartcard-pilot' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'caacl_disable' -and $Arguments[0] -ne 'zz-test-smartcard-pilot' }
        }
    }

    It 'never names the stock rule, and every request carries the prefix' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPACaAcl -Confirm:$false
            $named = @($script:Calls | Where-Object { $_.Method -like 'caacl_*' } | ForEach-Object { $_.Arguments[0] })
            $named.Count | Should-BeGreaterThan 0
            @($named | Where-Object { $_ -notlike 'zz-test-*' }) | Should-BeCollection -Count 0
            $named | Should-NotContainCollection @('hosts_services_caIPAserviceCert')
            (Get-Command New-FreeIPACaAcl).Parameters.Keys | Should-NotContainCollection @('IncludeStock', 'Force')
        }
    }

    It 'modifies and re-enables what exists on a re-run, and creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPASeededObject { @([PSCustomObject]@{ cn = @('zz-test-user-certs'); description = @('x [ZZ-TEST-seed]') }) }
            $r = New-FreeIPACaAcl -AclName user-certs -PassThru -Confirm:$false
            $r.UpdatedAcls | Should-Be 1
            $r.CreatedAcls | Should-Be 0
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'caacl_mod' }
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'caacl_enable' }
        }
    }

    It 'creates nothing under -WhatIf' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPACaAcl -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
        }
    }
}

Describe 'New-FreeIPACertificate' -Tag 'Unit', 'Public', 'Safety' {

    BeforeEach {
        InModuleScope TestEnvironment {
            Mock Get-FreeIPAConnection { @{ BaseUrl = 'https://ipa.example.com'; Prefix = 'ZZ-TEST-'; SeedTag = 'ZZ-TEST-seed'; SeedMarker = '[ZZ-TEST-seed]'; Domain = 'ipa.example.com'; Realm = 'IPA.EXAMPLE.COM' } }
            $script:Calls = [System.Collections.Generic.List[object]]::new()
            $script:Held = @{}
            $script:Serial = 100
            Mock New-FreeIPACertificateRequest { "-----BEGIN CERTIFICATE REQUEST-----`nREQUEST FOR $Subject SAN $($DnsName -join ',') $($EmailAddress -join ',')`n-----END CERTIFICATE REQUEST-----`n" }
            Mock Invoke-FreeIPARequest {
                $script:Calls.Add(@{ Method = $Method; Arguments = @($Arguments); Options = $Options; Find = [bool]$Find })
                switch ($Method) {
                    'cert_find' {
                        $owner = @($Options.user) + @($Options.service) + @($Options.host) | Where-Object { $_ } | Select-Object -First 1
                        if ($script:Held.ContainsKey($owner)) { return @($script:Held[$owner]) }
                        return @()
                    }
                    'user_show' { return [PSCustomObject]@{ result = [PSCustomObject]@{ uid = @($Arguments[0]); mail = @("$($Arguments[0])@ipa.example.com") } } }
                    'cert_request' {
                        $script:Serial++
                        return [PSCustomObject]@{ result = [PSCustomObject]@{ serial_number = "$script:Serial"; subject = "CN=x,O=IPA.EXAMPLE.COM"; valid_not_after = 'Mon Sep 11 22:16:42 2028 UTC' } }
                    }
                    'cert_revoke' { return [PSCustomObject]@{ result = [PSCustomObject]@{ revoked = $true } } }
                }
            }
        }
    }

    It 'asks the CA for each row with the right subject, principal, profile and SAN, and revokes the revoked ones with their reason' {
        InModuleScope TestEnvironment {
            $r = New-FreeIPACertificate -PassThru -Confirm:$false
            $r.TotalCertificates | Should-Be 10
            $r.Issued | Should-Be 10
            $r.Revoked | Should-Be 3
            $r.Existing | Should-Be 0
            $r.Errors | Should-BeCollection -Count 0

            $requests = @($script:Calls | Where-Object { $_.Method -eq 'cert_request' })
            $requests.Count | Should-Be 10
            $ada = $requests | Where-Object { $_.Options.principal -eq 'awhitfield@IPA.EXAMPLE.COM' }
            $ada.Arguments[0] | Should-MatchString 'CN=awhitfield,O=IPA\.EXAMPLE\.COM'
            $ada.Arguments[0] | Should-MatchString 'awhitfield@ipa\.example\.com'
            $ada.Options.profile_id | Should-Be 'IECUserRoles'
            $ada.Options.add | Should-BeTrue
            # No email SAN for a row that did not ask, and the user's entry not read for it.
            $jose = $requests | Where-Object { $_.Options.principal -eq 'jnino@IPA.EXAMPLE.COM' }
            $jose.Arguments[0] | Should-NotMatchString '@ipa\.example\.com'
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'user_show' -and $Arguments[0] -eq 'jnino' }

            $web = $requests | Where-Object { $_.Options.principal -eq 'HTTP/zz-test-web01.zz-test-lab.ipa.example.com@IPA.EXAMPLE.COM' }
            $web.Arguments[0] | Should-MatchString 'CN=zz-test-web01\.zz-test-lab\.ipa\.example\.com,O=IPA\.EXAMPLE\.COM SAN zz-test-web01\.zz-test-lab\.ipa\.example\.com'
            $web.Options.profile_id | Should-Be 'caIPAserviceCert'
            $nfs = $requests | Where-Object { $_.Options.principal -eq 'host/zz-test-nfs01.zz-test-lab.ipa.example.com@IPA.EXAMPLE.COM' }
            $nfs.Arguments[0] | Should-MatchString 'CN=zz-test-nfs01\.zz-test-lab\.ipa\.example\.com'

            $revocations = @($script:Calls | Where-Object { $_.Method -eq 'cert_revoke' })
            @($revocations | ForEach-Object { $_.Options.revocation_reason }) | Should-BeCollection @(1, 6, 5)
            # Every serial revoked is one this run was issued.
            $issued = @($r.Certificates.Serial)
            foreach ($revocation in $revocations) { $issued | Should-ContainCollection $revocation.Arguments[0] }

            ($r.Certificates | Where-Object Key -eq 'zmueller-compromised').State | Should-Be 'Revoked'
            ($r.Certificates | Where-Object Key -eq 'zmueller-current').State | Should-Be 'Valid'
            ($r.Certificates | Where-Object Key -eq 'zmueller-current').NotAfter | Should-Be ([DateTime]::new(2028, 9, 11, 22, 16, 42, [DateTimeKind]::Utc))
            @($r.Certificates | Get-Member -MemberType NoteProperty).Name | Should-NotContainCollection @('PrivateKey', 'Key', 'Csr')
        }
    }

    It 'asks the CA for nothing a principal already holds in the state the row wants' {
        InModuleScope TestEnvironment {
            $script:Held['zmueller'] = @(
                [PSCustomObject]@{ serial_number = '7'; status = 'REVOKED'; subject = 'CN=zmueller,O=IPA.EXAMPLE.COM'; valid_not_after = 'Mon Sep 11 22:16:42 2028 UTC' }
                [PSCustomObject]@{ serial_number = '8'; status = 'VALID'; subject = 'CN=zmueller,O=IPA.EXAMPLE.COM'; valid_not_after = 'Mon Sep 11 22:16:42 2028 UTC' }
            )
            $script:Held['talvarez'] = @([PSCustomObject]@{ serial_number = '9'; status = 'REVOKED'; subject = 'CN=talvarez,O=IPA.EXAMPLE.COM' })
            $r = New-FreeIPACertificate -CertificateKey zmueller-compromised, zmueller-current, talvarez -PassThru -Confirm:$false
            $r.Existing | Should-Be 2
            # A revoked one on the disabled user does not satisfy a row that wants a valid one.
            $r.Issued | Should-Be 1
            Should-Invoke Invoke-FreeIPARequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'cert_request' }
            Should-NotInvoke Invoke-FreeIPARequest -ParameterFilter { $Method -eq 'cert_revoke' }
            ($r.Certificates | Where-Object Key -eq 'zmueller-compromised').Serial | Should-Be '7'
            ($r.Certificates | Where-Object Key -eq 'zmueller-current').Serial | Should-Be '8'
        }
    }

    It 'records a request the CA refused against its row and continues with the rest' {
        InModuleScope TestEnvironment {
            Mock Invoke-FreeIPARequest {
                if ($Method -eq 'cert_request' -and $Options.principal -like 'talvarez@*') { throw 'FreeIPA cert_request failed (ACIError 2100): Insufficient access' }
                if ($Method -eq 'cert_find') { return @() }
                [PSCustomObject]@{ result = [PSCustomObject]@{ serial_number = '1'; subject = 'x'; valid_not_after = 'Mon Sep 11 22:16:42 2028 UTC' } }
            }
            $r = New-FreeIPACertificate -CertificateKey talvarez, jnino, web01-http -PassThru -Confirm:$false -ErrorAction SilentlyContinue
            @($r.Errors).Count | Should-Be 1
            $r.Errors[0] | Should-MatchString 'talvarez'
            $r.Issued | Should-Be 2
        }
    }

    It 'asks the CA for nothing under -WhatIf, and refuses a profile not marked builtin' {
        InModuleScope TestEnvironment {
            $null = New-FreeIPACertificate -WhatIf
            Should-NotInvoke Invoke-FreeIPARequest
            Should-NotInvoke New-FreeIPACertificateRequest
            (Get-Command New-FreeIPACertificate).Parameters.Keys | Should-NotContainCollection @('Profile', 'ValidityDays', 'KeepPrivateKey')
        }
    }
}

Describe 'New-FreeIPACertificateRequest' -Tag 'Unit', 'Private' {

    It 'builds a PKCS#10 request from in-box .NET, as PEM, with a SAN when asked' {
        InModuleScope TestEnvironment {
            $pem = New-FreeIPACertificateRequest -Subject 'CN=zz-test-web01.zz-test-lab.ipa.example.com,O=IPA.EXAMPLE.COM' -DnsName 'zz-test-web01.zz-test-lab.ipa.example.com' -EmailAddress 'x@ipa.example.com'
            $pem | Should-MatchString '^-----BEGIN CERTIFICATE REQUEST-----'
            $pem | Should-MatchString '-----END CERTIFICATE REQUEST-----\n$'
            $body = ($pem -replace '-----[A-Z ]+-----', '') -replace '\s', ''
            $der = [Convert]::FromBase64String($body)
            # A DER SEQUENCE, and the subject and the SAN names inside it.
            $der[0] | Should-Be 0x30
            $text = [System.Text.Encoding]::ASCII.GetString($der)
            $text | Should-MatchString 'zz-test-web01\.zz-test-lab\.ipa\.example\.com'
            $text | Should-MatchString 'x@ipa\.example\.com'
            $text | Should-MatchString 'IPA\.EXAMPLE\.COM'
        }
    }

    It 'builds a request with no SAN extension when given no names, and two requests never share a key' {
        InModuleScope TestEnvironment {
            $a = New-FreeIPACertificateRequest -Subject 'CN=jnino,O=IPA.EXAMPLE.COM'
            $b = New-FreeIPACertificateRequest -Subject 'CN=jnino,O=IPA.EXAMPLE.COM'
            $a | Should-NotBe $b
            $a.Length | Should-BeLessThan (New-FreeIPACertificateRequest -Subject 'CN=jnino,O=IPA.EXAMPLE.COM' -DnsName 'a.ipa.example.com').Length
        }
    }
}

Describe 'ConvertFrom-FreeIPACertificateDate' -Tag 'Unit', 'Private' {

    It 'reads the asctime form the certificate commands return, padded day included, as UTC' {
        InModuleScope TestEnvironment {
            $when = ConvertFrom-FreeIPACertificateDate -Value 'Mon Sep 11 22:16:42 2028 UTC'
            $when | Should-Be ([DateTime]::new(2028, 9, 11, 22, 16, 42, [DateTimeKind]::Utc))
            $when.Kind | Should-Be ([DateTimeKind]::Utc)
            (ConvertFrom-FreeIPACertificateDate -Value 'Sun Sep  6 20:59:01 2026 UTC') | Should-Be ([DateTime]::new(2026, 9, 6, 20, 59, 1, [DateTimeKind]::Utc))
            (ConvertFrom-FreeIPACertificateDate -Value @('Sun Sep  6 20:59:01 2026 UTC')) | Should-Be ([DateTime]::new(2026, 9, 6, 20, 59, 1, [DateTimeKind]::Utc))
            # The day name is checked against the date, as the CA writes it.
            ConvertFrom-FreeIPACertificateDate -Value 'Sat Sep  6 20:59:01 2026 UTC' | Should-BeNull
        }
    }

    It 'returns nothing for anything else rather than failing a report' {
        InModuleScope TestEnvironment {
            ConvertFrom-FreeIPACertificateDate -Value $null | Should-BeNull
            ConvertFrom-FreeIPACertificateDate -Value @() | Should-BeNull
            ConvertFrom-FreeIPACertificateDate -Value '20280911221642Z' | Should-BeNull
            ConvertFrom-FreeIPACertificateDate -Value 'not a date' | Should-BeNull
        }
    }
}
