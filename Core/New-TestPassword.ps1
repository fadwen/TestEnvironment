function New-TestPassword {
    <#
    .SYNOPSIS
        Generates a random password that satisfies typical directory complexity rules

    .DESCRIPTION
        Seeded accounts need a password because no directory will create a user without
        one. Nothing is expected to sign in with it, so it is generated, used once, and never
        returned to the caller or written anywhere.

        Randomness comes from RandomNumberGenerator rather than Get-Random. Get-Random is
        seeded from the system clock and is not a cryptographic source; two accounts created
        in the same tick can receive the same password. That is an unimportant weakness for a
        lab account and a habit worth not forming, and the cryptographic source costs nothing
        here.

        The character selection avoids the modulo bias that comes from taking a random byte
        modulo the alphabet length, by rejecting the values in the final incomplete block.
        One guaranteed character is drawn from each of the four required classes and the
        result is shuffled, because a password whose first four characters are always
        upper, lower, digit, symbol is a pattern.

    .PARAMETER Length
        Password length. Most directories cap this well above the default here, which is
        comfortably above any complexity floor.

    .PARAMETER NotContaining
        Substrings the password must not contain, compared case-insensitively. A candidate
        holding any of them is discarded and another is drawn.

        This exists for one specific rule that is easy to forget. Windows password complexity
        does not only count character classes: it also refuses any password containing the
        account's sAMAccountName, or any token of its display name three characters or longer,
        where the display name is split on comma, full stop, hyphen, underscore, space, tab
        and hash. A seeded service account called "ZZ-TEST-Web Application Service" therefore
        rejects any password containing "Web" - or "TEST", which the seed prefix puts on every
        account - and Active Directory reports it as "the password does not meet the length,
        complexity, or history requirement of the domain", naming none of the three.

        Measured against the real generator, that refused roughly one seed run in three
        hundred, which is frequent enough to be seen and rare enough to look like something
        else. Callers creating directory accounts should pass the tokens of the name they are
        about to use.

    .OUTPUTS
        System.String

    .EXAMPLE
        PS> $password = New-TestPassword

        DESCRIPTION: Generates a 32-character password meeting directory complexity requirements
        OUTPUT: A random string
        USE CASE: Called once per seeded user, and discarded immediately afterwards

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Changes no state. It computes a value in memory and returns it; the New verb describes constructing an object, not modifying anything.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateRange(16, 128)]
        [int]$Length = 32,

        [Parameter()]
        [string[]]$NotContaining = @()
    )

    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digit = '23456789'
    # Deliberately narrow. Directories accept a wider set, but these survive being pasted through
    # a shell, a CSV and a JSON body without one of them needing to be escaped.
    $symbol = '!#$%*+-=?@'
    $all = $upper + $lower + $digit + $symbol

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $pick = {
            param([string]$Alphabet)

            # Reject sampling: bytes at or above the largest exact multiple of the alphabet
            # length are discarded, so every character is equally likely.
            $limit = 256 - (256 % $Alphabet.Length)
            $byte = [byte[]]::new(1)
            do { $rng.GetBytes($byte) } while ($byte[0] -ge $limit)
            return $Alphabet[$byte[0] % $Alphabet.Length]
        }

        # Bounded, because a caller could ask for something unsatisfiable - a forbidden
        # substring of one character, say - and an unbounded loop would hang a seed rather
        # than say so. At the real rates involved a second attempt is already vanishingly
        # unlikely, so a ceiling this high only ever catches a mistake in the request.
        $attemptLimit = 100

        for ($attempt = 1; $attempt -le $attemptLimit; $attempt++) {
            $characters = [System.Collections.Generic.List[char]]::new()
            foreach ($class in $upper, $lower, $digit, $symbol) {
                $characters.Add((& $pick $class))
            }
            while ($characters.Count -lt $Length) {
                $characters.Add((& $pick $all))
            }

            # Fisher-Yates, so the guaranteed characters are not always in the first four
            # positions. The swap index comes from the same unbiased source.
            for ($i = $characters.Count - 1; $i -gt 0; $i--) {
                $limit = 256 - (256 % ($i + 1))
                $byte = [byte[]]::new(1)
                do { $rng.GetBytes($byte) } while ($byte[0] -ge $limit)
                $j = $byte[0] % ($i + 1)

                $swap = $characters[$i]
                $characters[$i] = $characters[$j]
                $characters[$j] = $swap
            }

            $candidate = -join $characters

            $clash = $null
            foreach ($forbidden in $NotContaining) {
                if ([string]::IsNullOrEmpty($forbidden)) { continue }
                if ($candidate.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $clash = $forbidden
                    break
                }
            }

            if (-not $clash) { return $candidate }

            Write-Verbose "Regenerating: the candidate contained '$clash' (attempt $attempt)"
        }

        throw ("Could not generate a password avoiding all $($NotContaining.Count) forbidden " +
            "substrings in $attemptLimit attempts. Check that they are not so short or so many " +
            'that no password of this length could satisfy them.')
    }
    finally {
        $rng.Dispose()
    }
}
