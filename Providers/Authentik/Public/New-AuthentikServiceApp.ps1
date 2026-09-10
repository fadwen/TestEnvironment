function New-AuthentikServiceApp {
    <#
    .SYNOPSIS
        Creates the automation service account the module connects as from then on

    .DESCRIPTION
        Authentik's equivalent of a service app is a service account: a user of the
        service_account type carrying a token. The account-creation call returns a token of
        its own, but that one has the app-password intent, which the API refuses as a bearer
        credential; a live run proved it with 'Token invalid/expired'. So this creates the
        account, replaces that token with one of the api intent and no expiry, reads its key
        back, places the account under the seed path with the seed tag, adds it to the
        instance's superuser group so it can create and delete everything the seed touches,
        proves the token by calling the API with it, and writes the credential record that
        Connect-AuthentikEnvironment -ServiceAccount reads.

        The token is written where the record says: into a SecretStore vault under
        -UseSecretStore, which is proven usable before the account exists so a created
        account is never left without a saved token, or DPAPI-protected in the record itself.

        The account is a seeded user in every respect but one: teardown keeps it unless told
        otherwise, because it is the credential doing the tearing down.

    .PARAMETER CredentialPath
        Where to write the credential record, when not the default location.

    .PARAMETER UseSecretStore
        Keep the token in a SecretStore vault rather than in the record.

    .PARAMETER VaultName
        The vault to use with -UseSecretStore.

    .PARAMETER VaultPassword
        The vault's password, when it is not the module default.

    .PARAMETER Force
        Replace an existing service account and mint a new token.

    .PARAMETER PassThru
        Returns the result object.

    .OUTPUTS
        PSCustomObject with BaseUrl, Username, UserPk, SuperuserGroup, CredentialPath,
        Protection, VaultName, HandoverVerified and Warnings.

    .EXAMPLE
        PS> New-AuthentikServiceApp

        DESCRIPTION: Creates the service account and writes the record
        OUTPUT: A banner naming the command to connect with from now on
        USE CASE: Once per instance, after connecting with an API token

    .EXAMPLE
        PS> New-AuthentikServiceApp -UseSecretStore -Force

        DESCRIPTION: Replaces the account and keeps the new token in the vault
        OUTPUT: The banner, and the result under -PassThru
        USE CASE: Rotating the token, or moving it off disk on a shared machine

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
        [string]$VaultName = 'AuthentikEnvironment',

        [Parameter()]
        [System.Security.SecureString]$VaultPassword,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-AuthentikConnection
    $marker = Get-AuthentikSeedMarker -Connection $connection
    $username = Get-AuthentikServiceAccountName -Marker $marker
    $recordPath = Get-AuthentikCredentialPath -BaseUrl $connection.BaseUrl -Path $CredentialPath
    $warnings = @()

    # --- An existing account ----------------------------------------------------------------
    $existing = @(Invoke-AuthentikRequest -Method GET -Path '/core/users/' `
            -Query @{ username = $username } -Connection $connection -Paginate)

    if ($existing.Count -gt 0 -and -not $Force) {
        throw "'$username' already exists (pk $($existing[0].pk)). Use -Force to replace it and mint a new token, or Get-TestServiceApp to see what is stored."
    }

    if (-not $PSCmdlet.ShouldProcess($username, 'Create a superuser service account with a non-expiring api-intent token')) {
        return
    }

    # --- The vault, before anything is created ----------------------------------------------
    if ($UseSecretStore) {
        $vault = Initialize-TestSecretVault -VaultName $VaultName -VaultPassword $VaultPassword -Install
        if (-not $vault -or -not $vault.Available) {
            throw "Vault '$VaultName' is not usable, so nothing was created."
        }
    }

    if ($existing.Count -gt 0) {
        Write-Verbose "Replacing service account $username (pk $($existing[0].pk))"
        $null = Invoke-AuthentikRequest -Method DELETE -Path "/core/users/$($existing[0].pk)/" -Connection $connection
    }

    # --- Create ------------------------------------------------------------------------------
    $created = Invoke-AuthentikRequest -Method POST -Path '/core/users/service_account/' -Connection $connection -Body @{
        name         = $username
        create_group = $false
        expiring     = $false
    }
    if (-not $created -or -not $created.user_pk) {
        throw 'Authentik created the service account but returned no user.'
    }
    $userPk = [int]$created.user_pk

    # The creation call's token has the app_password intent and is refused as a bearer
    # credential. It is removed rather than left as an unused way in, and an api-intent
    # token is minted in its place, whose key the API hands back exactly once through
    # view_key.
    try {
        $leftover = @(Invoke-AuthentikRequest -Method GET -Path '/core/tokens/' `
                -Query @{ user__username = $username; intent = 'app_password' } -Connection $connection -Paginate)
        foreach ($item in $leftover) {
            $null = Invoke-AuthentikRequest -Method DELETE -Path "/core/tokens/$($item.identifier)/" -Connection $connection
        }
    }
    catch {
        Write-Verbose "Could not remove the app-password token: $($_.Exception.Message)"
    }

    $tokenIdentifier = '{0}-api' -f $username
    $null = Invoke-AuthentikRequest -Method POST -Path '/core/tokens/' -Connection $connection -Body @{
        identifier  = $tokenIdentifier
        intent      = 'api'
        user        = $userPk
        expiring    = $false
        description = 'TestEnvironment automation. Safe to delete; teardown removes it with the account.'
    }
    $key = Invoke-AuthentikRequest -Method GET -Path "/core/tokens/$tokenIdentifier/view_key/" -Connection $connection
    if (-not $key -or -not $key.key) {
        throw "Authentik created the token '$tokenIdentifier' but did not return its key."
    }
    $token = [string]$key.key

    # Stamped like every other seeded user, so it is found by the same evidence and kept
    # apart only by its reserved username.
    $attributes = [ordered]@{}
    $attributes[$marker.Attribute] = $marker.Tag
    $attributes['labKey'] = $username
    $null = Invoke-AuthentikRequest -Method PATCH -Path "/core/users/$userPk/" -Connection $connection -Body @{
        name       = '{0}Automation' -f $marker.Prefix
        path       = $marker.UserPath
        attributes = $attributes
    }

    # --- Rights ------------------------------------------------------------------------------
    $superuserGroup = $null
    try {
        $superusers = @(Invoke-AuthentikRequest -Method GET -Path '/core/groups/' `
                -Query @{ is_superuser = 'true' } -Connection $connection -Paginate)
        if ($superusers.Count -eq 0) { throw 'no superuser group exists in this instance' }
        $superuserGroup = $superusers[0]
        $null = Invoke-AuthentikRequest -Method POST -Path "/core/groups/$($superuserGroup.pk)/add_user/" `
            -Body @{ pk = $userPk } -Connection $connection
    }
    catch {
        $warnings += "Could not add the account to a superuser group: $($_.Exception.Message). It exists but cannot seed anything until it has rights."
        Write-Warning $warnings[-1]
    }

    # --- The record --------------------------------------------------------------------------
    $exportArgs = @{
        Path           = $recordPath
        BaseUrl        = $connection.BaseUrl
        Username       = $username
        UserPk         = $userPk
        Token          = $token
        UseSecretStore = $UseSecretStore
        VaultName      = $VaultName
        Confirm        = $false
    }
    if ($VaultPassword) { $exportArgs['VaultPassword'] = $VaultPassword }
    $stored = Export-AuthentikCredential @exportArgs

    # --- Handover ------------------------------------------------------------------------------
    $handover = $false
    try {
        $probe = @{ BaseUrl = $connection.BaseUrl; AuthorizationHeader = "Bearer $token"; AuthType = 'ServiceAccount' }
        $me = Invoke-AuthentikRequest -Method GET -Path '/core/users/me/' -Connection $probe
        $handover = [bool]($me -and $me.user -and $me.user.username -eq $username)
    }
    catch {
        $warnings += "The account was created but its token did not authenticate: $($_.Exception.Message)"
        Write-Warning $warnings[-1]
    }

    Write-Host ''
    Write-Host '  Bootstrap complete. From now on, connect as the service account:' -ForegroundColor Green
    Write-Host ''
    Write-Host "    Connect-TestEnvironment -Provider Authentik -BaseUrl $($connection.BaseUrl) -ServiceAccount" -ForegroundColor Cyan
    Write-Host ''
    if ($UseSecretStore) {
        Write-Host "    (token in vault '$VaultName'; the account comes from the record at $recordPath)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "    (token $($stored.Protection)-protected in the record at $recordPath)" -ForegroundColor DarkGray
    }
    Write-Host ''

    if ($PassThru) {
        return [PSCustomObject]@{
            PSTypeName       = 'AuthentikServiceApp'
            BaseUrl          = $connection.BaseUrl
            Username         = $username
            UserPk           = $userPk
            SuperuserGroup   = $(if ($superuserGroup) { $superuserGroup.name } else { $null })
            CredentialPath   = $recordPath
            Protection       = $stored.Protection
            VaultName        = $stored.VaultName
            HandoverVerified = $handover
            Warnings         = $warnings
        }
    }
}
