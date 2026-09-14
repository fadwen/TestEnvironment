function Get-OktaIdentitySnapshot {
    <#
    .SYNOPSIS
        Reads the seeded users of the org as identities Compare-TestEnvironment can match
    .DESCRIPTION
        The users teardown would find. The key is the login's local part, jnino from
        jnino@oktalab.example.com, which is the shared login every other provider keeps. Enabled
        is whether the status is ACTIVE; a suspended, staged or deprovisioned user is not.
    .OUTPUTS
        PSCustomObject with Provider, Target and Identities
    .EXAMPLE
        PS> (Get-OktaIdentitySnapshot).Identities.Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $connection = Get-OktaConnection
    $identities = foreach ($user in @(Get-OktaSeededUser -Prefix $connection.Prefix -EmailDomain $connection.EmailDomain)) {
        $login = [string]$user.profile.login
        New-TestIdentity -Provider 'Okta' -Login $login -Key (($login -split '@', 2)[0]) -DisplayName ([string]$user.profile.displayName) `
            -GivenName ([string]$user.profile.firstName) -Surname ([string]$user.profile.lastName) -Enabled ([string]$user.status -eq 'ACTIVE')
    }
    [PSCustomObject]@{ Provider = 'Okta'; Target = $connection.OrgUrl; Identities = @($identities) }
}
