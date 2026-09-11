function New-FreeIPAServiceApp {
    <#
    .SYNOPSIS
        Creates the automation service account the module connects as from then on

    .DESCRIPTION
        FreeIPA's equivalent of a service app is a user with no shell whose only purpose is the
        API. This creates one with a random password, adds it to the admins group so it can
        create and delete everything the seed touches, and then deals with the two things
        FreeIPA does to a fresh password: the random one the server handed back is expired the
        moment it was set, so it is changed once as the user to a second random one, which is
        current; and the realm's policy would expire that on its own schedule, so the
        account's password expiry is set far into the future. The account is then proven by
        logging in with it, and the credential record that Connect-FreeIPAEnvironment
        -ServiceAccount reads is written, with the pinned certificate authority inside it.

        The password is written where the record says: into a SecretStore vault under
        -UseSecretStore, which is proven usable before the account exists so a created account
        is never left without a saved password, or DPAPI-protected in the record itself.

        The account is a seeded user in every respect but one: teardown keeps it unless told
        otherwise, because it is the credential doing the tearing down.

    .PARAMETER CredentialPath
        Where to write the credential record, when not the default location.

    .PARAMETER UseSecretStore
        Keep the password in a SecretStore vault rather than in the record.

    .PARAMETER VaultName
        The vault to use with -UseSecretStore.

    .PARAMETER VaultPassword
        The vault's password, when it is not the module default.

    .PARAMETER Force
        Replace an existing service account and mint a new password.

    .PARAMETER PassThru
        Returns the result object.

    .OUTPUTS
        PSCustomObject with BaseUrl, Username, AdminGroup, CredentialPath, Protection,
        VaultName, HandoverVerified and Warnings.

    .EXAMPLE
        PS> New-FreeIPAServiceApp

        DESCRIPTION: Creates the service account and writes the record
        OUTPUT: A banner naming the command to connect with from now on
        USE CASE: Once per realm, after connecting with an administrator's credential

    .EXAMPLE
        PS> New-FreeIPAServiceApp -UseSecretStore -Force

        DESCRIPTION: Replaces the account and keeps the new password in the vault
        OUTPUT: The banner, and the result under -PassThru
        USE CASE: Rotating the password, or moving it off disk on a shared machine

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialPath',
        Justification = 'A file path to a credential record, not a credential.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The handover banner is an instruction to the person who just bootstrapped, naming the exact command to connect with from now on. It must survive a caller who is capturing the output.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$CredentialPath,

        [Parameter()]
        [switch]$UseSecretStore,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$VaultName = 'FreeIPAEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection
    $username = Get-FreeIPAServiceAccountName -Marker $marker
    $recordPath = Get-FreeIPACredentialPath -BaseUrl $connection.BaseUrl -Path $CredentialPath
    $adminGroup = 'admins'
    $warnings = @()

    # --- An existing account ----------------------------------------------------------------
    $existing = Invoke-FreeIPARequest -Method 'user_show' -Arguments $username -IgnoreError 'NotFound' -Connection $connection

    if ($existing -and -not $Force) {
        throw "'$username' already exists. Use -Force to replace it and mint a new password, or Get-TestServiceApp to see what is stored."
    }

    if (-not $PSCmdlet.ShouldProcess($username, "Create an admins-group service account with a random password")) {
        return
    }

    # --- The vault, before anything is created ----------------------------------------------
    if ($UseSecretStore) {
        $vault = Initialize-TestSecretVault -VaultName $VaultName -VaultPassword $VaultPassword -Install
        if (-not $vault -or -not $vault.Available) {
            throw "Vault '$VaultName' is not usable, so nothing was created."
        }
    }

    if ($existing) {
        Write-Verbose "Replacing service account $username"
        $null = Invoke-FreeIPARequest -Method 'user_del' -Arguments $username -Connection $connection
    }

    # --- Create ------------------------------------------------------------------------------
    # The server mints the first password and hands it back once. It is expired on arrival,
    # as every admin-set password is, so it is changed immediately as the user.
    $created = Invoke-FreeIPARequest -Method 'user_add' -Arguments $username -Connection $connection -Options @{
        givenname   = 'TestEnvironment'
        sn          = 'Automation'
        cn          = '{0}Automation' -f $marker.Prefix
        displayname = '{0}Automation' -f $marker.Prefix
        userclass   = @($marker.Tag)
        loginshell  = '/sbin/nologin'
        random      = $true
    }
    if (-not $created -or -not $created.result -or -not $created.result.randompassword) {
        throw 'FreeIPA created the service account but returned no password.'
    }
    $initial = [string]$created.result.randompassword

    $password = New-TestPassword -Length 32
    Set-FreeIPAPassword -Connection $connection -Username $username -OldPassword $initial -NewPassword $password -Confirm:$false

    # Far enough out that the realm's policy never expires it underneath a run. Connect still
    # rotates on 'password-expired' should an administrator shorten it by hand.
    try {
        $null = Invoke-FreeIPARequest -Method 'user_mod' -Arguments $username -Connection $connection -Options @{
            krbpasswordexpiration = ConvertTo-FreeIPADateTime -Value ([DateTimeOffset]::UtcNow.AddYears(10))
        }
    }
    catch {
        $warnings += "Could not extend the password expiry: $($_.Exception.Message). The realm's policy applies and the connect will rotate the password when it expires."
        Write-Warning $warnings[-1]
    }

    # --- Rights ------------------------------------------------------------------------------
    try {
        $membership = Invoke-FreeIPARequest -Method 'group_add_member' -Arguments $adminGroup -Connection $connection -Options @{ user = @($username) }
        if ($membership -and $membership.completed -ne 1) {
            throw "the realm reported $($membership.completed) completed additions"
        }
    }
    catch {
        $warnings += "Could not add the account to '$adminGroup': $($_.Exception.Message). It exists but cannot seed anything until it has rights."
        Write-Warning $warnings[-1]
    }

    # --- The record --------------------------------------------------------------------------
    $exportArgs = @{
        Path           = $recordPath
        BaseUrl        = $connection.BaseUrl
        Username       = $username
        Password       = $password
        CaCertificate  = $connection.CaCertificate
        UseSecretStore = $UseSecretStore
        VaultName      = $VaultName
        Confirm        = $false
    }
    if ($VaultPassword) { $exportArgs['VaultPassword'] = $VaultPassword }
    $stored = Export-FreeIPACredential @exportArgs

    # --- Handover ------------------------------------------------------------------------------
    $handover = $false
    $probeHttp = $null
    try {
        $probeHttp = New-FreeIPAHttpClient -BaseUrl $connection.BaseUrl -CaCertificate $connection.CaCertificate
        $probe = @{
            BaseUrl = $connection.BaseUrl; Username = $username; Password = $password; AuthType = 'ServiceAccount'
            Client = $probeHttp.Client; Cookies = $probeHttp.Cookies; ApiVersion = $connection.ApiVersion
        }
        $login = Connect-FreeIPASession -Connection $probe
        if (-not $login.Success) { throw "login was rejected ($($login.Reason))" }
        $who = Invoke-FreeIPARequest -Method 'whoami' -Connection $probe
        $handover = [bool]($who -and $who.arguments -and (@($who.arguments)[0]) -eq $username)
    }
    catch {
        $warnings += "The account was created but its password did not authenticate: $($_.Exception.Message)"
        Write-Warning $warnings[-1]
    }
    finally {
        if ($probeHttp) { $probeHttp.Client.Dispose() }
    }

    Write-Host ''
    Write-Host '  Bootstrap complete. From now on, connect as the service account:' -ForegroundColor Green
    Write-Host ''
    Write-Host "    Connect-TestEnvironment -Provider FreeIPA -BaseUrl $($connection.BaseUrl) -ServiceAccount" -ForegroundColor Cyan
    Write-Host ''
    if ($UseSecretStore) {
        Write-Host "    (password in vault '$VaultName'; the account comes from the record at $recordPath)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    (password $($stored.Protection)-protected in the record at $recordPath)" -ForegroundColor DarkGray
    }
    Write-Host ''

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName       = 'FreeIPAServiceApp'
            BaseUrl          = $connection.BaseUrl
            Username         = $username
            AdminGroup       = $adminGroup
            CredentialPath   = $recordPath
            Protection       = $stored.Protection
            VaultName        = $stored.VaultName
            HandoverVerified = $handover
            Warnings         = $warnings
        }
    }
}
