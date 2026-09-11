function Connect-FreeIPAEnvironment {
    <#
    .SYNOPSIS
        Connects to a FreeIPA realm and stores the connection for the session

    .DESCRIPTION
        FreeIPA authenticates API calls with a session opened by a password login. There are
        two ways to hold one: a credential for an administrator, which is the bootstrap, and
        the password of the service account New-FreeIPAServiceApp creates, which is the
        durable one and is read from the credential record on disk.

        The connection is proven before it is stored. The login has to succeed, then a ping,
        a whoami and an environment read have to answer, which catches a wrong URL, a bad
        password, a certificate the machine does not trust and a proxy in the way, and which
        tells the session the server's API version, the identity it is running as, and the
        realm's domain, which every seeded host name is written under. Storing first and
        failing later would leave a broken connection behind for the next command to trip
        over with an unrelated message.

        Two things about FreeIPA passwords are handled here rather than left to surprise. Any
        password an administrator sets is expired the moment it is set, so a fresh bootstrap
        credential cannot log in until it is changed: -NewPassword changes it as part of
        connecting. And the realm's policy expires the service account's password on its own
        schedule, so a service account whose password has expired is rotated to a new random
        one and the record rewritten, with a warning, rather than failing.

        A FreeIPA server almost always presents a certificate from the realm's own CA. Pass
        that CA's PEM with -CertificateAuthorityPath and the connection trusts exactly it and
        nothing else; the bootstrap writes it into the record so -ServiceAccount needs no path.
        Without either, the operating system's trust store decides.

    .PARAMETER BaseUrl
        The server URL, for example https://ipa.example.com. No path.

    .PARAMETER Credential
        A login and password. The bootstrap credential.

    .PARAMETER NewPassword
        With -Credential: the password to change to before logging in, for a credential whose
        password the realm has marked expired.

    .PARAMETER ServiceAccount
        Connect with the service account password from the credential record.

    .PARAMETER CredentialPath
        Where the credential record is, when not in the default location.

    .PARAMETER VaultPassword
        The SecretStore password, when the record's password is in a vault whose password is
        not a default.

    .PARAMETER CertificateAuthorityPath
        A PEM file holding the realm's certificate authority, to be trusted in place of the
        operating system's store. /etc/ipa/ca.crt on any enrolled host.

    .PARAMETER Prefix
        The naming prefix for everything the session creates. Must end in a hyphen or an
        underscore. Defaults to the module-wide ZZ-TEST-.

    .PARAMETER PassThru
        Returns the connection, without its password or client.

    .OUTPUTS
        PSCustomObject. The connection, when -PassThru is supplied.

    .EXAMPLE
        PS> Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -Credential (Get-Credential admin) -CertificateAuthorityPath ./ca.crt

        DESCRIPTION: Connects with an administrator's credential, trusting the realm's CA
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: The first session against a realm, before a service account exists

    .EXAMPLE
        PS> Connect-FreeIPAEnvironment -BaseUrl https://ipa.example.com -ServiceAccount

        DESCRIPTION: Connects with the stored service account password
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
    [CmdletBinding(DefaultParameterSetName = 'Credential')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^https?://')]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true, ParameterSetName = 'Credential')]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(ParameterSetName = 'Credential')]
        [System.Security.SecureString]$NewPassword,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServiceAccount')]
        [switch]$ServiceAccount,

        [Parameter(ParameterSetName = 'ServiceAccount')]
        [string]$CredentialPath,

        [Parameter(ParameterSetName = 'ServiceAccount')]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [string]$CertificateAuthorityPath,

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*[-_]$')]
        [string]$Prefix = $script:TestEnvironmentDefaultPrefix,

        [Parameter()]
        [switch]$PassThru
    )

    $normalisedUrl = $BaseUrl.TrimEnd('/')
    $sharedMarker = Get-TestSeedMarker -Prefix $Prefix
    $authType = $PSCmdlet.ParameterSetName

    $caCertificate = $null
    if (-not [string]::IsNullOrWhiteSpace($CertificateAuthorityPath)) {
        if (-not (Test-Path -LiteralPath $CertificateAuthorityPath)) {
            throw "No certificate authority file at $CertificateAuthorityPath."
        }
        $caCertificate = [System.IO.File]::ReadAllText($CertificateAuthorityPath)
        if ($caCertificate -notmatch '-----BEGIN CERTIFICATE-----') {
            throw "$CertificateAuthorityPath does not hold a PEM certificate."
        }
    }

    $username = $null
    $password = $null
    $resolvedCredentialPath = $null
    $record = $null

    if ($authType -eq 'ServiceAccount') {
        $resolvedCredentialPath = Get-FreeIPACredentialPath -BaseUrl $normalisedUrl -Path $CredentialPath
        $record = Import-FreeIPACredential -Path $resolvedCredentialPath -VaultPassword $VaultPassword
        $username = $record.Username
        $password = $record.Password
        if (-not $caCertificate -and $record.CaCertificate) { $caCertificate = $record.CaCertificate }
    }
    else {
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password
    }

    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) {
        Write-Error 'The credential has no login or no password.' -ErrorAction Stop
        return
    }

    $http = New-FreeIPAHttpClient -BaseUrl $normalisedUrl -CaCertificate $caCertificate

    $candidate = @{
        BaseUrl        = $normalisedUrl
        Username       = $username
        Password       = $password
        AuthType       = $authType
        Prefix         = $sharedMarker.Prefix
        SeedTag        = $sharedMarker.Tag
        SeedMarker     = '[{0}]' -f $sharedMarker.Tag
        Client         = $http.Client
        Cookies        = $http.Cookies
        CaCertificate  = $caCertificate
        CredentialPath = $resolvedCredentialPath
        Identity       = $username
        Domain         = $null
        Realm          = $null
        ApiVersion     = $null
        ConnectedAt    = Get-Date
    }

    try {
        $login = Connect-FreeIPASession -Connection $candidate

        if (-not $login.Success -and $login.Reason -eq 'password-expired') {
            if ($authType -eq 'ServiceAccount') {
                # The realm's policy expired it. Rotated rather than reported, because the
                # account is the module's own and the record is the only place the password
                # lives; the record is rewritten with the same protection it had.
                $fresh = New-TestPassword -Length 32
                Set-FreeIPAPassword -Connection $candidate -Username $username -OldPassword $password -NewPassword $fresh -Confirm:$false
                $candidate.Password = $fresh
                $exportArgs = @{
                    Path          = $resolvedCredentialPath
                    BaseUrl       = $normalisedUrl
                    Username      = $username
                    Password      = $fresh
                    CaCertificate = $caCertificate
                    Confirm       = $false
                }
                if ($record.Protection -eq 'SecretStore') {
                    $exportArgs['UseSecretStore'] = $true
                    $exportArgs['VaultName'] = $record.VaultName
                    if ($VaultPassword) { $exportArgs['VaultPassword'] = $VaultPassword }
                }
                $null = Export-FreeIPACredential @exportArgs
                Write-Warning "The realm had expired the service account's password. It was rotated and the record at $resolvedCredentialPath rewritten."
                $login = Connect-FreeIPASession -Connection $candidate
            }
            elseif ($NewPassword) {
                $plainNew = ConvertFrom-TestSecureString -SecureString $NewPassword
                Set-FreeIPAPassword -Connection $candidate -Username $username -OldPassword $password -NewPassword $plainNew -Confirm:$false
                $candidate.Password = $plainNew
                Write-Verbose "Changed the expired password of $username before connecting."
                $login = Connect-FreeIPASession -Connection $candidate
            }
            else {
                throw ("the password for '$username' has expired. FreeIPA expires every password an administrator " +
                    'sets, so a new credential has to change it before it can be used: pass -NewPassword to change it ' +
                    'as part of connecting, or change it with kinit or the web UI first.')
            }
        }

        if (-not $login.Success) {
            throw "FreeIPA rejected the credential for '$username' ($($login.Reason))."
        }

        # Proven, and learned from. The ping names the API version every later call sends;
        # whoami names the identity; env names the domain seeded hosts are written under.
        $ping = Invoke-FreeIPARequest -Method 'ping' -Connection $candidate
        if ($ping -and $ping.summary -and ([string]$ping.summary) -match 'API version (\d+\.\d+)') {
            $candidate.ApiVersion = $Matches[1]
        }

        $who = Invoke-FreeIPARequest -Method 'whoami' -Connection $candidate
        if ($who -and $who.arguments) { $candidate.Identity = [string](@($who.arguments)[0]) }

        try {
            $environment = Invoke-FreeIPARequest -Method 'env' -Arguments @('domain', 'realm') -Connection $candidate
            if ($environment -and $environment.result) {
                $candidate.Domain = [string]$environment.result.domain
                $candidate.Realm = [string]$environment.result.realm
            }
        }
        catch {
            Write-Verbose "Could not read the realm's environment: $($_.Exception.Message)"
        }
        if ([string]::IsNullOrWhiteSpace($candidate.Domain)) {
            # The server is normally a host inside the domain, so the domain is the name minus
            # its first label. A single-label host cannot be guessed and the connect fails
            # rather than seeding hosts under a name nobody chose.
            $serverHost = ([uri]$normalisedUrl).Host
            if ($serverHost -match '^[^.]+\.(.+\..+)$') {
                $candidate.Domain = $Matches[1]
                Write-Warning "The realm did not report its domain; hosts will be seeded under '$($candidate.Domain)', derived from the server name."
            }
            else {
                throw "the realm did not report its domain and it cannot be derived from '$serverHost'."
            }
        }
    }
    catch {
        $http.Client.Dispose()
        throw (New-Object System.Exception(
                "Could not authenticate to $normalisedUrl as ${username}: $($_.Exception.Message)", $_.Exception))
    }

    $script:FreeIPAConnection = $candidate

    Write-Verbose "Connected to $normalisedUrl as $($candidate.Identity) (API $($candidate.ApiVersion), domain $($candidate.Domain)), seeding under $($candidate.Prefix)"

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName     = 'FreeIPAConnection'
            BaseUrl        = $candidate.BaseUrl
            AuthType       = $candidate.AuthType
            Identity       = $candidate.Identity
            Domain         = $candidate.Domain
            Realm          = $candidate.Realm
            ApiVersion     = $candidate.ApiVersion
            Prefix         = $candidate.Prefix
            SeedTag        = $candidate.SeedTag
            PinnedCa       = [bool]$candidate.CaCertificate
            CredentialPath = $candidate.CredentialPath
            ConnectedAt    = $candidate.ConnectedAt
        }
    }
}
