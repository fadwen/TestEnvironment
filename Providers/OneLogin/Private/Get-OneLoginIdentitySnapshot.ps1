function Get-OneLoginIdentitySnapshot {
    <#
    .SYNOPSIS
        Reads the seeded users of the account as identities Compare-TestEnvironment can match
    .DESCRIPTION
        The users teardown would find. The key is the username with the seed prefix stripped, so
        zz-test-jnino is jnino, the shared login. OneLogin keeps a first and a last name and no
        display name, so the display name is left empty and the comparison falls back to the parts
        rather than composing a name the account never stored: a composed one would put the family
        name last for a person whose name puts it first.

        Enabled means the account can be used: approved, and neither suspended nor never
        activated. OneLogin keeps those as two numbers, a state and a status, and a person who is
        rejected or suspended is as disabled as one switched off anywhere else.
    .OUTPUTS
        PSCustomObject with Provider, Target and Identities
    .EXAMPLE
        PS> (Get-OneLoginIdentitySnapshot).Identities.Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $connection = Get-OneLoginConnection
    $marker = Get-OneLoginSeedMarker -Prefix $connection.Prefix
    $unusable = @($script:OneLoginUserStatus['Suspended'], $script:OneLoginUserStatus['Unactivated'])
    $identities = foreach ($user in @(Get-OneLoginSeededObject -Type Users -Connection $connection)) {
        $login = [string]$user.username
        $key = $login
        if ($key.StartsWith($marker.Prefix, [StringComparison]::OrdinalIgnoreCase)) { $key = $key.Substring($marker.Prefix.Length) }
        $enabled = ([int]$user.state -eq $script:OneLoginUserState['Approved']) -and ($unusable -notcontains [int]$user.status)
        New-TestIdentity -Provider 'OneLogin' -Login $login -Key $key -GivenName ([string]$user.firstname) -Surname ([string]$user.lastname) -Enabled $enabled
    }
    [PSCustomObject]@{ Provider = 'OneLogin'; Target = $connection.Subdomain; Identities = @($identities) }
}
