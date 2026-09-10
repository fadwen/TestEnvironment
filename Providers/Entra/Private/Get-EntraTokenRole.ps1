function Get-EntraTokenRole {
    <#
    .SYNOPSIS
        Reads the application permissions out of an access token's roles claim

    .DESCRIPTION
        An app-only Graph token carries its granted application permissions in the 'roles'
        claim. Reading them locally is how this module can tell you what it is allowed to do
        before it tries, rather than discovering it one 403 at a time in the middle of a run.

        The claims segment is decoded, not verified. That is correct here and would not be
        anywhere else: the token was just issued to this process by Entra over TLS and is
        being used to describe itself, not to authorise anything. Nothing downstream trusts
        this output for an access decision.

        A token that grants nothing has no 'roles' claim at all rather than an empty one,
        which is worth knowing because it is what a brand new app registration with consent
        never granted looks like.

    .PARAMETER AccessToken
        The raw JWT

    .OUTPUTS
        System.String[]. The granted application permissions, sorted, or an empty array.

    .EXAMPLE
        PS> Get-EntraTokenRole -AccessToken $token

        DESCRIPTION: Lists the application permissions carried by the token
        OUTPUT: Directory.Read.All, Group.ReadWrite.All, User.ReadWrite.All
        USE CASE: Telling the caller up front which seed steps will be refused

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    $segments = $AccessToken.Split('.')
    if ($segments.Count -lt 2) {
        Write-Verbose "Access token is not a three-part JWT; cannot read its roles."
        return @()
    }

    try {
        $json = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-TestBase64Url -Text $segments[1]))
        $claims = $json | ConvertFrom-Json
    }
    catch {
        Write-Verbose "Could not decode the token claims: $($_.Exception.Message)"
        return @()
    }

    # Two different claims, because the two grant types describe permissions differently.
    # An app-only token carries 'roles' as an array of application permissions. A delegated
    # token carries 'scp' as a single SPACE-SEPARATED STRING of scopes, so reading only
    # 'roles' reports an interactive session as having no permissions at all.
    if ($claims.PSObject.Properties['roles'] -and $claims.roles) {
        return @($claims.roles | Sort-Object)
    }
    if ($claims.PSObject.Properties['scp'] -and $claims.scp) {
        return @([string]$claims.scp -split '\s+' | Where-Object { $_ } | Sort-Object)
    }

    return @()
}
