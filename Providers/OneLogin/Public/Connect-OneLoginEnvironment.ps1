function Connect-OneLoginEnvironment {
    <#
    .SYNOPSIS
        Establishes the OneLogin connection every other function in this provider uses

    .DESCRIPTION
        OneLogin authenticates an API credential - a client id and secret created under
        Developers, API Credentials in the admin portal - and that is the only credential this
        provider needs. The credential is created by hand, by an account owner or super user,
        before the first connect; this provider does not create it. Its scope has to be Manage
        All: the seed creates roles, apps, mappings and custom user fields as well as users, and
        Manage Users covers only the last.

        Every call goes to the account's own host, https://<subdomain>.onelogin.com, which serves
        both the token and the API whichever region the account is in, so there is no region to
        name. -Subdomain takes the bare name, the host or the portal URL, and keeps the name.

        The connection is validated before it is stored. A credential accepted here and refused
        on the first real call gives somebody an error about users when the problem is the
        credential, so a token is fetched and the API read once up front. A credential whose
        scope stops at reading is caught later, by the first write, with OneLogin's own message.

        Prefix and EmailDomain are recorded on the connection rather than passed to every
        function. They are what teardown keys off, so setting them once removes the failure mode
        where an account is seeded under one prefix and torn down under another.

    .PARAMETER Subdomain
        The account: 'contoso', 'contoso.onelogin.com' or 'https://contoso.onelogin.com/'.

    .PARAMETER ClientId
        The API credential's client id.

    .PARAMETER ClientSecret
        The API credential's client secret, as a SecureString.

    .PARAMETER UseStoredSecret
        Read the client id and secret from this machine's record for the account instead of
        being given them. Written by -SaveSecret on an earlier connect. Also answers to
        -UseStoredCredential, the name every provider shares for connecting with what it stored.

    .PARAMETER SaveSecret
        Write the client id and secret to this machine's record once the connection has been
        proved, so later runs can use -UseStoredSecret. Nothing is written if the connection
        fails.

    .PARAMETER UseSecretStore
        With -SaveSecret, keep the secret in a SecretStore vault rather than in the record.

    .PARAMETER VaultPassword
        The vault's password, when the secret is in a vault whose password is not a default.

    .PARAMETER Prefix
        Name prefix and seed tag for everything this module creates. Everything created and
        everything removed is scoped by it.

    .PARAMETER EmailDomain
        Domain for seeded usernames and emails. The default is under example.com, which RFC 2606
        reserves precisely so test data cannot deliver mail to a real recipient. Change it only if
        you own the domain you change it to.

    .PARAMETER PassThru
        Return the connection object.

    .OUTPUTS
        PSCustomObject describing the connection, when -PassThru is used.

    .EXAMPLE
        PS> $secret = Read-Host 'Client secret' -AsSecureString
        PS> Connect-TestEnvironment -Provider OneLogin -Subdomain contoso -ClientId 7f12... -ClientSecret $secret -SaveSecret

        DESCRIPTION: First run, saving the credential for later ones
        OUTPUT: Nothing, unless -PassThru is given
        USE CASE: Connecting to a new account

    .EXAMPLE
        PS> Connect-TestEnvironment -Provider OneLogin -Subdomain contoso -UseStoredCredential

        DESCRIPTION: Every run after that
        OUTPUT: Nothing
        USE CASE: The ordinary case, with nothing to paste

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        New-OneLoginEnvironment
        Get-OneLoginEnvironmentReport
        Disconnect-OneLoginEnvironment
    #>

    [CmdletBinding(DefaultParameterSetName = 'Secret')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Subdomain,

        [Parameter(Mandatory = $true, ParameterSetName = 'Secret')]
        [ValidatePattern('^[A-Za-z0-9]+$')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Secret')]
        [System.Security.SecureString]$ClientSecret,

        [Parameter(Mandatory = $true, ParameterSetName = 'Stored')]
        [Alias('UseStoredCredential')]
        [switch]$UseStoredSecret,

        [Parameter(ParameterSetName = 'Secret')]
        [switch]$SaveSecret,

        [Parameter(ParameterSetName = 'Secret')]
        [switch]$UseSecretStore,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$|^[A-Za-z0-9][A-Za-z0-9_-]*[-_]$')]
        [string]$Prefix = $script:TestEnvironmentDefaultPrefix,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$EmailDomain = $script:OneLoginDefaultSeedDomain,

        [Parameter()]
        [switch]$PassThru
    )

    $correlationId = [Guid]::NewGuid()
    Write-Verbose "Starting Connect-OneLoginEnvironment - CorrelationId: $correlationId"

    # 'https://contoso.onelogin.com/', 'contoso.onelogin.com' and 'contoso' all name contoso.
    $name = $Subdomain.Trim() -replace '^[A-Za-z]+://', ''
    $name = ($name -split '[/?#]')[0]
    $name = ($name -replace '\.onelogin\.com$', '').ToLowerInvariant()
    if ($name -notmatch '^[a-z0-9][a-z0-9-]*$') {
        throw "'$Subdomain' does not name a OneLogin account. Give the subdomain, as in https://<subdomain>.onelogin.com."
    }

    # Locals rather than the parameters: a parameter keeps its validation, and assigning the stored
    # id back to $ClientId would re-run the pattern against a value the caller never typed.
    $clientIdentifier = $ClientId
    $secret = $ClientSecret
    if ($UseStoredSecret) {
        $stored = Import-OneLoginCredential -Path (Get-OneLoginCredentialPath -Subdomain $name) -VaultPassword $VaultPassword
        $clientIdentifier = $stored.ClientId
        $secret = $stored.ClientSecret
    }

    # Held in a local until it is proved, so a failed connect cannot leave a half-built
    # connection in module scope for the next call to trip over.
    $candidate = @{
        Subdomain       = $name
        ApiHost         = '{0}.onelogin.com' -f $name
        ClientId        = $clientIdentifier
        ClientSecret    = $secret
        Prefix          = $Prefix
        EmailDomain     = $EmailDomain
        AccountId       = $null
        AccessToken     = $null
        TokenExpiresUtc = $null
    }

    # The token proves the credential; one read proves the API answers to it.
    try {
        $null = Invoke-OneLoginRequest -Method GET -Path 'roles' -Query @{ limit = 1 } -Connection $candidate -ErrorAction Stop
    }
    catch {
        throw ("Could not connect to OneLogin account '$name' at https://$($candidate.ApiHost): $($_.Exception.Message)")
    }

    $script:OneLoginConnection = $candidate

    if ($SaveSecret) {
        $plain = ConvertFrom-TestSecureString -SecureString $secret
        try {
            $null = Export-OneLoginCredential -Path (Get-OneLoginCredentialPath -Subdomain $name) -Subdomain $name `
                -ClientId $clientIdentifier -ClientSecret $plain -UseSecretStore:$UseSecretStore -VaultPassword $VaultPassword -Confirm:$false
        }
        finally {
            $plain = $null
        }
        Write-Verbose "Wrote the OneLogin credential record for $name"
    }

    Write-Verbose ("Connected to OneLogin account '{0}' (account id {1})" -f $name, $candidate.AccountId)

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName  = 'OneLoginConnection'
            Subdomain   = $name
            AccountId   = $candidate.AccountId
            ApiHost     = $candidate.ApiHost
            ClientId    = $clientIdentifier
            Prefix      = $Prefix
            EmailDomain = $EmailDomain
        }
    }
}
