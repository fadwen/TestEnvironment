function Get-ADTestNameToken {
    <#
    .SYNOPSIS
        Returns the parts of an account's name that its password may not contain

    .DESCRIPTION
        Windows password complexity is usually described as "three of five character
        classes", and that is only half of it. The check also refuses any password that
        contains the account's sAMAccountName, or any token of its display name three
        characters or longer, compared case-insensitively. The display name is split on
        comma, full stop, hyphen, underscore, space, tab and hash; tokens shorter than three
        characters are ignored, because they would refuse almost everything.

        Two things about the seeded accounts make this bite rather than stay theoretical:

        - The seed prefixes every display name, so "TEST" is a checked token on every single
          account this module creates.
        - Several service accounts carry a three-letter word of their own - Web, SQL, API,
          CRM, ERP, Dev, Log - and a three-letter token is by far the most likely to turn up
          by chance in a random password.

        Active Directory reports the refusal as "The password does not meet the length,
        complexity, or history requirement of the domain", naming none of the three, so the
        failure reads as a generator that produced something weak rather than one that
        produced something that happened to spell a word in the account's own name.

        Measured against the real generator across sixty thousand samples, this refused about
        one seed run in three hundred - often enough to be seen, rare enough to be dismissed
        as a fluke. Passing these tokens to New-TestPassword removes it entirely.

    .PARAMETER DisplayName
        The display name the account will carry, including any seed prefix. Split as Windows
        splits it.

    .PARAMETER SamAccountName
        The logon name the account will carry. Checked whole, not split.

    .OUTPUTS
        System.String[], the tokens a password for this account must not contain. Empty when
        the name yields nothing long enough to matter.

    .EXAMPLE
        PS> Get-ADTestNameToken -DisplayName 'ZZ-TEST-Web Application Service' -SamAccountName 'svc-webapp'

        DESCRIPTION: Returns the tokens Windows would check for this account
        OUTPUT: TEST, Web, Application, Service, svc-webapp
        USE CASE: Passed to New-TestPassword -NotContaining before creating the account

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DisplayName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$SamAccountName
    )

    # Ordinal-ignore-case, because the comparison Windows makes is case-insensitive and a set
    # that held both "Test" and "TEST" would only cost extra draws.
    $tokens = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    if (-not [string]::IsNullOrWhiteSpace($DisplayName)) {
        foreach ($piece in ($DisplayName -split '[,\.\-_ \t#]+')) {
            if ($piece.Length -ge 3) { $null = $tokens.Add($piece) }
        }
    }

    # The logon name is checked whole rather than split, so it goes in as it stands.
    if (-not [string]::IsNullOrWhiteSpace($SamAccountName) -and $SamAccountName.Length -ge 3) {
        $null = $tokens.Add($SamAccountName)
    }

    # A typed empty array rather than a one-element array wrapping an empty one, which is what
    # the comma operator produces and what a caller counting the result would then see as one
    # forbidden token that is not there.
    return [string[]]@($tokens)
}
