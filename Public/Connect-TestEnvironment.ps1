function Connect-TestEnvironment {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Connects to an identity provider, and fixes which provider the session works against
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
