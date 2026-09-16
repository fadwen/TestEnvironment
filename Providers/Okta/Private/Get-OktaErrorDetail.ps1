function Get-OktaErrorDetail {
    <#
    .SYNOPSIS
        Extracts the useful part of a failed Okta API response

    .DESCRIPTION
        Okta puts the actionable text in the response body, under errorSummary and
        errorCauses, and PowerShell throws that body away in favour of a generic
        "The remote server returned an error" message. Invoke-TestWebRequest reads the body
        once, whichever way the running PowerShell hands it over, and puts it in
        $_.ErrorDetails.Message on both editions.

        This reads it from there and flattens errorCauses, which is the field that actually
        says which attribute was rejected and why.

    .PARAMETER ErrorRecord
        The ErrorRecord caught from Invoke-WebRequest

    .OUTPUTS
        String suitable for putting straight into an exception message

    .EXAMPLE
        catch { throw (Get-OktaErrorDetail -ErrorRecord $_) }

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2026-08-07
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    # The body is in ErrorDetails on both editions: Invoke-TestWebRequest reads a failed response
    # once, with -SkipHttpErrorCheck on PowerShell 7 and from the response stream on Windows
    # PowerShell, and puts it there. Nothing here reads a stream.
    $rawBody = $null
    if ($ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $rawBody = $ErrorRecord.ErrorDetails.Message
    }

    # Whatever is left when the body is absent or is not an Okta error document. A transport
    # failure is the common case: PowerShell 7 puts the inner exception's entire ToString,
    # stack trace included, into both ErrorDetails.Message and Exception.Message, so a refused
    # connection yields twenty lines of System.Net internals wrapped around one useful
    # sentence. Keep the sentence. The full record is still on $Error[0] for anyone who wants
    # it, and Okta always answers an API error with JSON, so nothing structured is lost here.
    $fallbackSource = if ([string]::IsNullOrWhiteSpace($rawBody)) {
        $ErrorRecord.Exception.Message
    }
    else {
        $rawBody
    }
    $fallback = (@($fallbackSource -split "`r?`n") |
        Where-Object { $_.Trim() } | Select-Object -First 1)
    $fallback = if ($fallback) { $fallback.Trim() } else { 'no further detail was returned' }

    if ([string]::IsNullOrWhiteSpace($rawBody)) { return $fallback }

    $parsed = $null
    try { $parsed = $rawBody | ConvertFrom-Json } catch { return $fallback }

    if (-not $parsed) { return $fallback }

    # The token endpoint uses the OAuth error shape, everything else uses Okta's own.
    if ($parsed.PSObject.Properties['error'] -and -not $parsed.PSObject.Properties['errorSummary']) {
        $oauthParts = @($parsed.error)
        if ($parsed.PSObject.Properties['error_description']) {
            $oauthParts += $parsed.error_description
        }
        return ($oauthParts -join ': ')
    }

    $parts = @()
    if ($parsed.PSObject.Properties['errorSummary']) { $parts += $parsed.errorSummary }
    if ($parsed.PSObject.Properties['errorCauses'] -and $parsed.errorCauses) {
        $parts += @($parsed.errorCauses | ForEach-Object { $_.errorSummary })
    }
    if ($parsed.PSObject.Properties['errorCode'] -and $parsed.errorCode) {
        $parts += "[$($parsed.errorCode)]"
    }

    $message = ($parts | Where-Object { $_ }) -join ' '
    if ([string]::IsNullOrWhiteSpace($message)) { return $fallback }

    return $message
}
