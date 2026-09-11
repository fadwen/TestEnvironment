function Get-AuthentikManagedMapping {
    <#
    .SYNOPSIS
        Resolves the instance's own default property mappings by their managed identifiers

    .DESCRIPTION
        A provider created through the API carries no property mappings at all, where the
        admin UI would have selected the instance's defaults: the OpenID scopes on an OAuth2
        provider, the standard attributes on a SAML provider. A provider without them issues
        tokens with no claims and assertions with no attributes, and a client cannot sign in
        through it. So the seed attaches the same defaults the UI would, found by the managed
        identifier Authentik gives each of them, which is stable across instances where the
        primary key is not.

        A mapping the instance does not have is skipped with a verbose note rather than an
        error, because an instance whose defaults were removed is still an instance to seed.
        The lookup is cached on the connection for the session.

    .PARAMETER Kind
        Scope for OAuth2 and proxy providers, Saml for SAML providers.

    .PARAMETER Managed
        The managed identifiers to resolve, such as goauthentik.io/providers/oauth2/scope-openid.

    .PARAMETER Connection
        The connection to use. Defaults to the active one.

    .OUTPUTS
        System.String[]. The primary keys of the mappings found, in the order asked for.

    .EXAMPLE
        PS> Get-AuthentikManagedMapping -Kind Scope -Managed 'goauthentik.io/providers/oauth2/scope-openid'

        DESCRIPTION: Resolves the openid scope mapping
        OUTPUT: One UUID
        USE CASE: The property_mappings of a seeded OAuth2 provider

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Scope', 'Saml')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string[]]$Managed,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-AuthentikConnection }

    if (-not $Connection.ContainsKey('ManagedMappingCache')) { $Connection['ManagedMappingCache'] = @{} }
    $cache = $Connection.ManagedMappingCache

    if (-not $cache.ContainsKey($Kind)) {
        $path = switch ($Kind) {
            'Scope' { '/propertymappings/provider/scope/' }
            'Saml' { '/propertymappings/provider/saml/' }
        }
        $byManaged = @{}
        foreach ($mapping in @(Invoke-AuthentikRequest -Method GET -Path $path -Query @{ managed__isnull = 'false' } -Connection $Connection -Paginate)) {
            if ($mapping.managed) { $byManaged[[string]$mapping.managed] = [string]$mapping.pk }
        }
        $cache[$Kind] = $byManaged
    }

    $found = foreach ($id in $Managed) {
        if ($cache[$Kind].ContainsKey($id)) { $cache[$Kind][$id] }
        else { Write-Verbose "This instance has no managed $Kind mapping '$id'; the provider is created without it." }
    }
    return @($found)
}
