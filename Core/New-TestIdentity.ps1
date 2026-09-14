function New-TestIdentity {
    <#
    .SYNOPSIS
        Shapes one seeded person the way Compare-TestEnvironment reads them, whichever provider held them
    .DESCRIPTION
        Every Get-<Provider>IdentitySnapshot returns a list of these, so the comparison never has to
        know where a person came from. The Key is the login with whatever the provider added
        stripped off, lower-cased: the seed prefix from a PingOne username, the UPN suffix from an
        Entra one, the email domain from an Okta login. DisplayName is $null where the provider
        keeps no such field, which is how the comparison knows to fall back to the given name and
        surname rather than compose a name the provider never stored.
    .PARAMETER Provider
        The provider the person was read from
    .PARAMETER Login
        The login as the provider holds it
    .PARAMETER Key
        The login with the provider's additions stripped; defaults to the lower-cased login
    .PARAMETER DisplayName
        The display name as stored, or nothing when the provider has no such field
    .PARAMETER GivenName
        The given name as stored, where the provider has one
    .PARAMETER Surname
        The surname as stored, where the provider has one
    .PARAMETER Enabled
        Whether the account can sign in
    .OUTPUTS
        PSCustomObject typed TestIdentity
    .EXAMPLE
        PS> New-TestIdentity -Provider Entra -Login 'ZZ-TEST-jnino@lab.example.com' -Key 'jnino' -DisplayName $user.displayName -Enabled $user.accountEnabled
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an object in memory and changes nothing outside it.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Login,

        [Parameter()]
        [AllowEmptyString()]
        [string]$Key,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$DisplayName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$GivenName,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Surname,

        [Parameter()]
        [AllowNull()]
        [object]$Enabled
    )

    if (-not $Key) { $Key = $Login }
    $enabledValue = $null
    if ($null -ne $Enabled) { $enabledValue = [bool]$Enabled }

    return [PSCustomObject]@{
        PSTypeName  = 'TestIdentity'
        Provider    = $Provider
        Key         = $Key.ToLowerInvariant()
        Login       = $Login
        DisplayName = $(if ($DisplayName) { $DisplayName } else { $null })
        GivenName   = $(if ($GivenName) { $GivenName } else { $null })
        Surname     = $(if ($Surname) { $Surname } else { $null })
        Enabled     = $enabledValue
    }
}
