function New-ADTestEdgeUser {
    <#
    .SYNOPSIS
        Creates a single edge case user account with a generated password

    .DESCRIPTION
        Creates one account for New-ADTestEdgeCase. Separate from New-ADTestUser, which is
        CSV-driven and creates the population; this makes individual accounts whose value is
        in one specific attribute being unusual - no UPN, a comma in the name, an expiring
        password - rather than in being part of a realistic organisation.

        Skips silently and reports false if the account already exists, so the caller stays
        re-runnable.

    .PARAMETER Name
        Common name for the account. May contain a comma; Active Directory escapes it.

    .PARAMETER SamAccountName
        sAMAccountName. Capped at 20 characters for user objects - a longer value fails with
        "The name provided is not a properly formed account name", which does not obviously
        mean "too long".

    .PARAMETER Path
        Distinguished name of the OU to create the account in.

    .PARAMETER Description
        Description text, used to record what makes this account unusual.

    .PARAMETER DomainDnsName
        DNS name of the domain, used to build the userPrincipalName. Resolved from the
        current domain when not supplied, which is what every caller in this module wants -
        passing it at each of the ten call sites only made those lines long enough to wrap.

    .PARAMETER Extra
        Additional New-ADUser parameters, merged over the defaults. Used for the account
        control flags that make an account interesting - PasswordNeverExpires,
        ChangePasswordAtLogon, SmartcardLogonRequired.

    .PARAMETER NoUserPrincipalName
        Creates the account with no userPrincipalName. New-ADUser supplies one when the
        parameter is omitted, so leaving it out is not enough to produce an account without.

    .EXAMPLE
        New-ADTestEdgeUser -Name 'EdgeCase No UPN' -SamAccountName 'EdgeCaseNoUpn' `
            -Path $edgeOU -Description 'No UPN' -DomainDnsName $domain.DNSName `
            -NoUserPrincipalName

        DESCRIPTION: Creates an account with no userPrincipalName
        OUTPUT: True

    .OUTPUTS
        System.Boolean

        True when an account was created, false when one already existed.

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 20)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Description,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DomainDnsName = (Get-ADTestDomain).DNSName,

        [Parameter()]
        [ValidateNotNull()]
        [hashtable]$Extra = @{},

        [Parameter()]
        [switch]$NoUserPrincipalName
    )

    if (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue) {
        Write-Verbose "User already exists: $SamAccountName"
        return $false
    }

    # Via the shared helper rather than an inline copy loop - see
    # ConvertTo-TestSecureString for what that conversion does and does not achieve.
    $plainPassword = New-TestPassword -Length 24
    $password = ConvertTo-TestSecureString -PlainText $plainPassword
    $plainPassword = $null

    $userParam = @{
        Name            = $Name
        SamAccountName  = $SamAccountName
        DisplayName     = $Name
        Path            = $Path
        Description     = $Description
        AccountPassword = $password
        Enabled         = $true
    }

    if (-not $NoUserPrincipalName) {
        $userParam['UserPrincipalName'] = "$SamAccountName@$DomainDnsName"
    }

    foreach ($key in $Extra.Keys) {
        $userParam[$key] = $Extra[$key]
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Create edge case user')) {
        New-ADUser @userParam
        return $true
    }

    return $false
}
