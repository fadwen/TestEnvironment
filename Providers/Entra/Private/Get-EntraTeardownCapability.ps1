function Get-EntraTeardownCapability {
    <#
    .SYNOPSIS
        Works out, before anything is prompted for, which teardown layers this identity can remove

    .DESCRIPTION
        A teardown that asks the person to confirm each deletion and then fails each one with
        a 403 has told them nothing they could act on and cost them a keypress per object. The
        permission question can be answered up front, from two sources:

        - the token's own claims: 'roles' on an app-only token, 'scp' on a delegated one, and
          'wids' where the token carries directory roles
        - the identity's directory roles read from Graph, because a service principal that is
          a Global Administrator can delete everything while its token's roles claim says it
          can only read. That is documented in the README as the reason a claims-only check is
          a mistake, and it is why the roles are looked up rather than trusted absent.

        Each layer of the teardown is allowed if the identity holds any of the permissions that
        can delete that type, or any of the directory roles that can. Where neither source can
        be read - a token that is not a JWT, a Graph lookup that fails - the answer is unknown
        and the layer is allowed, because refusing to try on no evidence is worse than a failed
        delete that reports itself.

        Applications are the one layer with an in-between answer. Application.ReadWrite.OwnedBy
        permits deleting only applications the identity owns, so a caller holding that grant
        and nothing broader is told to filter by ownership rather than to skip the layer.

    .PARAMETER Connection
        The connection to judge. Defaults to the active one.

    .OUTPUTS
        EntraTeardownCapability with Known, IdentityKind, IdentityObjectId, Permissions,
        DirectoryRoles, Layers and ApplicationsOwnedOnly.

    .EXAMPLE
        PS> $capability = Get-EntraTeardownCapability

        DESCRIPTION: Judges the active connection
        OUTPUT: One Allowed flag and Reason per teardown layer
        USE CASE: The start of Remove-EntraEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('EntraTeardownCapability')]
    param(
        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }

    # --- The token's claims ------------------------------------------------------------------
    $claims = $null
    $token = [string]$Connection.AccessToken
    $segments = $token.Split('.')
    if ($segments.Count -ge 2) {
        try {
            $claims = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-TestBase64Url -Text $segments[1])) | ConvertFrom-Json
        }
        catch {
            Write-Verbose "Could not decode the token claims: $($_.Exception.Message)"
        }
    }

    $permissions = @()
    $tokenRoles = @()
    $identityKind = 'Unknown'
    if ($claims) {
        if ($claims.PSObject.Properties['roles'] -and $claims.roles) { $permissions = @($claims.roles); $identityKind = 'Application' }
        if ($claims.PSObject.Properties['scp'] -and $claims.scp) { $permissions = @([string]$claims.scp -split '\s+' | Where-Object { $_ }); $identityKind = 'User' }
        if ($claims.PSObject.Properties['wids'] -and $claims.wids) { $tokenRoles = @($claims.wids) }
    }
    if ($identityKind -eq 'Unknown' -and $Connection.AuthMode -eq 'DeviceCode') { $identityKind = 'User' }
    if ($identityKind -eq 'Unknown' -and $Connection.AuthMode -eq 'Certificate') { $identityKind = 'Application' }

    # --- The identity, and its directory roles from Graph -----------------------------------
    # Looked up rather than read from the token, because an app-only token does not carry the
    # roles its service principal holds, and those roles are what let a read-only-looking app
    # delete everything.
    $identityObjectId = $null
    $directoryRoles = @()
    $rolesKnown = $false
    try {
        if ($identityKind -eq 'User') {
            $me = Invoke-EntraRequest -Method GET -Path '/me' -Query @{ '$select' = 'id' } -Connection $Connection
            $identityObjectId = [string]$me.id
        }
        elseif ($Connection.ClientId) {
            $principal = @(Invoke-EntraRequest -Method GET -Path '/servicePrincipals' -Connection $Connection -Paginate -ConsistencyLevel `
                    -Query @{ '$filter' = "appId eq '$($Connection.ClientId)'"; '$select' = 'id' }) | Select-Object -First 1
            if ($principal) { $identityObjectId = [string]$principal.id }
        }

        if ($identityObjectId) {
            $container = if ($identityKind -eq 'User') { '/users' } else { '/servicePrincipals' }
            $memberships = @(Invoke-EntraRequest -Method GET -Connection $Connection -Paginate `
                    -Path "$container/$identityObjectId/transitiveMemberOf/microsoft.graph.directoryRole" `
                    -Query @{ '$select' = 'roleTemplateId,displayName' })
            $directoryRoles = @($memberships | ForEach-Object { [string]$_.roleTemplateId } | Where-Object { $_ })
            $rolesKnown = $true
        }
    }
    catch {
        Write-Verbose "Could not read the identity's directory roles, so they are treated as unknown: $($_.Exception.Message)"
    }
    $directoryRoles = @($directoryRoles + $tokenRoles | Sort-Object -Unique)
    if ($tokenRoles.Count -gt 0) { $rolesKnown = $true }

    $known = ($permissions.Count -gt 0) -or $rolesKnown

    # --- What each layer needs ----------------------------------------------------------------
    # Any one of the permissions, or any one of the directory roles, is enough. Template ids
    # are the well-known ones Entra uses for every tenant.
    $globalAdministrator = '62e90394-69f5-4237-9190-012177145e10'
    $privilegedRoleAdministrator = 'e8611ab8-c189-46e8-94e1-60213ab1f814'
    $conditionalAccessAdministrator = 'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9'
    $securityAdministrator = '194ae4cb-b126-40b2-bd5b-6091b380977d'
    $authenticationPolicyAdministrator = '0526716b-113d-4c15-b2c8-68e3c22b9f80'
    $applicationAdministrator = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'
    $cloudApplicationAdministrator = '158c047a-c907-4556-b7ef-446551a6b5f7'
    $userAdministrator = 'fe930be7-5e62-47db-91af-98c3a49a38b1'
    $groupsAdministrator = 'fdd7a751-b60b-444a-984c-02652fe8fa1c'
    $licenseAdministrator = '4d6ac14f-3453-41d0-bef9-a3e0c569773a'
    $cloudDeviceAdministrator = '7698a772-787b-4ac8-901f-60d6b08affd2'
    $intuneAdministrator = '3a2c62db-5318-420d-8d74-23affee5d9d5'

    $requirements = [ordered]@{
        ConditionalAccessPolicies = @{
            Permissions = @('Policy.ReadWrite.ConditionalAccess')
            Roles       = @($globalAdministrator, $securityAdministrator, $conditionalAccessAdministrator)
        }
        AuthenticationStrengths   = @{
            Permissions = @('Policy.ReadWrite.ConditionalAccess', 'Policy.ReadWrite.AuthenticationMethod')
            Roles       = @($globalAdministrator, $securityAdministrator, $conditionalAccessAdministrator, $authenticationPolicyAdministrator)
        }
        RoleEligibilities         = @{
            Permissions = @('RoleManagement.ReadWrite.Directory', 'RoleEligibilitySchedule.ReadWrite.Directory')
            Roles       = @($globalAdministrator, $privilegedRoleAdministrator)
        }
        DirectoryRoles            = @{
            Permissions = @('RoleManagement.ReadWrite.Directory')
            Roles       = @($globalAdministrator, $privilegedRoleAdministrator)
        }
        NamedLocations            = @{
            Permissions = @('Policy.ReadWrite.ConditionalAccess')
            Roles       = @($globalAdministrator, $securityAdministrator, $conditionalAccessAdministrator)
        }
        Licenses                  = @{
            Permissions = @('Group.ReadWrite.All', 'Directory.ReadWrite.All')
            Roles       = @($globalAdministrator, $groupsAdministrator, $userAdministrator, $licenseAdministrator)
        }
        Applications              = @{
            Permissions = @('Application.ReadWrite.All', 'Directory.ReadWrite.All')
            Roles       = @($globalAdministrator, $applicationAdministrator, $cloudApplicationAdministrator)
        }
        Devices                   = @{
            Permissions = @('Device.ReadWrite.All', 'Directory.ReadWrite.All', 'Directory.AccessAsUser.All')
            Roles       = @($globalAdministrator, $cloudDeviceAdministrator, $intuneAdministrator)
        }
        Groups                    = @{
            Permissions = @('Group.ReadWrite.All', 'Directory.ReadWrite.All')
            Roles       = @($globalAdministrator, $groupsAdministrator, $userAdministrator)
        }
        Users                     = @{
            Permissions = @('User.ReadWrite.All', 'User.DeleteRestore.All', 'Directory.ReadWrite.All')
            Roles       = @($globalAdministrator, $userAdministrator)
        }
        AdministrativeUnits       = @{
            Permissions = @('AdministrativeUnit.ReadWrite.All', 'Directory.ReadWrite.All')
            Roles       = @($globalAdministrator, $privilegedRoleAdministrator)
        }
    }

    $layers = [ordered]@{}
    foreach ($name in $requirements.Keys) {
        $need = $requirements[$name]
        $byPermission = @($need.Permissions | Where-Object { $permissions -contains $_ })
        $byRole = @($need.Roles | Where-Object { $directoryRoles -contains $_ })

        $allowed = $true
        $reason = 'unknown identity; attempting'
        if ($byPermission.Count -gt 0) { $reason = "permission $($byPermission[0])" }
        elseif ($byRole.Count -gt 0) { $reason = 'a directory role' }
        elseif ($known) {
            $allowed = $false
            $reason = "the token carries none of $($need.Permissions -join ', ') and the identity holds no directory role that permits it"
        }

        $layers[$name] = [PSCustomObject]@{ Allowed = $allowed; Reason = $reason }
    }

    # OwnedBy is a narrower yes for applications: not a reason to skip the layer, a reason to
    # filter it by ownership so nothing is prompted for that the delete would refuse anyway.
    $ownedOnly = $false
    if (-not $layers['Applications'].Allowed -and ($permissions -contains 'Application.ReadWrite.OwnedBy')) {
        $layers['Applications'] = [PSCustomObject]@{ Allowed = $true; Reason = 'permission Application.ReadWrite.OwnedBy, owned objects only' }
        $ownedOnly = $true
    }

    return [PSCustomObject]@{
        PSTypeName            = 'EntraTeardownCapability'
        Known                 = $known
        IdentityKind          = $identityKind
        IdentityObjectId      = $identityObjectId
        Permissions           = @($permissions | Sort-Object)
        DirectoryRoles        = $directoryRoles
        Layers                = $layers
        ApplicationsOwnedOnly = $ownedOnly
    }
}
