function Get-PingOneErrorDetail {
    <#
    .SYNOPSIS
        Pulls the code, message and correlation id out of a failed PingOne response

    .DESCRIPTION
        PingOne answers a failure with a body rather than a useful status code. A 400 is
        returned for a malformed request, an unsupported grant type, a duplicate name and a
        field that failed validation alike, so branching on the status alone cannot tell a
        caller which of those happened. The body carries what matters:

            {
              "id": "...", "code": "INVALID_DATA", "message": "The request could not be completed.",
              "details": [ { "code": "INVALID_VALUE", "target": "name", "message": "..." } ]
            }

        The `id` is the correlation id, and it is the only thing Ping's support can act on, so
        it is kept even though nothing in this module reads it.

        The body is in ErrorDetails.Message on both editions: Invoke-TestWebRequest reads a
        failed response once, whichever way the running PowerShell hands it over, and puts it
        there. This function turns PingOne's shape into one line.

    .PARAMETER ErrorRecord
        The error record from the failed call.

    .OUTPUTS
        PSCustomObject with Status, Code, Message, Target, CorrelationId and Summary. Summary is
        the one-line form worth putting in an exception message.

    .EXAMPLE
        PS> try { Invoke-WebRequest ... } catch { Get-PingOneErrorDetail -ErrorRecord $_ }

        DESCRIPTION: Turns a failure into something worth printing
        OUTPUT: Status 400, Code INVALID_DATA, Target name, and a summary naming all three
        USE CASE: Called by Invoke-PingOneRequest on every failure

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $status = 0
    if ($ErrorRecord.Exception.Response) {
        try { $status = [int]$ErrorRecord.Exception.Response.StatusCode } catch { $status = 0 }
    }

    # The body is in ErrorDetails on both editions: Invoke-TestWebRequest reads a failed response
    # once, with -SkipHttpErrorCheck on PowerShell 7 and from the response stream on Windows
    # PowerShell, and puts it there. Nothing here reads a stream.
    $raw = $null
    if ($ErrorRecord.ErrorDetails) { $raw = $ErrorRecord.ErrorDetails.Message }

    $code = $null
    $message = $null
    $target = $null
    $correlationId = $null

    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try {
            $parsed = $raw | ConvertFrom-Json
            $code = $parsed.code
            $message = $parsed.message
            $correlationId = $parsed.id
            if ($parsed.details) {
                $first = @($parsed.details)[0]
                $target = $first.target
                # The detail is more specific than the top-level message, which is usually the
                # useless "The request could not be completed."
                if ($first.message) { $message = $first.message }
            }
        }
        catch {
            Write-Verbose 'The error body was not JSON; using it as the message.'
            $message = ($raw -replace '\s+', ' ')
        }
    }

    if (-not $message) { $message = $ErrorRecord.Exception.Message }

    $summary = $code
    if ($target) { $summary = '{0} on {1}' -f $summary, $target }
    if ($summary) { $summary = '{0}: {1}' -f $summary, $message } else { $summary = $message }
    if ($correlationId) { $summary = '{0} (correlation id {1})' -f $summary, $correlationId }

    return [PSCustomObject]@{
        Status        = $status
        Code          = $code
        Message       = $message
        Target        = $target
        CorrelationId = $correlationId
        Summary       = $summary
    }
}
