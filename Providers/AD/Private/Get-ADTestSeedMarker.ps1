function Get-ADTestSeedMarker {
    <#
    .SYNOPSIS
        Returns the shared seed marker for the active Active Directory connection

    .DESCRIPTION
        Core's marker, resolved from the connection's prefix, falling back to the module default
        when nothing is connected.

        The fallback is what makes this worth a function. This provider's seeding commands can
        be called individually, before Connect-ADEnvironment has recorded anything, and the unit
        tests mock the connection with only the fields the function under test reads. Asking
        Core directly for a marker built from an absent prefix throws a validation error about
        an empty string, which says nothing about the real problem and turns "this test did not
        set up a prefix" into fourteen unrelated failures.

    .OUTPUTS
        TestSeedMarker

    .EXAMPLE
        PS> (Get-ADTestSeedMarker).Prefix

        DESCRIPTION: The prefix every AD object except a human user account is named with
        OUTPUT: ZZ-TEST-
        USE CASE: Called wherever this provider builds a name or a description

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('TestSeedMarker')]
    param()

    $prefix = $null
    if ($script:ADConnection -and $script:ADConnection.PSObject.Properties['Prefix']) {
        $prefix = $script:ADConnection.Prefix
    }

    if ([string]::IsNullOrWhiteSpace($prefix)) {
        $prefix = $script:TestEnvironmentDefaultPrefix
    }

    return Get-TestSeedMarker -Prefix $prefix
}
