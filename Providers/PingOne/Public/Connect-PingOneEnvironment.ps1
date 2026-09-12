function Connect-PingOneEnvironment {
    <#
    .SYNOPSIS
        Establishes the PingOne connection every other function in this provider uses

    .DESCRIPTION
        PingOne authenticates a worker application with a client id and secret, and that is the
        only credential this provider needs. The worker application is created by hand in the
        console, with its roles, before the first connect; this provider does not create it.

        Two things about that are easy to get wrong, and both are handled here rather than left
        to the caller.

        The token endpoint belongs to the environment the worker application LIVES in, not the
        one it manages. A trial hands you an Administrators environment and a sandbox, and the
        obvious thing to do - create the worker where the objects will go - is not what most
        people end up doing, because the console's application list opens on Administrators.
        Authenticating against the wrong one is refused with `invalid_client`, which is the same
        message you get for a disabled application and for a mistyped secret, so it sends people
        looking in the wrong place. -AuthEnvironmentId says where the application lives and
        defaults to -EnvironmentId, which is right when they are the same and harmless to state
        when they are not.

        The region is not derivable from an environment id. PingOne serves North America,
        Europe, Canada, Asia-Pacific and Australia from different hostnames, and asking the
        wrong one returns a 404 that looks like a missing environment. The console's own
        hostname is the reliable answer, so -Region is named rather than guessed, and the error
        below says which host was tried.

        The connection is validated before it is stored. A credential accepted here and refused
        on the first real call gives somebody an error about users when the problem is the
        credential, so the environment is read once up front - which also collects the name and
        licence the report and the seed both want.

        Prefix and EmailDomain are recorded on the connection rather than passed to every
        function. They are what teardown keys off, so setting them once removes the failure
        mode where an environment is seeded under one prefix and torn down under another.

    .PARAMETER EnvironmentId
        The environment to seed. A GUID, shown on the environment's home page in the console.

    .PARAMETER ClientId
        The worker application's client id. Also a GUID, and on a worker application it is the
        same value as the application's own id.

    .PARAMETER ClientSecret
        The worker application's secret, as a SecureString.

    .PARAMETER UseStoredSecret
        Read the secret from this machine's record for the environment instead of being given
        it. Written by -SaveSecret on an earlier connect.

    .PARAMETER SaveSecret
        Write the secret to this machine's record once the connection has been proved, so later
        runs can use -UseStoredSecret. Nothing is written if the connection fails.

    .PARAMETER AuthEnvironmentId
        The environment the worker application lives in, when that is not the one being seeded.
        Defaults to -EnvironmentId.

    .PARAMETER Region
        The region the tenant is served from. Defaults to NorthAmerica, which is where a trial
        lands.

    .PARAMETER Prefix
        Name prefix and seed tag for everything this module creates. Everything created and
        everything removed is scoped by it.

    .PARAMETER EmailDomain
        Domain for seeded usernames and emails. The default is under example.com, which RFC
        2606 reserves precisely so test data cannot deliver mail to a real recipient. Change it
        only if you own the domain you change it to.

    .PARAMETER PassThru
        Return the connection object.

    .OUTPUTS
        PSCustomObject describing the connection, when -PassThru is used.

    .EXAMPLE
        PS> $secret = Read-Host 'Worker secret' -AsSecureString
        PS> Connect-PingOneEnvironment -EnvironmentId 0e2469df-9492-43bf-b8d6-8b9023795e55 `
                -ClientId bb016fd3-0157-40ac-8ca3-74eda168d0d9 -ClientSecret $secret `
                -AuthEnvironmentId ed8e5fd7-15dc-4ac4-8665-6adb1b88ed51 -SaveSecret

        DESCRIPTION: First run, with the worker application living in the Administrators environment
        OUTPUT: Nothing, unless -PassThru is given
        USE CASE: Connecting to a trial, where the worker is usually not in the sandbox

    .EXAMPLE
        PS> Connect-PingOneEnvironment -EnvironmentId 0e2469df-... -ClientId bb016fd3-... `
                -UseStoredSecret -AuthEnvironmentId ed8e5fd7-...

        DESCRIPTION: Every run after that
        OUTPUT: Nothing
        USE CASE: The ordinary case, with nothing to paste

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

    .LINK
        New-PingOneEnvironment
        Get-PingOneEnvironmentReport
        Disconnect-PingOneEnvironment
    #>

    [CmdletBinding(DefaultParameterSetName = 'Secret')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$EnvironmentId,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'Secret')]
        [System.Security.SecureString]$ClientSecret,

        [Parameter(Mandatory = $true, ParameterSetName = 'Stored')]
        [switch]$UseStoredSecret,

        [Parameter(ParameterSetName = 'Secret')]
        [switch]$SaveSecret,

        [Parameter()]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$AuthEnvironmentId,

        [Parameter()]
        [ValidateSet('NorthAmerica', 'Europe', 'Canada', 'AsiaPacific', 'Australia')]
        [string]$Region = 'NorthAmerica',

        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,30}$|^[A-Za-z0-9][A-Za-z0-9_-]*[-_]$')]
        [string]$Prefix = $script:TestEnvironmentDefaultPrefix,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$EmailDomain = $script:PingOneDefaultSeedDomain,

        [Parameter()]
        [switch]$PassThru
    )

    $correlationId = [Guid]::NewGuid()
    Write-Verbose "Starting Connect-PingOneEnvironment - CorrelationId: $correlationId"

    if (-not $AuthEnvironmentId) { $AuthEnvironmentId = $EnvironmentId }

    $secret = $ClientSecret
    if ($UseStoredSecret) {
        $recordPath = Get-PingOneCredentialPath -EnvironmentId $EnvironmentId
        if (-not (Test-Path -LiteralPath $recordPath)) {
            throw ("No stored secret for environment $EnvironmentId at $recordPath. Connect once " +
                'with -ClientSecret and -SaveSecret first.')
        }
        $secret = (Get-Content -LiteralPath $recordPath -Raw).Trim() | ConvertTo-SecureString
    }

    $hosts = $script:PingOneRegionHost[$Region]

    # Held in a local until it is proved, so a failed connect cannot leave a half-built
    # connection in module scope for the next call to trip over.
    $candidate = @{
        EnvironmentId     = $EnvironmentId
        AuthEnvironmentId = $AuthEnvironmentId
        ClientId          = $ClientId
        ClientSecret      = $secret
        Region            = $Region
        ApiHost           = $hosts.Api
        AuthHost          = $hosts.Auth
        ConsoleHost       = $hosts.Console
        Prefix            = $Prefix
        EmailDomain       = $EmailDomain
        AccessToken       = $null
        TokenExpiresUtc   = $null
        TokenScopes       = @()
    }

    # The cheapest possible call that proves all three of the credential, the region and the
    # environment id at once.
    # Named in the absolute form below /v1, because the environment itself is the one thing
    # that is not a collection underneath the environment.
    try {
        $environment = Invoke-PingOneRequest -Method GET -Path "/environments/$EnvironmentId" `
            -Connection $candidate -ErrorAction Stop
    }
    catch {
        throw ("Could not read environment $EnvironmentId from $($hosts.Api): $($_.Exception.Message) " +
            "If the environment exists, check -Region - it defaults to NorthAmerica and the region " +
            'is not derivable from the id.')
    }

    $candidate['EnvironmentName'] = $environment.name
    $candidate['EnvironmentType'] = $environment.type
    $candidate['OrganizationId'] = $environment.organization.id
    $candidate['LicenseId'] = $environment.license.id

    $script:PingOneConnection = $candidate

    if ($SaveSecret) {
        $recordPath = Get-PingOneCredentialPath -EnvironmentId $EnvironmentId
        ConvertFrom-SecureString -SecureString $secret | Set-Content -LiteralPath $recordPath -Encoding utf8
        Write-Verbose "Wrote the worker secret to $recordPath"
    }

    Write-Verbose ("Connected to PingOne environment '{0}' ({1}) in {2}" -f
        $environment.name, $EnvironmentId, $Region)

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName        = 'PingOneConnection'
            EnvironmentId     = $EnvironmentId
            EnvironmentName   = $environment.name
            EnvironmentType   = $environment.type
            AuthEnvironmentId = $AuthEnvironmentId
            OrganizationId    = $environment.organization.id
            ClientId          = $ClientId
            Region            = $Region
            ApiHost           = $hosts.Api
            Prefix            = $Prefix
            EmailDomain       = $EmailDomain
        }
    }
}
