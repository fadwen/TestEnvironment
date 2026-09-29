function Get-OneLoginErrorDetail {
    <#
    .SYNOPSIS
        Pulls the status, error name and message out of a failed OneLogin response

    .DESCRIPTION
        OneLogin answers a failure in one of three shapes, depending on which generation of its
        API served the request, and all three were seen against a live account:

            {"name":"UnprocessableEntityError","message":"Validation failed: ...","statusCode":422}
            {"status":404,"error":"NotFoundError","description":"Resource not found"}
            {"status":{"error":true,"code":400,"type":"bad request","message":"..."}}

        The first is what the users and custom attribute endpoints send, the second what roles
        send, and the third the version 1 API. A malformed request can also be answered with an
        HTML error page rather than JSON, which is reduced to its status. This turns every shape
        into one line.

        The body is in ErrorDetails.Message on both editions: Invoke-TestWebRequest reads a failed
        response once, whichever way the running PowerShell hands it over, and puts it there.

    .PARAMETER ErrorRecord
        The error record from the failed call.

    .OUTPUTS
        PSCustomObject with Status, Code, Message, RetryAfterSeconds and Summary. Summary is the
        one-line form worth putting in an exception message.

    .EXAMPLE
        PS> try { Invoke-TestWebRequest ... } catch { Get-OneLoginErrorDetail -ErrorRecord $_ }

        DESCRIPTION: Turns a failure into something worth printing
        OUTPUT: Status 422, Code UnprocessableEntityError, and a summary naming both
        USE CASE: Called by Invoke-OneLoginRequest on every failure

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
    $headers = @{}
    if ($ErrorRecord.Exception.PSObject.Properties['Response'] -and $ErrorRecord.Exception.Response) {
        try { $status = [int]$ErrorRecord.Exception.Response.StatusCode } catch { $status = 0 }
        if ($ErrorRecord.Exception.Response.PSObject.Properties['Headers'] -and
            $ErrorRecord.Exception.Response.Headers -is [System.Collections.IDictionary]) {
            $headers = $ErrorRecord.Exception.Response.Headers
        }
    }

    $raw = $null
    if ($ErrorRecord.ErrorDetails) { $raw = $ErrorRecord.ErrorDetails.Message }

    $code = $null
    $message = $null

    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        if ($raw.TrimStart().StartsWith('<')) {
            # An HTML error page. Nothing in it is worth quoting; the status says as much.
            $message = 'OneLogin answered with an HTML error page rather than JSON'
        }
        else {
            try {
                $parsed = $raw | ConvertFrom-Json
                if ($parsed.PSObject.Properties['status'] -and $parsed.status -is [PSCustomObject]) {
                    $code = [string]$parsed.status.type
                    $message = [string]$parsed.status.message
                    if (-not $status -and $parsed.status.code) { $status = [int]$parsed.status.code }
                }
                else {
                    if ($parsed.PSObject.Properties['name']) { $code = [string]$parsed.name }
                    elseif ($parsed.PSObject.Properties['error']) { $code = [string]$parsed.error }
                    if ($parsed.PSObject.Properties['message']) { $message = [string]$parsed.message }
                    elseif ($parsed.PSObject.Properties['description']) { $message = [string]$parsed.description }
                    if (-not $status) {
                        if ($parsed.PSObject.Properties['statusCode']) { $status = [int]$parsed.statusCode }
                        elseif ($parsed.PSObject.Properties['status'] -and $parsed.status -is [ValueType]) { $status = [int]$parsed.status }
                    }
                }
            }
            catch {
                Write-Verbose 'The error body was not JSON; using it as the message.'
                $message = ($raw -replace '\s+', ' ')
            }
        }
    }

    if (-not $message) { $message = $ErrorRecord.Exception.Message }

    # How long a 429 asks to be left alone. Retry-After is the standard header; OneLogin also
    # reports the seconds until its hourly window resets.
    $retryAfter = $null
    foreach ($name in 'Retry-After', 'X-RateLimit-Reset') {
        $value = 0
        if ($headers.ContainsKey($name) -and [int]::TryParse([string]$headers[$name], [ref]$value)) {
            $retryAfter = $value
            break
        }
    }

    $summary = if ($code) { '{0}: {1}' -f $code, $message } else { $message }

    return [PSCustomObject]@{
        Status            = $status
        Code              = $code
        Message           = $message
        RetryAfterSeconds = $retryAfter
        Summary           = $summary
    }
}
