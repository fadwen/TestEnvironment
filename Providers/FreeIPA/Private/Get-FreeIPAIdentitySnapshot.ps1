function Get-FreeIPAIdentitySnapshot {
    <#
    .SYNOPSIS
        Reads the seeded active users of the realm as identities Compare-TestEnvironment can match
    .DESCRIPTION
        The active users teardown would find, read with their detail so the display name and the
        lock state come back; staged and preserved users are left out, because neither can sign
        in anywhere and neither exists in the other providers as such. The key is the uid, which
        the seed never prefixes, so it is the shared login. Enabled is the inverse of nsaccountlock.
    .OUTPUTS
        PSCustomObject with Provider, Target and Identities
    .EXAMPLE
        PS> (Get-FreeIPAIdentitySnapshot).Identities.Count
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $connection = Get-FreeIPAConnection
    # FreeIPA returns every attribute as a list, even a single-valued one.
    $first = {
        param($value)
        if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } }
        elseif ($null -eq $value) { '' }
        else { [string]$value }
    }
    $identities = foreach ($user in @(Get-FreeIPASeededObject -Type Users -Detail -Connection $connection)) {
        $locked = $false
        if ($user.PSObject.Properties['nsaccountlock']) { $locked = ((& $first $user.nsaccountlock) -eq 'True') }
        New-TestIdentity -Provider 'FreeIPA' -Login (& $first $user.uid) -DisplayName (& $first $user.displayname) `
            -GivenName (& $first $user.givenname) -Surname (& $first $user.sn) -Enabled (-not $locked)
    }
    [PSCustomObject]@{ Provider = 'FreeIPA'; Target = $connection.BaseUrl; Identities = @($identities) }
}
