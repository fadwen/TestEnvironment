function Get-EntraBootstrapState {
    <#
    .SYNOPSIS
        Works out whether the tenant already has a service app, and whether this machine can use it

    .DESCRIPTION
        Answers the question a person has the moment an interactive sign-in succeeds: do I run
        New-TestServiceApp, or has that already been done? The answer depends on two things
        that live in different places, and either can be true without the other:

        - the tenant may hold a bootstrapped application, found by the seed prefix and the
          EntraEnvironmentServiceApp tag New-TestServiceApp stamps on it
        - this machine may hold a credential record for the tenant, written by the same
          command, naming an application and where its private key is

        The four combinations each call for a different next command, and a fifth case covers a
        delegated token that cannot list applications at all. The scenario is decided here and
        returned as data; Write-EntraBootstrapNextStep turns it into the banner a person sees.
        Splitting the two keeps the decision testable without capturing console output.

        A record whose client id matches no tagged application in the tenant is treated as
        stale, not as proof: the application it names was deleted or belongs to another tenant's
        record copied over. Connecting with it would fail at token time with a message about
        the credential, which is the least helpful place to learn this.

    .PARAMETER Connection
        The connection to look through. Defaults to the active one.

    .OUTPUTS
        EntraBootstrapState. Scenario is one of ReadyToConnect, AppWithoutCredential,
        StaleRecord, NothingYet or Unknown, and Commands holds the exact commands to run next.

    .EXAMPLE
        PS> Get-EntraBootstrapState

        DESCRIPTION: Reads the tenant and the local record and names the scenario
        OUTPUT: An EntraBootstrapState with the next commands filled in
        USE CASE: Called by Connect-EntraEnvironment after an interactive sign-in

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('EntraBootstrapState')]
    param(
        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) {
        $Connection = Get-EntraConnection
    }

    $marker = Get-EntraSeedMarker -Connection $Connection
    $tenantId = $Connection.TenantId

    # --- The tenant ------------------------------------------------------------------------
    # The same discovery Get-EntraSeededObject uses to EXCLUDE the service app from teardown,
    # run here to find it. Filtered on the prefix server-side and on the tag client-side,
    # because a bootstrap given a custom -DisplayName still carries the tag.
    $applications = @()
    $tenantChecked = $true
    $checkError = $null
    try {
        $candidates = @(Invoke-EntraRequest -Method GET -Path '/applications' -Connection $Connection `
                -Paginate -ConsistencyLevel -Query @{
                    '$filter' = "startswith(displayName,'$($marker.Prefix.Replace("'", "''"))')"
                    '$select' = 'id,appId,displayName,tags'
                })
        $applications = @($candidates | Where-Object { @($_.tags) -contains 'EntraEnvironmentServiceApp' } |
                ForEach-Object { [PSCustomObject]@{ DisplayName = $_.displayName; ClientId = $_.appId; Id = $_.id } })
    }
    catch {
        # A delegated token without Application.Read.All lands here. Not knowing is a
        # scenario of its own, not a failure of the connect that just succeeded.
        $tenantChecked = $false
        $checkError = $_.Exception.Message
    }

    # --- This machine ----------------------------------------------------------------------
    $recordPath = Get-TestCredentialPath -TenantId $tenantId
    $record = $null
    if (Test-Path -LiteralPath $recordPath) {
        try {
            $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            Write-Verbose "The credential record at $recordPath could not be read: $($_.Exception.Message)"
        }
    }

    $keyProtection = $null
    if ($record) {
        $keyProtection = if ($record.PSObject.Properties['keyProtection'] -and $record.keyProtection) {
            $record.keyProtection
        }
        else { 'CertificateStore' }
    }

    $recordMatches = [bool]($record -and ($applications.ClientId -contains $record.clientId))

    # --- The scenario ----------------------------------------------------------------------
    $connectCommand = if ($record -and $keyProtection -eq 'SecretStore') {
        "Connect-TestEnvironment -Provider Entra -TenantId $tenantId -UseSecretStore"
    }
    elseif ($record) {
        "Connect-TestEnvironment -Provider Entra -TenantId $tenantId -ClientId $($record.clientId) -CertificateThumbprint $($record.certificateThumbprint)"
    }
    else { $null }

    $scenario = if (-not $tenantChecked) { 'Unknown' }
    elseif ($recordMatches) { 'ReadyToConnect' }
    elseif ($applications.Count -gt 0) { 'AppWithoutCredential' }
    elseif ($record) { 'StaleRecord' }
    else { 'NothingYet' }

    $commands = switch ($scenario) {
        'ReadyToConnect' {
            @($connectCommand, 'Get-TestServiceApp -TestCredential')
        }
        'AppWithoutCredential' {
            # -Force, because the application exists and New-TestServiceApp refuses to replace
            # one without it. The private key it was created with is not on this machine, so
            # replacing it is the only way to a credential that works here.
            @('New-TestServiceApp -Force')
        }
        'StaleRecord' {
            @('New-TestServiceApp')
        }
        'NothingYet' {
            @('New-TestServiceApp', 'New-TestServiceApp -UseSecretStore')
        }
        'Unknown' {
            if ($connectCommand) { @($connectCommand, 'New-TestServiceApp -Force') }
            else { @('New-TestServiceApp', 'New-TestServiceApp -Force') }
        }
    }

    return [PSCustomObject]@{
        PSTypeName         = 'EntraBootstrapState'
        Scenario           = $scenario
        TenantId           = $tenantId
        TenantName         = $Connection.TenantName
        TenantChecked      = $tenantChecked
        CheckError         = $checkError
        Applications       = @($applications)
        RecordPath         = $recordPath
        RecordExists       = [bool]$record
        RecordClientId     = $(if ($record) { $record.clientId } else { $null })
        RecordMatchesApp   = $recordMatches
        KeyProtection      = $keyProtection
        VaultName          = $(if ($record -and $record.PSObject.Properties['vaultName']) { $record.vaultName } else { $null })
        Commands           = @($commands)
    }
}
