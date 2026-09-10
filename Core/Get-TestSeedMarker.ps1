function Get-TestSeedMarker {
    <#
    .SYNOPSIS
        Returns the naming prefix and metadata every provider stamps on what it creates

    .DESCRIPTION
        One scheme for all three providers, so an object is recognisable as this module's work
        whichever directory it is sitting in.

        Each provider arrived with its own: Entra tagged descriptions with 'ENTRALAB-seed',
        Okta appended '[seed:OKTALAB]' and wrote a labSeedTag attribute, and Active Directory
        stamped nothing at all - it relied entirely on objects being inside OU=TestData, which
        says nothing once you are looking at the object rather than the tree. Three schemes meant
        three answers to "did we make this", and the AD answer was "only if you ask the right
        way".

        Everything derives from the prefix. Two settings that must agree for teardown to work
        are one setting too many, so the tag is not separately configurable.

        **The prefix goes on everything except people.** Groups, applications, devices,
        organisational units, network locations, policies and service accounts all take it.
        Human user accounts do not: the seeded people carry real names on purpose, because the
        same person exists in the AD and Entra labs and matching them is what makes hybrid
        identity testable. Ownership of a user is proved by its container and its seed tag
        instead, which is what those are for.

    .PARAMETER Prefix
        Naming prefix, including its trailing separator. Defaults to the module's own.

    .OUTPUTS
        TestSeedMarker with Prefix, Tag, Description and DescriptionPattern.

    .EXAMPLE
        PS> Get-TestSeedMarker

        DESCRIPTION: Returns the default marker
        OUTPUT: Prefix ZZ-TEST-, Tag ZZ-TEST-seed, and the description sentence
        USE CASE: Called by every provider function that creates or identifies an object

    .EXAMPLE
        PS> (Get-TestSeedMarker -Prefix 'LAB-').Tag

        DESCRIPTION: Derives the tag from a non-default prefix
        OUTPUT: LAB-seed
        USE CASE: A second lab in the same directory, kept separate from the first

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('TestSeedMarker')]
    param(
        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*[-_]$')]
        [string]$Prefix = $script:TestEnvironmentDefaultPrefix
    )

    $tag = '{0}seed' -f $Prefix

    [PSCustomObject]@{
        PSTypeName  = 'TestSeedMarker'
        Prefix      = $Prefix
        Tag         = $tag

        # The tag sits inside a sentence so the description still reads like a description in a
        # portal, where somebody will eventually be looking at it and wondering what created
        # this and whether they may delete it.
        Description = "Seeded by TestEnvironment. Safe to delete. [$tag]"

        # What teardown matches on. Kept beside the text it has to match, because a description
        # format and the pattern that recognises it are the classic pair to change one of.
        DescriptionPattern = '\[{0}\]' -f [regex]::Escape($tag)
    }
}
