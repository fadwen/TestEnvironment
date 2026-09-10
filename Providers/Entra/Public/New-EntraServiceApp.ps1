function New-EntraServiceApp {
    <#
    .SYNOPSIS
        Bootstraps a dedicated application for this module, and hands over to it

    .DESCRIPTION
        Creates the application the module authenticates as from then on, so that the only
        thing a human ever has to do interactively is authorise it once.

        The flow mirrors OktaTestEnvironment's, which trades a pasted SSWS token for an OAuth
        service app. Entra has no pasted token to trade - there is no long-lived personal API
        key - so the bootstrap credential is the human themselves, signed in by device code.
        Everything after that is app-only:

        1. Generate an RSA key pair locally. **Only the public half is ever sent.** The private
           key stays on this machine, in the certificate store, and Entra never sees it.
        2. Create the application and upload the public key as a credential.
        3. Create its service principal.
        4. Grant admin consent for the application permissions it needs. Consent for an
           application permission IS an appRoleAssignment on the Microsoft Graph service
           principal, which is why this step needs a Global Administrator and cannot be done
           by the application itself.
        5. Prove the handover works by acquiring a token as the new application before
           reporting success. An application that exists and cannot authenticate is worse than
           no application, because the failure surfaces later and somewhere else.

        The credential record is written to ~/.testenvironment/, outside the repository.
        It records which application and which certificate to use; the private key is not in
        it, because the key lives in the certificate store.

        > **RoleManagement.ReadWrite.Directory is privileged.** It is included by default
        > because the module seeds custom directory roles, and it permits creating and
        > assigning directory roles - an escalation path. Pass -Scope without it, and skip the
        > DirectoryRoles seeding step, if that is not a trade you want.

    .PARAMETER DisplayName
        Name for the application. The seed prefix is applied automatically.

    .PARAMETER Scope
        Application permissions to grant. Defaults to every permission marked Required in the
        seed data, plus RoleManagement.ReadWrite.Directory.

    .PARAMETER CertificateValidityDays
        How long the generated certificate is valid for

    .PARAMETER Force
        Replaces an existing bootstrapped application and its certificate

    .PARAMETER PassThru
        Returns the details of what was created

    .OUTPUTS
        EntraServiceApp when -PassThru is supplied

    .EXAMPLE
        PS> Connect-EntraEnvironment -TenantId <tenant> -Interactive
        PS> New-EntraServiceApp -PassThru

        DESCRIPTION: Signs a human in once, then creates and authorises the application
        OUTPUT: The application id, the certificate thumbprint, and the granted permissions
        USE CASE: First run against a new tenant

    .EXAMPLE
        PS> Connect-EntraEnvironment -TenantId <tenant> -Interactive
        PS> New-EntraServiceApp -Scope User.ReadWrite.All, Group.ReadWrite.All

        DESCRIPTION: Grants only what a directory-only seed needs
        OUTPUT: None
        USE CASE: Deliberately withholding the privileged permissions

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('EntraServiceApp')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The handover banner is an instruction to the human who just authorised the bootstrap, telling them the exact command to connect with from now on. It is deliberately not part of the output object, which -PassThru already carries, and it must survive a caller who is piping or suppressing the other streams.')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName = 'ServiceApp',

        [Parameter()]
        [string[]]$Scope,

        [Parameter()]
        [ValidateRange(30, 1095)]
        [int]$CertificateValidityDays = 365,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'EntraEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection
    $appName = '{0}{1}' -f $marker.Prefix, $DisplayName

    if ($connection.AuthMode -ne 'DeviceCode') {
        Write-Warning ("Bootstrapping while connected app-only. Granting admin consent needs a Global " +
            "Administrator, which an application usually is not - if this fails with Authorization_RequestDenied, " +
            "reconnect with -Interactive and run it again.")
    }

    # --- Permissions -------------------------------------------------------------------
    $catalogue = @(Get-EntraSeedData -Name 'EntraServiceAppPermissions')
    $wanted = if ($Scope) {
        $unknown = @($Scope | Where-Object { $catalogue.Permission -notcontains $_ })
        if ($unknown) {
            Write-Error ("Unknown permission(s): $($unknown -join ', '). Known: " +
                ($catalogue.Permission -join ', ')) -ErrorAction Stop
            return
        }
        @($catalogue | Where-Object { $Scope -contains $_.Permission })
    }
    else {
        $catalogue
    }

    Write-Verbose "Granting $($wanted.Count) application permission(s)"

    # --- The vault, before anything is created -----------------------------------------
    # Checked up front rather than at the point the key is stored. A vault that cannot be
    # opened is a very likely failure - SecretStore configuration is per user and shared with
    # whatever else uses it - and discovering that after the application exists leaves an
    # orphaned registration with a private key that was never saved anywhere.
    if ($UseSecretStore) {
        $vault = Initialize-TestSecretVault -VaultName $VaultName -VaultPassword $VaultPassword -Install
        if (-not $vault -or -not $vault.Available) {
            Write-Error "Vault '$VaultName' is not usable, so nothing was created." -ErrorAction Stop
            return
        }
        Write-Verbose "Vault '$VaultName' is ready"
    }

    # --- An existing bootstrap ---------------------------------------------------------
    $existing = $null
    try {
        $existing = @(Invoke-EntraRequest -Method GET -Path '/applications' -Connection $connection `
                -Paginate -ConsistencyLevel -Query @{
                    '$filter' = "displayName eq '$($appName.Replace("'", "''"))'"
                    '$select' = 'id,appId,displayName'
                }) | Select-Object -First 1
    }
    catch {
        Write-Verbose "Could not check for an existing service app: $($_.Exception.Message)"
    }

    if ($existing -and -not $Force) {
        Write-Warning ("'$appName' already exists (appId $($existing.appId)). Use -Force to replace it and mint " +
            "a new certificate, or Get-EntraServiceApp to see what is stored.")
        return
    }

    if ($existing -and $Force) {
        if ($PSCmdlet.ShouldProcess($appName, 'Delete the existing service app and its certificate')) {
            try {
                foreach ($principal in @(Invoke-EntraRequest -Method GET -Path '/servicePrincipals' -Connection $connection `
                            -Paginate -ConsistencyLevel -Query @{ '$filter' = "appId eq '$($existing.appId)'"; '$select' = 'id' })) {
                    Invoke-EntraRequest -Method DELETE -Path "/servicePrincipals/$($principal.id)" -Connection $connection -RetryOnNotFound | Out-Null
                }
                Invoke-EntraRequest -Method DELETE -Path "/applications/$($existing.id)" -Connection $connection -RetryOnNotFound | Out-Null
                Write-Verbose "Removed the previous '$appName'"
            }
            catch {
                Write-Warning "Could not remove the previous service app: $($_.Exception.Message)"
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($appName,
            "Create an application and grant it $($wanted.Count) application permission(s) in tenant $($connection.TenantName)")) {
        return
    }

    # --- 1. The key pair, generated locally --------------------------------------------
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $certificate = $null
    try {
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            "CN=$appName", $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

        # Backdated slightly so a workstation clock a little ahead of Entra's does not make a
        # certificate that is not yet valid at the moment it is first used.
        $certificate = $request.CreateSelfSigned(
            [DateTimeOffset]::UtcNow.AddMinutes(-5),
            [DateTimeOffset]::UtcNow.AddDays($CertificateValidityDays))
    }
    finally {
        $rsa.Dispose()
    }

    # --- 2. The application ------------------------------------------------------------
    $application = $null
    try {
        $application = Invoke-EntraRequest -Method POST -Path '/applications' -Connection $connection -Body @{
            displayName    = $appName
            signInAudience = 'AzureADMyOrg'
            tags           = @($marker.Tag, 'EntraEnvironmentServiceApp')
            notes          = "Authenticates EntraEnvironment. $($marker.Description)"
        }
        Write-Verbose "Created application '$appName' ($($application.appId))"
    }
    catch {
        $certificate.Dispose()
        throw (New-Object System.Exception("Could not create the service app: $($_.Exception.Message)", $_.Exception))
    }

    try {
        # Only the public half. RawData is the DER-encoded certificate with no private key in
        # it, which is the entire security property this design rests on.
        Invoke-EntraRequest -Method PATCH -Path "/applications/$($application.id)" -Connection $connection -RetryOnNotFound -Body @{
            keyCredentials = @(@{
                    type        = 'AsymmetricX509Cert'
                    usage       = 'Verify'
                    key         = [Convert]::ToBase64String($certificate.RawData)
                    displayName = "CN=$appName"
                })
        } | Out-Null
        Write-Verbose 'Uploaded the certificate public key'
    }
    catch {
        $certificate.Dispose()
        throw (New-Object System.Exception("Could not attach the certificate: $($_.Exception.Message)", $_.Exception))
    }

    # --- 3. The service principal ------------------------------------------------------
    $principal = $null
    try {
        $principal = Invoke-EntraRequest -Method POST -Path '/servicePrincipals' -Connection $connection `
            -RetryOnNotFound -RetryOnErrorMatch 'does not reference a valid application object' -Body @{
            appId = $application.appId
            tags  = @($marker.Tag, 'EntraEnvironmentServiceApp')
        }
        Write-Verbose "Created the service principal ($($principal.id))"
    }
    catch {
        $certificate.Dispose()
        throw (New-Object System.Exception("Could not create the service principal: $($_.Exception.Message)", $_.Exception))
    }

    # --- 4. Admin consent --------------------------------------------------------------
    $graphAppId = '00000003-0000-0000-c000-000000000000'
    $graphPrincipal = $null
    try {
        $graphPrincipal = (Invoke-EntraRequest -Method GET -Connection $connection `
                -Path "/servicePrincipals?`$filter=appId eq '$graphAppId'").value | Select-Object -First 1
    }
    catch {
        Write-Warning "Could not resolve the Microsoft Graph service principal: $($_.Exception.Message)"
    }

    $granted = [System.Collections.Generic.List[string]]::new()
    $refused = [System.Collections.Generic.List[string]]::new()

    if ($graphPrincipal) {
        foreach ($permission in $wanted) {
            try {
                Invoke-EntraRequest -Method POST -Connection $connection -RetryOnNotFound `
                    -RetryOnErrorMatch 'does not reference a valid' `
                    -Path "/servicePrincipals/$($principal.id)/appRoleAssignments" -Body @{
                    principalId = $principal.id
                    resourceId  = $graphPrincipal.id
                    appRoleId   = $permission.AppRoleId
                } | Out-Null
                $granted.Add($permission.Permission)
                Write-Verbose "Consented: $($permission.Permission)"
            }
            catch {
                $refused.Add($permission.Permission)
                Write-Warning "Could not grant '$($permission.Permission)': $($_.Exception.Message)"
            }
        }
    }

    if ($refused.Count -gt 0) {
        Write-Warning ("$($refused.Count) permission(s) were not granted: $($refused -join ', '). Granting an " +
            "application permission requires a Global Administrator; the seeding steps that need these will fail.")
    }

    # --- 5. Prove the handover before claiming success ---------------------------------
    # Nothing is reported as working until the new application has actually authenticated.
    Write-Verbose 'Waiting for the credential to become usable, then testing the handover'
    $handover = $false
    $handoverRoles = @()

    foreach ($delay in 10, 15, 20, 30, 30) {
        Start-Sleep -Seconds $delay
        try {
            $probe = @{
                TenantId       = $connection.TenantId
                ClientId       = $application.appId
                Certificate    = $certificate
                AuthMode       = 'Certificate'
                GraphBaseUri   = $connection.GraphBaseUri
                AccessToken    = $null
                TokenExpiresOn = $null
                TokenRoles     = @()
            }
            $null = Get-EntraAccessToken -Connection $probe
            $handoverRoles = @($probe.TokenRoles)
            $handover = $true
            break
        }
        catch {
            Write-Verbose "Handover not ready yet: $($_.Exception.Message)"
        }
    }

    # --- Store the certificate and the record -------------------------------------------
    $storedThumbprint = $certificate.Thumbprint
    $keyProtection = 'CertificateStore'
    $secretName = "EntraEnvironment-$($connection.TenantId)"

    if ($UseSecretStore) {
        # The portable path. The certificate store is the right default on Windows, but off it
        # the store is a file-backed shim whose behaviour varies by distribution, so a lab that
        # has to run on Linux or in a container needs the key somewhere it controls. The PFX
        # goes into the vault and the certificate store is left alone entirely.
        $keyProtection = 'SecretStore'
        $transitPassword = New-TestPassword -Length 48
        $pfx = $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $transitPassword)

        try {
            # The vault was already proven usable before anything was created, so this only
            # writes.
            #
            # Two secrets, because the PFX is useless without the password that unwraps it and
            # storing them together would make the vault entry self-decrypting.
            $null = Set-TestVaultSecret -VaultName $VaultName -SecretName $secretName `
                -PlainText ([Convert]::ToBase64String($pfx)) -Confirm:$false
            $null = Set-TestVaultSecret -VaultName $VaultName -SecretName "$secretName-password" `
                -PlainText $transitPassword -Confirm:$false

            Write-Verbose "Private key stored in SecretStore vault '$VaultName' as '$secretName'"
        }
        catch {
            $certificate.Dispose()
            throw (New-Object System.Exception(
                "The application was created but its private key could not be stored in the vault: $($_.Exception.Message)",
                $_.Exception))
        }
        finally {
            [Array]::Clear($pfx, 0, $pfx.Length)
        }
    }
    else {
        try {
            if (-not (Save-TestCertificate -Certificate $certificate)) {
                Write-Warning "The certificate was stored without a usable private key; the handover will not work."
            }
        }
        catch {
            Write-Warning ("Could not add the certificate to the store: $($_.Exception.Message). The application " +
                "exists but you will need to supply the certificate another way.")
        }
    }

    $recordPath = Get-TestCredentialPath -TenantId $connection.TenantId
    try {
        [ordered]@{
            schemaVersion         = 1
            tenantId              = $connection.TenantId
            tenantName            = $connection.TenantName
            applicationObjectId   = $application.id
            clientId              = $application.appId
            servicePrincipalId    = $principal.id
            displayName           = $appName
            certificateThumbprint = $storedThumbprint
            certificateExpires    = $certificate.NotAfter.ToString('o')
            # Where the private key actually is. Connect-EntraEnvironment reads this to
            # decide whether to look in the certificate store or open the vault, so a record
            # that guessed would send it to the wrong place.
            keyProtection         = $keyProtection
            vaultName             = $(if ($UseSecretStore) { $VaultName } else { $null })
            secretName            = $(if ($UseSecretStore) { $secretName } else { $null })
            grantedPermissions    = @($granted)
            createdOn             = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath -Encoding UTF8
        Write-Verbose "Wrote the credential record to $recordPath"
    }
    catch {
        Write-Warning "Could not write the credential record to ${recordPath}: $($_.Exception.Message)"
    }

    $certificate.Dispose()

    if (-not $handover) {
        Write-Warning ("The application was created and consented but has not yet authenticated. Entra sometimes " +
            "takes a few minutes to publish a new credential. Try connecting with the thumbprint below shortly.")
    }

    Write-Host ''
    Write-Host '  Bootstrap complete. From now on, connect app-only:' -ForegroundColor Green
    Write-Host ''
    if ($keyProtection -eq 'SecretStore') {
        Write-Host "    Connect-TestEnvironment -Provider Entra -TenantId $($connection.TenantId) -UseSecretStore" -ForegroundColor Cyan
        Write-Host ''
        Write-Host "    (private key in vault '$VaultName'; the client id and thumbprint come from the record)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    Connect-TestEnvironment -Provider Entra -TenantId $($connection.TenantId) ``" -ForegroundColor Cyan
        Write-Host "        -ClientId $($application.appId) ``" -ForegroundColor Cyan
        Write-Host "        -CertificateThumbprint $storedThumbprint" -ForegroundColor Cyan
    }
    Write-Host ''

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName            = 'EntraServiceApp'
            TenantId              = $connection.TenantId
            TenantName            = $connection.TenantName
            DisplayName           = $appName
            ClientId              = $application.appId
            ApplicationObjectId   = $application.id
            ServicePrincipalId    = $principal.id
            CertificateThumbprint = $storedThumbprint
            KeyProtection         = $keyProtection
            VaultName             = $(if ($UseSecretStore) { $VaultName } else { $null })
            GrantedPermissions    = @($granted)
            RefusedPermissions    = @($refused)
            HandoverVerified      = $handover
            HandoverRoles         = $handoverRoles
            RecordPath            = $recordPath
        }
    }
}
