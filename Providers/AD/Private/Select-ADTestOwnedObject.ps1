function Select-ADTestOwnedObject {
    <#
    .SYNOPSIS
        Filters directory objects down to the ones this module can prove it created

    .DESCRIPTION
        Ownership proof, applied between finding an object and deleting it.

        Being inside the seeded container is where teardown looks, but it is not proof of who
        put an object there. A person can move a real group into OU=ZZ-TEST-TestData, or create
        one there by hand, and until now teardown would have deleted it without comment - the
        sweeps were "everything under this SearchBase", full stop. The seed tag is what turns
        location into evidence, and this is where that evidence is checked.

        The Entra provider has had this the whole time and says so in the same words: an object
        whose name matches but whose tag is missing is left alone, loudly. This brings the AD
        provider to the same standard.

        Anything skipped is named, because silently declining to delete is its own kind of
        surprise - the caller asked for a teardown and should be told what survived it.

    .PARAMETER InputObject
        Directory objects, each read with adminDescription among its properties.

    .PARAMETER Kind
        What to call these in the warning, for example 'group'.

    .OUTPUTS
        The subset carrying the seed tag.

    .EXAMPLE
        PS> $groups | Select-ADTestOwnedObject -Kind group

        DESCRIPTION: Keeps only the groups this module created
        OUTPUT: The owned subset, with a warning naming each one skipped
        USE CASE: Every teardown sweep in Remove-ADEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Kind
    )

    begin {
        $tag = (Get-ADTestSeedMarker).Tag
    }

    process {
        foreach ($object in @($InputObject | Where-Object { $_ })) {
            if ($object.adminDescription -eq $tag) {
                $object
                continue
            }

            $name = if ($object.Name) { $object.Name } else { $object.DistinguishedName }
            Write-Warning ("The $Kind '$name' is inside the seeded container but does not carry " +
                "$tag in adminDescription, so this module cannot prove it created it. Leaving it alone.")
        }
    }
}
