function Remove-OneLoginAppSecret {
    <#
    .SYNOPSIS
        Deletes a saved app secret record, and the vault secret it points to

    .DESCRIPTION
        Called by Remove-OneLoginEnvironment for each app it deletes, and for each record whose app
        is no longer in the account, so a saved secret never outlives the app it opens. A record
        kept in the SecretStore points to a vault secret; that secret is removed first, then the
        record, so a failure part way leaves the record that still names what is left.

        Goes through ShouldProcess, so a teardown run with -WhatIf lists the record and removes
        nothing.

    .PARAMETER Record
        A record as Get-OneLoginAppSecretRecord returns it.

    .OUTPUTS
        System.Boolean, $true when the record was removed.

    .EXAMPLE
        PS> Get-OneLoginAppSecretRecord -Subdomain contoso | Remove-OneLoginAppSecret -Confirm:$false

        DESCRIPTION: Removes every saved app secret for the account
        OUTPUT: $true per record removed
        USE CASE: Teardown

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNull()]
        [PSCustomObject]$Record
    )

    process {
        $label = if ($Record.AppName) { "$($Record.AppName) ($($Record.AppId))" } else { "app $($Record.AppId)" }
        if (-not $PSCmdlet.ShouldProcess($Record.Path, "Delete the saved client secret of OneLogin $label")) {
            return $false
        }

        if ($Record.Protection -eq 'SecretStore' -and $Record.VaultName -and $Record.SecretName) {
            $null = Remove-TestVaultSecret -VaultName $Record.VaultName -SecretName $Record.SecretName -Confirm:$false
        }
        Remove-Item -LiteralPath $Record.Path -Force -Confirm:$false -ErrorAction Stop
        return $true
    }
}
