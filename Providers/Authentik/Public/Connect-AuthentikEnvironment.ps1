function Connect-AuthentikEnvironment {
    <#
    .SYNOPSIS
        Connects to an Authentik instance and stores the connection for the session

    .DESCRIPTION
        Authentik authenticates API calls with a bearer token. There are two ways to hold
        one: an API token created for an administrator in the admin interface, which is the
        bootstrap credential, and the token of the service account New-AuthentikServiceApp
        creates, which is the durable one and is read from the credential record on disk.

        The connection is proven before it is stored. A request to the current-user endpoint
        has to succeed, which catches a wrong URL, a revoked token and a proxy in the way, and
        it names the identity the token belongs to so the connection can report who it is.
        Storing first and failing later would leave a broken connection behind for the next
        command to trip over with an unrelated message.

        The prefix and the email domain are fixed here for the session. Every object the seed
        creates carries the prefix in the form its type accepts, and every seeded user's email
        and every seeded application's URLs are written against the domain.

    .PARAMETER BaseUrl
        The instance URL, for example https://auth.example.com. No path.

    .PARAMETER ApiToken
        An API token, as a SecureString. The bootstrap credential.

    .PARAMETER ServiceAccount
        Connect with the service account token from the credential record.

    .PARAMETER CredentialPath
        Where the credential record is, when not in the default location.

    .PARAMETER VaultPassword
        The SecretStore password, when the token is in a vault whose password is not a default.

    .PARAMETER Prefix
        The naming prefix for everything the session creates. Must end in a hyphen or an
        underscore. Defaults to the module-wide ZZ-TEST-.

    .PARAMETER EmailDomain
        The domain seeded users' email addresses and seeded applications' URLs belong to.

    .PARAMETER PassThru
        Returns the connection, without its Authorization header.

    .OUTPUTS
        PSCustomObject. The connection, when -PassThru is supplied.

    .EXAMPLE
        PS> Connect-AuthentikEnvironment -BaseUrl https://auth.example.com -ApiToken $token

        DESCRIPTION: Connects with an administrator's API token
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: The first session against an instance, before a service account exists

    .EXAMPLE
        PS> Connect-AuthentikEnvironment -BaseUrl https://auth.example.com -ServiceAccount

        DESCRIPTION: Connects with the stored service account token
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: Every session after the bootstrap

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path to a credential record, not a credential.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ServiceAccount',
        Justification = 'Selects the parameter set; the set name is what the body switches on.')]
    [CmdletBinding(DefaultParameterSetName = 'ApiToken')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^https?://')]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true, ParameterSetName = 'ApiToken')]
        [System.Security.SecureString]$ApiToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServiceAccount')]
        [switch]$ServiceAccount,

        [Parameter(ParameterSetName = 'ServiceAccount')]
        [string]$CredentialPath,

        [Parameter(ParameterSetName = 'ServiceAccount')]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*[-_]$')]
        [string]$Prefix = $script:TestEnvironmentDefaultPrefix,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$EmailDomain = 'authentiklab.example.com',

        [Parameter()]
        [switch]$PassThru
    )

    $normalisedUrl = $BaseUrl.TrimEnd('/')
    $sharedMarker = Get-TestSeedMarker -Prefix $Prefix

    $token = $null
    $authType = $PSCmdlet.ParameterSetName
    $resolvedCredentialPath = $null
    $identityHint = $null

    if ($authType -eq 'ApiToken') {
        $token = ConvertFrom-TestSecureString -SecureString $ApiToken
    }
    else {
        $resolvedCredentialPath = Get-AuthentikCredentialPath -BaseUrl $normalisedUrl -Path $CredentialPath
        $credential = Import-AuthentikCredential -Path $resolvedCredentialPath -VaultPassword $VaultPassword
        $token = $credential.Token
        $identityHint = $credential.Username
    }

    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Error 'The token is empty.' -ErrorAction Stop
        return
    }

    $candidate = @{
        BaseUrl             = $normalisedUrl
        AuthorizationHeader = "Bearer $token"
        AuthType            = $authType
        Prefix              = $sharedMarker.Prefix
        EmailDomain         = $EmailDomain.TrimStart('@')
        SeedTag             = $sharedMarker.Tag
        SeedMarker          = '[{0}]' -f $sharedMarker.Tag
        CredentialPath      = $resolvedCredentialPath
        Identity            = $identityHint
        ConnectedAt         = Get-Date
    }

    # Proven before it is stored. The current-user endpoint needs nothing but a valid token
    # and says whose it is.
    try {
        $me = Invoke-AuthentikRequest -Method GET -Path '/core/users/me/' -Connection $candidate
        if ($me -and $me.user -and $me.user.username) {
            $candidate.Identity = [string]$me.user.username
        }
    }
    catch {
        throw (New-Object System.Exception(
            "Could not authenticate to $normalisedUrl as $authType`: $($_.Exception.Message)", $_.Exception))
    }

    $script:AuthentikConnection = $candidate

    Write-Verbose "Connected to $normalisedUrl as $($candidate.Identity), seeding under $($candidate.Prefix) on $($candidate.EmailDomain)"

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName     = 'AuthentikConnection'
            BaseUrl        = $candidate.BaseUrl
            AuthType       = $candidate.AuthType
            Identity       = $candidate.Identity
            Prefix         = $candidate.Prefix
            EmailDomain    = $candidate.EmailDomain
            SeedTag        = $candidate.SeedTag
            CredentialPath = $candidate.CredentialPath
            ConnectedAt    = $candidate.ConnectedAt
        }
    }
}
