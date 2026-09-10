function Split-EntraOwnedObject {
    <#
    .SYNOPSIS
        Separates the applications or service principals an identity owns from those it does not

    .DESCRIPTION
        Application.ReadWrite.OwnedBy lets an identity delete only the applications and
        service principals it owns. The grant is the permission the bootstrapped service app
        holds, deliberately, so a teardown running as that app can meet seeded applications it
        did not create - by a human, or by a service app since replaced - and cannot delete.
        Asking the person to confirm each of those and then failing each with a 403 is what
        this exists to prevent: the owners are read first, and the objects the identity does
        not own are set aside with a reason before anything is prompted for.

        An owners read that fails leaves the object in the owned list. Refusing to try on no
        evidence is worse than one failed delete that reports itself.

    .PARAMETER Object
        The applications or service principals to split, as Get-EntraSeededObject returned them.

    .PARAMETER Type
        Applications or ServicePrincipals; decides the owners path.

    .PARAMETER IdentityObjectId
        The object id of the connected identity, from Get-EntraTeardownCapability.

    .PARAMETER Connection
        The connection to read through. Defaults to the active one.

    .OUTPUTS
        PSCustomObject with Owned and Unowned, each an array of the input objects.

    .EXAMPLE
        PS> $split = Split-EntraOwnedObject -Object $applications -Type Applications -IdentityObjectId $capability.IdentityObjectId

        DESCRIPTION: Splits the seeded applications by whether the service app owns them
        OUTPUT: Owned and Unowned arrays
        USE CASE: The applications layer of Remove-EntraEnvironment under an OwnedBy grant

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Object = @(),

        [Parameter(Mandatory = $true)]
        [ValidateSet('Applications', 'ServicePrincipals')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$IdentityObjectId,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-EntraConnection }
    $path = if ($Type -eq 'Applications') { '/applications' } else { '/servicePrincipals' }

    $owned = [System.Collections.Generic.List[object]]::new()
    $unowned = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $Object) {
        try {
            $owners = @(Invoke-EntraRequest -Method GET -Path "$path/$($item.id)/owners" -Connection $Connection -Paginate -Query @{ '$select' = 'id' })
            if (@($owners | ForEach-Object { [string]$_.id }) -contains $IdentityObjectId) { $owned.Add($item) }
            else { $unowned.Add($item) }
        }
        catch {
            Write-Verbose "Could not read the owners of '$($item.displayName)'; attempting it anyway: $($_.Exception.Message)"
            $owned.Add($item)
        }
    }

    return [PSCustomObject]@{
        Owned   = $owned.ToArray()
        Unowned = $unowned.ToArray()
    }
}
