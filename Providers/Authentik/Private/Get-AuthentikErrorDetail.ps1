function Get-AuthentikErrorDetail {
    <#
    .SYNOPSIS
        Reduces an Authentik API error response to one readable line

    .DESCRIPTION
        Authentik answers a failed request with JSON in one of two shapes. A generic failure -
        forbidden, not found, throttled - carries a single 'detail' string. A validation
        failure carries one array of messages per offending field, sometimes alongside
        'non_field_errors', and the field name is the part that says what to fix: 'slug: This
        field must be unique' is actionable where 'Bad Request' is not.

        The body is read from ErrorDetails first, which is where PowerShell 7 puts it, and from
        the response stream on Windows PowerShell, where it can be read exactly once. Anything
        that is not JSON is reduced to its first non-blank line so an HTML error page from a
        proxy in front of Authentik does not become a screenful.

    .PARAMETER ErrorRecord
        The error Invoke-WebRequest raised.

    .OUTPUTS
        System.String. One line describing the failure.

    .EXAMPLE
        PS> Get-AuthentikErrorDetail -ErrorRecord $_

        DESCRIPTION: Turns a caught request error into its message
        OUTPUT: 'slug: application with this slug already exists.'
        USE CASE: Inside Invoke-AuthentikRequest's catch block

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
    if ($ErrorRecord.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $raw = $ErrorRecord.ErrorDetails.Message
    }
    elseif ($ErrorRecord.Exception.PSObject.Properties['Response'] -and $ErrorRecord.Exception.Response) {
        $response = $ErrorRecord.Exception.Response
        # Probed by method rather than by edition: HttpWebResponse has GetResponseStream, the
        # HttpResponseMessage PowerShell 7 raises does not, and its body is already in
        # ErrorDetails above.
        if ($response.PSObject.Methods.Name -contains 'GetResponseStream') {
            try {
                $stream = $response.GetResponseStream()
                if ($stream) {
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
                }
            }
            catch {
                Write-Verbose "Could not read the error response body: $($_.Exception.Message)"
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $ErrorRecord.Exception.Message
    }

    $parsed = $null
    try { $parsed = $raw | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }

    if ($parsed -and $parsed.PSObject.Properties['detail']) {
        return [string]$parsed.detail
    }

    if ($parsed) {
        # Field errors: every property is a field whose value is a list of messages. Joined
        # as 'field: message' so the offending field is named.
        $parts = foreach ($property in $parsed.PSObject.Properties) {
            if ($property.Name -eq 'code') { continue }
            $messages = @($property.Value | ForEach-Object { [string]$_ } | Where-Object { $_ })
            if ($messages.Count -eq 0) { continue }
            if ($property.Name -eq 'non_field_errors') { $messages -join '; ' }
            else { '{0}: {1}' -f $property.Name, ($messages -join '; ') }
        }
        if ($parts) { return ($parts -join ' | ') }
    }

    $firstLine = @($raw -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1
    if ($firstLine) { return $firstLine.Trim() }
    return $ErrorRecord.Exception.Message
}
