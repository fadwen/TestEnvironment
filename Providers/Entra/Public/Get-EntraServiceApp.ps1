function Get-EntraServiceApp {
    <#
    .SYNOPSIS
        Reports the bootstrapped service app, and whether its credential still works

    .DESCRIPTION
        Answers the question you actually have after a bootstrap: what am I meant to connect
        as, and does it still work.

        Both halves are checked independently, because they fail apart. The record on disk says
        which application and which certificate; the tenant says whether the application still
        exists and what it is consented for; the certificate store says whether the private key
        is still here. Any one of the three can be missing while the others look fine - a
        certificate deleted from the store leaves a perfectly valid application nobody can
        authenticate as, and an application deleted in the portal leaves a record and a
        certificate that point at nothing.

        The certificate is never exported and its private key is never returned. There is
        nothing here that would be dangerous in a transcript.

    .PARAMETER TenantId
        Which tenant's record to read. Defaults to the connected tenant.

    .PARAMETER TestCredential
        Attempts a token request with the stored certificate and reports whether it worked

    .OUTPUTS
        EntraServiceAppStatus

    .EXAMPLE
        PS> Get-EntraServiceApp -TestCredential

        DESCRIPTION: Reports what is stored and proves the credential still authenticates
        OUTPUT: The client id, thumbprint, granted permissions and a CredentialWorks flag
        USE CASE: Working out why a connection stopped working

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType('EntraServiceAppStatus')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$TestCredential
    )

    if (-not $TenantId) {
        $connection = Get-EntraConnection
        $TenantId = $connection.TenantId
    }

    $recordPath = Get-TestCredentialPath -TenantId $TenantId
    if (-not (Test-Path -LiteralPath $recordPath)) {
        Write-Warning ("No credential record for tenant $TenantId at $recordPath. Run New-TestServiceApp " +
            "after connecting with -Interactive.")
        return
    }

    $record = $null
    try {
        $record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Error "The credential record at $recordPath could not be read: $($_.Exception.Message)" -ErrorAction Stop
        return
    }

    # Records written before the vault path existed carry no keyProtection and mean the store.
    $protection = if ($record.PSObject.Properties['keyProtection'] -and $record.keyProtection) {
        $record.keyProtection
    }
    else { 'CertificateStore' }

    # The private key, checked separately from the record that names it, and looked for where
    # the record says it is rather than always in the store.
    $certificate = $null
    try {
        if ($protection -eq 'SecretStore') {
            # -VaultPassword is threaded through rather than left to the default. Without it
            # this reported CertificatePresent and CredentialWorks as false on a store whose
            # password is not the module's own - contradicting a connection that had just
            # succeeded, which is worse than not reporting at all.
            $stored = Get-EntraStoredCredential -TenantId $TenantId -VaultPassword $VaultPassword -ErrorAction Stop
            $certificate = $stored.Certificate
        }
        else {
            $certificate = Get-TestCertificate -Thumbprint $record.certificateThumbprint -ErrorAction Stop
        }
    }
    catch {
        Write-Verbose "The private key is not usable: $($_.Exception.Message)"
    }

    # The application, checked separately again. Only attempted when connected, since reading
    # it needs a token of its own.
    $applicationExists = $null
    $grantedNow = @()
    if ($script:EntraConnection) {
        try {
            $null = Invoke-EntraRequest -Method GET -Path "/applications/$($record.applicationObjectId)" `
                -Query @{ '$select' = 'id' }
            $applicationExists = $true

            $assignments = @(Invoke-EntraRequest -Method GET -Paginate `
                    -Path "/servicePrincipals/$($record.servicePrincipalId)/appRoleAssignments")
            $catalogue = @{}
            foreach ($permission in (Get-EntraSeedData -Name 'EntraServiceAppPermissions')) {
                $catalogue[$permission.AppRoleId] = $permission.Permission
            }
            $grantedNow = @($assignments | ForEach-Object {
                    if ($catalogue.ContainsKey($_.appRoleId)) { $catalogue[$_.appRoleId] } else { $_.appRoleId }
                } | Sort-Object)
        }
        catch {
            $applicationExists = $false
            Write-Verbose "Could not read the application back: $($_.Exception.Message)"
        }
    }

    $credentialWorks = $null
    if ($TestCredential) {
        if (-not $certificate) {
            $credentialWorks = $false
        }
        else {
            try {
                $probe = @{
                    TenantId       = $TenantId
                    ClientId       = $record.clientId
                    Certificate    = $certificate
                    AuthMode       = 'Certificate'
                    GraphBaseUri   = if ($script:EntraConnection) { $script:EntraConnection.GraphBaseUri } else { 'https://graph.microsoft.com' }
                    AccessToken    = $null
                    TokenExpiresOn = $null
                    TokenRoles     = @()
                }
                $null = Get-EntraAccessToken -Connection $probe
                $credentialWorks = $true
            }
            catch {
                $credentialWorks = $false
                Write-Verbose "Credential test failed: $($_.Exception.Message)"
            }
        }
    }

    return [PSCustomObject]@{
        PSTypeName            = 'EntraServiceAppStatus'
        TenantId              = $record.tenantId
        TenantName            = $record.tenantName
        DisplayName           = $record.displayName
        ClientId              = $record.clientId
        CertificateThumbprint = $record.certificateThumbprint
        CertificateExpires    = $record.certificateExpires
        KeyProtection         = $protection
        VaultName             = $(if ($record.PSObject.Properties['vaultName']) { $record.vaultName } else { $null })
        CertificatePresent    = [bool]$certificate
        ApplicationExists     = $applicationExists
        GrantedAtBootstrap    = @($record.grantedPermissions)
        GrantedNow            = $grantedNow
        CredentialWorks       = $credentialWorks
        RecordPath            = $recordPath
        CreatedOn             = $record.createdOn
    }
}
