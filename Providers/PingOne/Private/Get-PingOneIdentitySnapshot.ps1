function Get-PingOneIdentitySnapshot {
    <#
    .SYNOPSIS
        Reads the seeded users of the environment as identities Compare-TestEnvironment can match
    .DESCRIPTION
        The users teardown would find. The key is the username with the seed prefix stripped, so
        zz-test-jnino is jnino, the shared login. PingOne keeps a given name and a family name and
        no display name, so the display name is left empty and the comparison falls back to the
        parts rather than composing a name the environment never stored: a composed one would put
        the family name last for a person whose name puts it first.
    .OUTPUTS
        PSCustomObject with Provider, Target and Identities
    .EXAMPLE
        PS> (Get-PingOneIdentitySnapshot).Identities.Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $connection = Get-PingOneConnection
    $marker = Get-PingOneSeedMarker -Prefix $connection.Prefix
    $identities = foreach ($user in @(Get-PingOneSeededObject -Type Users -Connection $connection)) {
        $login = [string]$user.username
        $key = $login
        if ($key.StartsWith($marker.Prefix, [StringComparison]::OrdinalIgnoreCase)) { $key = $key.Substring($marker.Prefix.Length) }
        New-TestIdentity -Provider 'PingOne' -Login $login -Key $key -GivenName ([string]$user.name.given) -Surname ([string]$user.name.family) -Enabled $user.enabled
    }
    [PSCustomObject]@{ Provider = 'PingOne'; Target = $connection.EnvironmentId; Identities = @($identities) }
}
