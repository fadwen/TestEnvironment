function New-TestWebRequestError {
    <#
    .SYNOPSIS
        Builds the one error shape a failed HTTP response has, on either edition

    .DESCRIPTION
        Windows PowerShell and PowerShell 7 report a failed HTTP response differently: one throws
        a WebException whose Response holds the body on a stream that can be read once, the other
        keeps the body in the error record's ErrorDetails and the status on an HttpResponseMessage.
        Every provider used to handle both. Invoke-TestWebRequest now reads the status, the headers
        and the body once, whichever way it got them, and throws this record, so a provider reads
        one shape:

        - $_.Exception.Message names the method, the URI and the status.
        - $_.Exception.Response.StatusCode is an integer, and .Headers a hashtable - which
          PowerShell keys case-insensitively - with each header's values joined by a comma and a space, so
          $_.Exception.Response.Headers['Retry-After'] reads the same on both editions.
        - $_.ErrorDetails.Message is the body, decoded as UTF-8, when there was one.

        The exception is a plain System.Exception carrying Response as an added property, not a
        WebException, whose Response is read-only and typed to a class PowerShell 7 never
        produces. A transport failure - a refused connection, a name that does not resolve - has
        no response and is never wrapped in this: Invoke-TestWebRequest lets those through
        untouched, and a provider that reads a missing Response as status 0 keeps doing so.

    .PARAMETER Method
        The HTTP method of the request that failed.

    .PARAMETER Uri
        The URI it was sent to.

    .PARAMETER StatusCode
        The HTTP status the server answered with.

    .PARAMETER StatusDescription
        The reason phrase, when one was given.

    .PARAMETER Headers
        The response headers, already normalised to a hashtable.

    .PARAMETER Body
        The decoded body, or nothing.

    .PARAMETER InnerException
        The exception the cmdlet threw, when it threw one, kept as the inner exception.

    .EXAMPLE
        PS> $PSCmdlet.ThrowTerminatingError((New-TestWebRequestError -Method GET -Uri $uri -StatusCode 429 -Headers $headers -Body $body))

        DESCRIPTION: What Invoke-TestWebRequest does with a failed response
        OUTPUT: Nothing; the caller's catch receives the record
        USE CASE: Called only by Invoke-TestWebRequest

    .OUTPUTS
        System.Management.Automation.ErrorRecord

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an error record in memory; nothing outside the process changes.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [int]$StatusCode,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$StatusDescription,

        [Parameter()]
        [AllowNull()]
        [hashtable]$Headers,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Body,

        [Parameter()]
        [AllowNull()]
        [System.Exception]$InnerException
    )

    $reason = if ([string]::IsNullOrWhiteSpace($StatusDescription)) { '' } else { " $StatusDescription" }
    $message = "$Method $Uri answered HTTP $StatusCode$reason"

    $exception = if ($InnerException) { New-Object System.Exception($message, $InnerException) } else { New-Object System.Exception($message) }
    $response = [PSCustomObject]@{
        PSTypeName        = 'TestWebResponse'
        StatusCode        = $StatusCode
        StatusDescription = $StatusDescription
        Headers           = if ($Headers) { $Headers } else { @{} }
    }
    # An added property survives the exception being handed around as a .NET object: PowerShell
    # keeps instance members it added in a table keyed by the object, so $_.Exception.Response
    # is there in the caller's catch.
    $exception | Add-Member -NotePropertyName 'Response' -NotePropertyValue $response

    $category = if ($StatusCode -eq 401 -or $StatusCode -eq 403) { [System.Management.Automation.ErrorCategory]::PermissionDenied }
    elseif ($StatusCode -eq 404) { [System.Management.Automation.ErrorCategory]::ObjectNotFound }
    elseif ($StatusCode -ge 500) { [System.Management.Automation.ErrorCategory]::ResourceUnavailable }
    else { [System.Management.Automation.ErrorCategory]::InvalidOperation }

    $record = New-Object System.Management.Automation.ErrorRecord($exception, "TestWebRequest.HTTP$StatusCode", $category, $Uri)
    if (-not [string]::IsNullOrEmpty($Body)) {
        $record.ErrorDetails = New-Object System.Management.Automation.ErrorDetails($Body)
    }
    return $record
}
