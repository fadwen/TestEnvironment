function Get-EntraIdentitySnapshot {
    <#
    .SYNOPSIS
        Reads the seeded members of the tenant as identities Compare-TestEnvironment can match
    .DESCRIPTION
        The users teardown would find, guests left out because an invited guest's login is
        minted by Entra and matches nothing anywhere else. The key is the UPN's local part with
        the seed prefix stripped, so ZZ-TEST-jnino@lab.example.com is jnino, which is what every
        other provider that keeps the shared logins calls the same person.
    .OUTPUTS
        PSCustomObject with Provider, Target and Identities
    .EXAMPLE
        PS> (Get-EntraIdentitySnapshot).Identities.Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection
    $identities = foreach ($user in @(Get-EntraSeededObject -Type Users -Connection $connection)) {
        if ($user.userType -eq 'Guest') { continue }
        $login = [string]$user.userPrincipalName
        $local = ($login -split '@', 2)[0]
        if ($local.StartsWith($marker.Prefix, [StringComparison]::OrdinalIgnoreCase)) { $local = $local.Substring($marker.Prefix.Length) }
        New-TestIdentity -Provider 'Entra' -Login $login -Key $local -DisplayName ([string]$user.displayName) `
            -GivenName ([string]$user.givenName) -Surname ([string]$user.surname) -Enabled $user.accountEnabled
    }
    [PSCustomObject]@{ Provider = 'Entra'; Target = $connection.TenantId; Identities = @($identities) }
}
