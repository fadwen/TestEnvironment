function Import-OktaAppCredential {
    <#
    .SYNOPSIS
        Reads back the service app credential written by Export-OktaAppCredential

    .DESCRIPTION
        Resolves whichever storage mode the file records and returns a uniform object with the
        private JWK attached, so callers never branch on storage. Import-TestCredentialRecord
        reads a version 2 record and follows it to wherever the key is.

        Schema version 1 is still accepted, here rather than in Core because no other provider
        ever wrote one. Those files hold the JWK as plain JSON, from before the credential was
        encrypted at rest, and refusing them would strand anybody who seeded an environment with
        an earlier build. They are read, used, and reported with a warning naming the command
        that upgrades them - a warning being the right level because the credential still works
        and the run should not stop for it.

    .PARAMETER Path
        The credential file to read.

    .PARAMETER VaultPassword
        Password used to unlock the SecretStore vault, when the credential lives in one.

    .OUTPUTS
        PSCustomObject with orgUrl, clientId, appId, label, scopes, protection and privateJwk.

    .EXAMPLE
        PS> $credential = Import-OktaAppCredential -Path $path

        DESCRIPTION: Reads the record and recovers the private key
        OUTPUT: The credential with its JWK
        USE CASE: Connect-OktaEnvironment -ServiceApp and every token request

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [System.Security.SecureString]$VaultPassword
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("No service app credential at '$Path'. Run New-OktaServiceApp while " +
            'connected with an SSWS token to create one.')
    }

    # A version 1 record carries the key as a JSON object under privateJwk and no protection
    # field. It is the one shape the shared reader does not know, so it is read here.
    $peek = ([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path))).TrimStart([char]0xFEFF)
    try { $peek = $peek | ConvertFrom-Json } catch { throw "'$Path' is not valid JSON: $($_.Exception.Message)" }
    $legacy = (-not $peek.PSObject.Properties['protection'] -or -not $peek.protection) -and
        $peek.PSObject.Properties['privateJwk'] -and $peek.privateJwk

    if ($legacy) {
        foreach ($required in @('orgUrl', 'clientId', 'appId')) {
            if (-not $peek.PSObject.Properties[$required] -or -not $peek.$required) {
                throw "'$Path' is missing the required '$required' field and cannot be used."
            }
        }
        Write-Warning ("'$Path' stores the private key unencrypted, in the format used before this module " +
            'encrypted credentials at rest. Re-run New-OktaServiceApp -Force with an SSWS token to replace it.')
        $record = $peek
        $privateJwk = $peek.privateJwk
        $protection = 'None'
    }
    else {
        $read = Import-TestCredentialRecord -Path $Path -Required orgUrl, clientId, appId -SecretField 'privateJwkProtected' `
            -SecretLabel 'key' -MissingRecordMessage 'Run New-OktaServiceApp while connected with an SSWS token to create one.' `
            -VaultPassword $VaultPassword
        $record = $read.Record
        $protection = $read.Protection
        try { $privateJwk = $read.Secret | ConvertFrom-Json }
        catch { throw "The stored private key in '$Path' is not valid JSON: $($_.Exception.Message)" }
    }

    return [PSCustomObject]@{
        orgUrl     = $record.orgUrl
        clientId   = $record.clientId
        appId      = $record.appId
        label      = $record.label
        scopes     = @($record.scopes)
        protection = $protection
        vaultName  = $(if ($record.PSObject.Properties['vaultName']) { $record.vaultName } else { $null })
        secretName = $(if ($record.PSObject.Properties['secretName']) { $record.secretName } else { $null })
        createdUtc = $(if ($record.PSObject.Properties['createdUtc']) { $record.createdUtc } else { $null })
        privateJwk = $privateJwk
        path       = $Path
    }
}
