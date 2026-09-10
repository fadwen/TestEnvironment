function Connect-TestEnvironment {
    <#
    .SYNOPSIS
        Connects to an identity provider, and fixes which provider the session works against

    .DESCRIPTION
        The single entry point for every provider. Naming the provider once here is what lets
        everything afterwards - New-TestEnvironment, the report, teardown - be
        provider-agnostic: they read the active connection rather than being told again.

        Everything except -Provider is mirrored from the provider's own connect command once
        -Provider is known, so this function never has to restate what a provider needs.

        It was written the other way first, with a parameter set per provider and credential
        type, and that broke the moment a second provider arrived. The sets were all Entra's,
        so 'Connect-TestEnvironment -Provider AD' - which needs no credentials at all, because
        Active Directory uses the caller's own Windows identity - matched the default Entra set
        and demanded a TenantId, a ClientId and a certificate thumbprint that do not exist in
        that world. Reflecting instead means a provider that needs nothing asks for nothing,
        and adding a third provider changes no parameters here.

    .PARAMETER Provider
        Which identity provider to connect to. Everything else this command accepts depends on
        this, so supply it first when using tab completion.

    .OUTPUTS
        A provider connection object when -PassThru is supplied.

    .EXAMPLE
        PS> Connect-TestEnvironment -Provider AD

        DESCRIPTION: Imports RSAT, checks elevation and detects the domain
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: The normal path on a domain-joined machine

    .EXAMPLE
        PS> Connect-TestEnvironment -Provider Entra -TenantId <id> -ClientId <c> -CertificateThumbprint <t>

        DESCRIPTION: Connects app-only to Entra with a certificate
        OUTPUT: Nothing, unless -PassThru is supplied
        USE CASE: The normal path once an Entra service app has been bootstrapped

    .EXAMPLE
        PS> Connect-TestEnvironment -Provider Entra -TenantId <id> -Interactive
        PS> New-TestServiceApp

        DESCRIPTION: Signs a human in once so the module can create the app it uses afterwards
        OUTPUT: The device code to enter, then the connection
        USE CASE: First run against a new tenant

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('TestEnvironmentConnection')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('AD', 'Entra', 'Okta')]
        [string]$Provider,

        [Parameter()]
        [switch]$PassThru
    )

    dynamicparam {
        # $Provider is not bound as a variable yet - dynamicparam runs during binding - so it is
        # read from the partially bound parameters. Before it is supplied there is nothing to
        # mirror, which is why -Provider is the parameter that has to come first.
        $chosen = $PSBoundParameters['Provider']
        if (-not $chosen) { return [System.Management.Automation.RuntimeDefinedParameterDictionary]::new() }

        # PassThru is declared statically above, and re-declaring a parameter is an error
        # rather than an override.
        return Get-TestProviderParameter -CommandName ('Connect-{0}Environment' -f $chosen) -Exclude 'PassThru'
    }

    begin {
        if (-not $script:TestEnvironmentProvider.ContainsKey($Provider)) {
            Write-Error ("No provider called '$Provider' is loaded. Available: " +
                (($script:TestEnvironmentProvider.Keys | Sort-Object) -join ', ')) -ErrorAction Stop
            return
        }

        $target = 'Connect-{0}Environment' -f $Provider
        if (-not (Get-Command -Name $target -ErrorAction SilentlyContinue)) {
            Write-Error "The $Provider provider does not implement $target." -ErrorAction Stop
            return
        }
    }

    process {
        # Set before connecting rather than after, because a provider's connect logic can call
        # back through the shared dispatchers and those refuse to run without it. Cleared again
        # on failure, so a half-connected session cannot masquerade as a good one and send the
        # next command somewhere unexpected.
        $script:ActiveProvider = $Provider

        # Forwarded as a splat rather than rebuilt parameter by parameter. Rebuilding means
        # every new provider parameter has to be added in two places, and the one that gets
        # forgotten fails silently by simply not being passed on.
        $forward = @{}
        foreach ($key in $PSBoundParameters.Keys) {
            if ($key -in 'Provider', 'PassThru') { continue }
            $forward[$key] = $PSBoundParameters[$key]
        }
        $forward['PassThru'] = $true

        $connection = $null
        try {
            $connection = & $target @forward
        }
        catch {
            $script:ActiveProvider = $null
            throw
        }

        if (-not $connection) {
            $script:ActiveProvider = $null
            Write-Error "The $Provider provider did not return a connection." -ErrorAction Stop
            return
        }

        Write-Verbose "Connected through the $Provider provider"

        if ($PassThru) {
            return ($connection | Add-Member -NotePropertyName Provider -NotePropertyValue $Provider -Force -PassThru)
        }
    }
}
