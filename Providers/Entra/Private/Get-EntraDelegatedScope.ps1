function Get-EntraDelegatedScope {
    <#
    .SYNOPSIS
        Derives the delegated scopes an interactive session needs from the service app's permission list

    .DESCRIPTION
        The permissions the module needs are declared once, in Data\EntraServiceAppPermissions.csv,
        as the application permissions the bootstrapped service app is granted. An interactive
        session needs the same rights as delegated scopes, and most carry the same name. Two do
        not, and the difference is why this is derived rather than typed a second time:

        - Device.ReadWrite.All exists only as an application permission. The delegated way to
          delete a device is Directory.AccessAsUser.All.
        - Application.ReadWrite.OwnedBy is deliberately narrow for the service app, which
          should only ever touch the applications it made. A human running interactively is
          expected to be able to remove applications that identity did not make - it is the
          way to clear the ones an OwnedBy grant refuses - so the delegated form is
          Application.ReadWrite.All.

        openid and offline_access are added because the device-code flow needs the first to
        identify the user and the second to hand back a refresh token.

    .PARAMETER GraphBaseUri
        The Graph endpoint the scopes belong to. Resource-scoped names are returned bare; the
        device-code request prefixes them.

    .OUTPUTS
        System.String[]. The scopes, sorted, with openid and offline_access last.

    .EXAMPLE
        PS> Get-EntraDelegatedScope

        DESCRIPTION: Lists the delegated scopes an interactive session asks for
        OUTPUT: AdministrativeUnit.ReadWrite.All, Application.ReadWrite.All, ... openid, offline_access
        USE CASE: The default for Connect-EntraEnvironment -Interactive -Scope

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $delegatedFor = @{
        'Device.ReadWrite.All'          = 'Directory.AccessAsUser.All'
        'Application.ReadWrite.OwnedBy' = 'Application.ReadWrite.All'
    }

    $scopes = foreach ($permission in (Get-EntraSeedData -Name 'EntraServiceAppPermissions')) {
        $name = [string]$permission.Permission
        if ($delegatedFor.ContainsKey($name)) { $delegatedFor[$name] } else { $name }
    }

    return @(@($scopes | Sort-Object -Unique) + @('openid', 'offline_access'))
}
