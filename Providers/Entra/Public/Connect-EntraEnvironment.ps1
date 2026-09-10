function Connect-EntraEnvironment {
    <#
    .SYNOPSIS
        Establishes the certificate-authenticated Graph connection every other function uses

    .DESCRIPTION
        Authenticates app-only against Microsoft Graph using a certificate, and stores the
        resulting connection in module scope for the rest of the session.

        Certificate rather than client secret is the only supported option, and that is a
        deliberate constraint rather than an omission. A secret has to exist somewhere in
        plaintext for the caller to pass it in, which puts it in a script, a variable, or a
        transcript. A certificate's private key stays in the store, only a short-lived signed
        assertion crosses the wire, and nothing this module handles is worth stealing.

        Three things are settled here and then relied on everywhere else, because getting any
        of them wrong after objects exist is expensive:

        - The prefix. Every object this module creates carries it, and teardown will not
          touch an object without it. Changing the prefix between a seed and a teardown
          orphans everything the first run made.
        - The UPN suffix. Seed users are created on it, and it is the fallback proof of
          ownership if the seed tag is ever lost. It defaults to the tenant's onmicrosoft.com
          routing domain, which cannot receive external mail, so a seeded mailbox cannot
          reach a real recipient.
        - The tenant. Read back from Graph and reported, rather than echoed from the
          parameter, so a connection to the wrong directory is visible immediately instead of
          at the moment something is created in it.

        The credential is validated before it is stored. A connection object that exists but
        does not work is worse than no connection, because the failure then surfaces at the
        first seeding call rather than at the point the credential was supplied.

    .PARAMETER TenantId
        Directory (tenant) ID, or a verified domain name

    .PARAMETER ClientId
        Application (client) ID of the app registration to authenticate as

    .PARAMETER CertificateThumbprint
        SHA-1 thumbprint of a certificate in CurrentUser\My or LocalMachine\My

    .PARAMETER CertificatePath
        Path to a PFX file holding the certificate and its private key

    .PARAMETER CertificatePassword
        Password protecting the PFX file

    .PARAMETER Certificate
        An already-loaded certificate object

    .PARAMETER Prefix
        Namespace applied to every object created, and required for teardown to consider one
        of them ours. Must end in a separator so seeded names cannot run into real ones.

    .PARAMETER UpnSuffix
        Domain seeded users are created on. Defaults to the tenant's onmicrosoft.com routing
        domain, which is deliberate: it accepts no external mail.

    .PARAMETER GraphBaseUri
        Graph endpoint. Change only for a sovereign cloud.

    .PARAMETER PassThru
        Returns the connection summary

    .OUTPUTS
        EntraConnection when -PassThru is supplied

    .EXAMPLE
        PS> Connect-EntraEnvironment -TenantId b818de68-9112-40b3-adc2-6838048cd611 `
                -ClientId 895bcc2f-ad2f-4ec4-8dfe-310251b5e1a8 `
                -CertificateThumbprint 9FC871A73BCE94325FD5E05DA33CBFF651E0A467

        DESCRIPTION: Connects using a certificate already in the personal store
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: The normal path, run once at the start of a session

    .EXAMPLE
        PS> Connect-EntraEnvironment -TenantId $tenant -ClientId $app `
                -CertificatePath .\lab.pfx -CertificatePassword $pfxPassword -PassThru

        DESCRIPTION: Connects using a PFX rather than the certificate store
        OUTPUT: The connection summary, including the tenant name read back from Graph
        USE CASE: A build agent that receives the certificate as a file

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(DefaultParameterSetName = 'Thumbprint')]
    [OutputType('EntraConnection')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'UseSecretStore',
        Justification = 'Selects the Stored parameter set rather than being read in the body; the switch on ParameterSetName is what acts on it.')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Thumbprint')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter(ParameterSetName = 'Interactive')]
        [ValidateNotNullOrEmpty()]
        [string]$BootstrapClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',

        [Parameter(Mandatory = $true, ParameterSetName = 'Stored')]
        [switch]$UseSecretStore,

        [Parameter(ParameterSetName = 'Stored')]
        [System.Security.SecureString]$VaultPassword,

        [Parameter(Mandatory = $true, ParameterSetName = 'Thumbprint')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$CertificatePath,

        [Parameter(ParameterSetName = 'Path')]
        [securestring]$CertificatePassword,

        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter()]
        # Internal hyphens are admitted now, because the shared default carries one. Still ends
        # in a separator so a seeded name cannot run into a real one.
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*[-_]$')]
        [string]$Prefix = $script:TestEnvironmentDefaultPrefix,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$UpnSuffix,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$GraphBaseUri = 'https://graph.microsoft.com',

        [Parameter()]
        [switch]$PassThru
    )

    $resolvedCertificate = $null
    $resolvedClientId = $ClientId

    switch ($PSCmdlet.ParameterSetName) {
        'Thumbprint' { $resolvedCertificate = Get-TestCertificate -Thumbprint $CertificateThumbprint }
        'Path' { $resolvedCertificate = Get-TestCertificate -Path $CertificatePath -Password $CertificatePassword }
        'Object' { $resolvedCertificate = Get-TestCertificate -Certificate $Certificate }
        'Stored' {
            # The record is the authority on both which application to be and where its key
            # lives, so neither has to be typed. That is the whole point of having bootstrapped.
            $stored = Get-EntraStoredCredential -TenantId $TenantId -VaultPassword $VaultPassword
            $resolvedCertificate = $stored.Certificate
            $resolvedClientId = $stored.ClientId
            Write-Verbose "Using the stored credential for '$($stored.DisplayName)' (key in $($stored.KeyProtection))"
        }
    }

    # Built as a candidate and only promoted to $script:EntraConnection once it has proven it
    # can reach the tenant. Storing first would leave a broken connection behind on failure,
    # and the next command would report something unrelated.
    $candidate = @{
        TenantId       = $TenantId
        ClientId       = $resolvedClientId
        Certificate    = $resolvedCertificate
        AuthMode       = 'Certificate'
        RefreshToken   = $null
        GraphBaseUri   = $GraphBaseUri.TrimEnd('/')
        Prefix         = $Prefix
        UpnSuffix      = $UpnSuffix
        AccessToken    = $null
        TokenExpiresOn = $null
        TokenRoles     = @()
    }

    if ($Interactive) {
        # The bootstrap path. The token is the signed-in human's, not an application's, and it
        # is held in memory only - the certificate minted by New-EntraServiceApp is the
        # durable credential this exists to create.
        $candidate.AuthMode = 'DeviceCode'
        $candidate.ClientId = $BootstrapClientId

        $session = New-EntraDeviceCodeToken -TenantId $TenantId -ClientId $BootstrapClientId `
            -GraphBaseUri $candidate.GraphBaseUri

        $candidate.AccessToken = $session.AccessToken
        $candidate.RefreshToken = $session.RefreshToken
        $candidate.TokenExpiresOn = $session.ExpiresOn
        $candidate.TokenRoles = @(Get-EntraTokenRole -AccessToken $session.AccessToken)
    }
    else {
        Write-Verbose "Authenticating as $resolvedClientId against tenant $TenantId"
        $null = Get-EntraAccessToken -Connection $candidate
    }

    # Read the organisation back rather than trusting the parameter. A tenant id that is
    # merely well-formed authenticates against the wrong directory perfectly happily.
    $organization = $null
    try {
        $organization = (Invoke-EntraRequest -Method GET -Path '/organization' -Connection $candidate).value |
            Select-Object -First 1
    }
    catch {
        throw (New-Object System.Exception(
            "Authenticated as $ClientId but could not read /organization. The app needs at least " +
            "Organization.Read.All or Directory.Read.All: $($_.Exception.Message)", $_.Exception))
    }

    if (-not $organization) {
        Write-Error "Authenticated to tenant $TenantId but /organization returned nothing to identify it by." -ErrorAction Stop
        return
    }

    # The id from Graph, not the parameter. A domain name is a legal -TenantId and the rest of
    # the module builds URLs from this, so it has to be the resolved GUID either way.
    $candidate.TenantId = $organization.id
    $candidate.TenantName = $organization.displayName

    $verifiedDomains = @($organization.verifiedDomains)
    $candidate.VerifiedDomains = @($verifiedDomains | ForEach-Object { $_.name })

    if (-not $candidate.UpnSuffix) {
        # The routing domain, identified by isInitial rather than by matching on
        # '.onmicrosoft.com'. A tenant can hold several onmicrosoft.com domains and only one
        # of them is the initial one; picking by suffix match gets that wrong on exactly the
        # tenants where it matters.
        $initial = $verifiedDomains | Where-Object { $_.isInitial } | Select-Object -First 1
        if (-not $initial) {
            Write-Error ("No initial (onmicrosoft.com) domain found in tenant $($organization.displayName). " +
                "Pass -UpnSuffix explicitly to say which domain seeded users belong on.") -ErrorAction Stop
            return
        }
        $candidate.UpnSuffix = $initial.name
        Write-Verbose "Defaulted the seed UPN suffix to the routing domain $($initial.name)"
    }
    elseif ($candidate.VerifiedDomains -notcontains $candidate.UpnSuffix) {
        Write-Error ("$($candidate.UpnSuffix) is not a verified domain in tenant $($organization.displayName). " +
            "Graph rejects a user whose UPN suffix the tenant does not own. Verified: " +
            ($candidate.VerifiedDomains -join ', ')) -ErrorAction Stop
        return
    }

    $script:EntraConnection = $candidate

    Write-Verbose "Connected to $($candidate.TenantName) as $ClientId, seeding under $Prefix on $($candidate.UpnSuffix)"

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName            = 'EntraConnection'
            TenantId              = $candidate.TenantId
            TenantName            = $candidate.TenantName
            ClientId              = $candidate.ClientId
            AuthMode              = $candidate.AuthMode
            CertificateThumbprint = $resolvedCertificate.Thumbprint
            KeyProtection         = $(if ($stored) { $stored.KeyProtection } else { "None" })
            CertificateExpires    = $resolvedCertificate.NotAfter
            Prefix                = $candidate.Prefix
            UpnSuffix             = $candidate.UpnSuffix
            VerifiedDomains       = $candidate.VerifiedDomains
            GrantedRoles          = $candidate.TokenRoles
        }
    }
}
