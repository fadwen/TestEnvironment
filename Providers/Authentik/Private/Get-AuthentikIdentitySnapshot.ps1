function Get-AuthentikIdentitySnapshot {
    <#
    .SYNOPSIS
        Reads the seeded users of the instance as identities Compare-TestEnvironment can match
    .DESCRIPTION
        The users teardown would find, the module's own service account left out. The key is the
        username as stored, which the seed never prefixes, so it is the shared login. Authentik
        keeps one name field, so the display name is compared and there is no given name or
        surname to fall back to.
    .OUTPUTS
        PSCustomObject with Provider, Target and Identities
    .EXAMPLE
        PS> (Get-AuthentikIdentitySnapshot).Identities.Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $connection = Get-AuthentikConnection
    $identities = foreach ($user in @(Get-AuthentikSeededObject -Type Users -Connection $connection)) {
        New-TestIdentity -Provider 'Authentik' -Login ([string]$user.username) -DisplayName ([string]$user.name) -Enabled $user.is_active
    }
    [PSCustomObject]@{ Provider = 'Authentik'; Target = $connection.BaseUrl; Identities = @($identities) }
}
