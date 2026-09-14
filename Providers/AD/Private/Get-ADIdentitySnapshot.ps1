function Get-ADIdentitySnapshot {
    <#
    .SYNOPSIS
        Reads the seeded users of the domain as identities Compare-TestEnvironment can match
    .DESCRIPTION
        The users under the seed OU that carry the tag, the way teardown finds them. The key is
        the SAM account name, which in this data is first name and initial rather than the shared
        login the other providers use, so a comparison against another provider matches most of
        these people by display name; the display name is the one the seed wrote, from the same
        shared file as everywhere else.
    .OUTPUTS
        PSCustomObject with Provider, Target and Identities
    .EXAMPLE
        PS> (Get-ADIdentitySnapshot).Identities.Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $domain = Get-ADTestDomain
    $seedRoot = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
    $identities = @()
    # A search base that does not exist is an error to the AD cmdlets rather than an empty result.
    $rootExists = @(Get-ADOrganizationalUnit -Filter "Name -eq '$($script:ADTestRootName)'" -SearchBase $domain.DomainDN `
            -SearchScope OneLevel -ErrorAction Stop).Count -gt 0
    if ($rootExists) {
        $identities = foreach ($user in @(Get-ADUser -Filter '*' -SearchBase "OU=Users,$seedRoot" -Properties adminDescription, DisplayName, GivenName, Surname -ErrorAction Stop |
                    Select-ADTestOwnedObject -Kind user)) {
            New-TestIdentity -Provider 'AD' -Login ([string]$user.SamAccountName) -DisplayName ([string]$user.DisplayName) `
                -GivenName ([string]$user.GivenName) -Surname ([string]$user.Surname) -Enabled $user.Enabled
        }
    }
    [PSCustomObject]@{ Provider = 'AD'; Target = $domain.DNSName; Identities = @($identities) }
}
