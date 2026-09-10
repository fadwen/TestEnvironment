function Set-ADTestSeedTag {
    <#
    .SYNOPSIS
        Stamps the seed tag onto objects this module created but did not tag at creation

    .DESCRIPTION
        Every object the AD provider creates carries the seed tag in adminDescription, because
        teardown refuses to delete anything that does not. The main seeding paths set it in the
        creation call itself, which is the right place - the object is never untagged, not even
        for an instant.

        The edge cases are the exception. New-ADTestEdgeCase creates a dozen objects across
        several nested containers, some through helpers that take no attribute hashtable, and
        threading the tag through every one of those calls would leave a thirteenth to be
        forgotten later. Sweeping the subtree once, after the fact, is the version that cannot
        rot: an object added to that function tomorrow is tagged without anybody remembering to.

        Objects already carrying the tag are left alone rather than rewritten, so this is cheap
        to call twice.

    .PARAMETER SearchBase
        Distinguished name of a subtree to stamp, base included.

    .PARAMETER Identity
        Distinguished names to stamp individually, for objects that do not live in the subtree -
        a fine-grained password policy sits in the Password Settings Container, not with the
        objects it applies to.

    .OUTPUTS
        System.Int32, the number of objects stamped.

    .EXAMPLE
        PS> Set-ADTestSeedTag -SearchBase 'OU=EdgeCases,OU=ZZ-TEST-TestData,DC=ad,DC=contoso,DC=com'

        DESCRIPTION: Tags everything the edge cases created under their own container
        OUTPUT: The count stamped
        USE CASE: Called at the end of New-ADTestEdgeCase

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [string[]]$Identity
    )

    $tag = (Get-ADTestSeedMarker).Tag
    $stamped = 0

    $targets = [System.Collections.Generic.List[object]]::new()

    if ($SearchBase) {
        foreach ($object in @(Get-ADObject -Filter * -SearchBase $SearchBase -Properties adminDescription -ErrorAction SilentlyContinue)) {
            $targets.Add($object)
        }
    }

    foreach ($dn in @($Identity | Where-Object { $_ })) {
        $object = Get-ADObject -Identity $dn -Properties adminDescription -ErrorAction SilentlyContinue
        if ($object) { $targets.Add($object) }
    }

    foreach ($object in $targets) {
        if ($object.adminDescription -eq $tag) { continue }

        if ($PSCmdlet.ShouldProcess($object.DistinguishedName, "Stamp the seed tag $tag")) {
            try {
                Set-ADObject -Identity $object.DistinguishedName -Replace @{ adminDescription = $tag } -ErrorAction Stop
                $stamped++
            }
            catch {
                # A failure here costs ownership proof rather than the object, so it is worth
                # naming loudly: teardown will refuse to remove whatever was missed.
                Write-Warning ("Could not stamp the seed tag on $($object.DistinguishedName): " +
                    "$($_.Exception.Message). Teardown will not remove it.")
            }
        }
    }

    return $stamped
}
