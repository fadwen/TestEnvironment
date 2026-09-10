function Get-AuthentikFlow {
    <#
    .SYNOPSIS
        Finds the flow a provider must reference for a given designation

    .DESCRIPTION
        An OAuth2 or proxy provider cannot be created without an authorization flow and an
        invalidation flow, given by primary key. A fresh Authentik instance ships defaults
        with well-known slugs, and an administrator may have replaced them. So the well-known
        slug is tried first, and if it is absent the first flow with the right designation is
        taken - which is what the admin interface offers too.

        Looked up per call and cached on the connection for the rest of the session, because
        every seeded provider needs the same two primary keys and the answer does not change
        while a seed runs.

    .PARAMETER Designation
        Which flow to find: authorization or invalidation.

    .PARAMETER Connection
        The connection to look through. Defaults to the active one.

    .OUTPUTS
        System.String. The flow's primary key, a UUID.

    .EXAMPLE
        PS> $authorization = Get-AuthentikFlow -Designation authorization

        DESCRIPTION: Resolves the authorization flow a new provider needs
        OUTPUT: The UUID of default-provider-authorization-implicit-consent, or the first authorization flow
        USE CASE: Creating an OAuth2 or proxy provider

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('authorization', 'invalidation')]
        [string]$Designation,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-AuthentikConnection }

    if (-not $Connection.ContainsKey('FlowCache')) { $Connection['FlowCache'] = @{} }
    if ($Connection.FlowCache.ContainsKey($Designation)) { return $Connection.FlowCache[$Designation] }

    $preferredSlug = switch ($Designation) {
        'authorization' { 'default-provider-authorization-implicit-consent' }
        'invalidation' { 'default-provider-invalidation-flow' }
    }

    $flow = $null
    $bySlug = @(Invoke-AuthentikRequest -Method GET -Path '/flows/instances/' `
            -Query @{ slug = $preferredSlug } -Connection $Connection -Paginate)
    if ($bySlug.Count -gt 0) { $flow = $bySlug[0] }

    if (-not $flow) {
        $byDesignation = @(Invoke-AuthentikRequest -Method GET -Path '/flows/instances/' `
                -Query @{ designation = $Designation } -Connection $Connection -Paginate)
        if ($byDesignation.Count -gt 0) { $flow = $byDesignation[0] }
    }

    if (-not $flow) {
        throw "No $Designation flow exists in this Authentik instance, so no provider can be created. Create one, or restore the default '$preferredSlug'."
    }

    Write-Verbose "Using $Designation flow '$($flow.slug)' ($($flow.pk))"
    $Connection.FlowCache[$Designation] = [string]$flow.pk
    return [string]$flow.pk
}
