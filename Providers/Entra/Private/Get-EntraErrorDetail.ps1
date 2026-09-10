function Get-EntraErrorDetail {
    <#
    .SYNOPSIS
        Extracts the useful part of a failed Graph or token endpoint response

    .DESCRIPTION
        Graph returns its diagnosis in the response body - error.code, error.message and a
        request id - and the token endpoint uses a different shape again, with
        error_description carrying the AADSTS code that actually identifies the problem.
        PowerShell surfaces neither by default: Windows PowerShell throws away the body of a
        failed response entirely, and PowerShell 7 keeps it only in ErrorDetails.

        Both editions are handled, and the request id is included whenever Graph sends one.
        That id is the only thing Microsoft support can correlate against their side, so
        discarding it turns a supportable failure into an anecdote.

    .PARAMETER ErrorRecord
        The error record caught from Invoke-WebRequest

    .OUTPUTS
        System.String. A single-line description.

    .EXAMPLE
        PS> Get-EntraErrorDetail -ErrorRecord $_

        DESCRIPTION: Turns a failed response into something worth putting in an exception
        OUTPUT: Authorization_RequestDenied: Insufficient privileges to complete the operation. (request-id 3f2a...)
        USE CASE: Called from the catch block in Invoke-EntraRequest

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $raw = $null

    # PowerShell 7 path: the body is kept here and the stream has already been consumed.
    if ($ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $raw = $ErrorRecord.ErrorDetails.Message
    }

    # Windows PowerShell path: read the response stream directly, because the body is not
    # attached to the error record at all.
    if (-not $raw -and $ErrorRecord.Exception.PSObject.Properties['Response'] -and $ErrorRecord.Exception.Response) {
        try {
            $stream = $ErrorRecord.Exception.Response.GetResponseStream()
            if ($stream) {
                $stream.Position = 0
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
        }
        catch {
            Write-Verbose "Could not read the error response stream: $($_.Exception.Message)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($raw)) { return $ErrorRecord.Exception.Message }

    try {
        $parsed = $raw | ConvertFrom-Json
    }
    catch {
        # Not JSON - a proxy or a gateway error page. Collapse it so one bad response cannot
        # paste an entire HTML document into an exception message.
        $flat = ($raw -replace '\s+', ' ').Trim()
        if ($flat.Length -gt 400) { $flat = $flat.Substring(0, 400) + '...' }
        return $flat
    }

    # Graph shape
    if ($parsed.PSObject.Properties['error'] -and $parsed.error -isnot [string]) {
        $text = '{0}: {1}' -f $parsed.error.code, $parsed.error.message
        if ($parsed.error.PSObject.Properties['innerError'] -and $parsed.error.innerError.PSObject.Properties['request-id']) {
            $text += " (request-id $($parsed.error.innerError.'request-id'))"
        }
        return $text
    }

    # Token endpoint shape
    if ($parsed.PSObject.Properties['error_description']) {
        return (($parsed.error_description -replace '\s+', ' ').Trim())
    }
    if ($parsed.PSObject.Properties['error']) {
        return [string]$parsed.error
    }

    return (($raw -replace '\s+', ' ').Trim())
}
