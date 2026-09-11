function Invoke-FreeIPARequest {
    <#
    .SYNOPSIS
        Calls one FreeIPA API method over JSON-RPC, with session renewal and a readable error

    .DESCRIPTION
        The single path every FreeIPA call takes. FreeIPA's API is JSON-RPC at
        /ipa/session/json: one method per call, named as the CLI names it with an underscore
        (user_add, group_add_member), positional arguments as a list and options as an object,
        and the whole thing behind a session cookie. That fixes what this function has to know:

        - The API version rides in the options. The one the server reported at connect time
          is sent, so the server never has to guess forward compatibility.
        - A call always answers HTTP 200, and success or failure is in the body: 'result' on
          success, or an 'error' object with a numeric code, a name such as NotFound or
          DuplicateEntry, and a message. Callers that expect a particular failure - a show
          that may find nothing, a modify that may change nothing - name it in -IgnoreError
          and get $null back; anything else is thrown with the method, the name and the
          server's message.
        - The session expires on idle. A 401 from the endpoint means it has, so the session is
          opened again with the connection's credential and the call is repeated once.
        - A search is unbounded here. The server applies a size limit and a two-second time
          limit by default, and a listing of three hundred users would be silently truncated
          without sizelimit and timelimit set to zero, so -Find sets both.

        Dates come back as {"__datetime__": "20261210024734Z"} objects and go out as that
        string; ConvertFrom-FreeIPADateTime and ConvertTo-FreeIPADateTime handle both ends.

    .PARAMETER Method
        The API method, as the CLI names it with underscores.

    .PARAMETER Arguments
        Positional arguments: the primary key for most methods, a search string for a find.

    .PARAMETER Options
        Named options, as the CLI's flags with underscores and without the leading dashes.

    .PARAMETER Find
        Mark the call as a search: sizelimit and timelimit are set to zero unless the caller
        set them, and the array of results is returned rather than the envelope.

    .PARAMETER IgnoreError
        Error names that are an expected outcome. The call returns $null when one of them
        comes back instead of throwing.

    .PARAMETER Connection
        A connection to use instead of the active one. Tests pass one; the bootstrap passes
        the one it is in the middle of proving.

    .OUTPUTS
        System.Object. The 'result' envelope FreeIPA returned, whose 'result' property is the
        entry; or with -Find, the array of entries; or $null for an ignored error.

    .EXAMPLE
        PS> Invoke-FreeIPARequest -Method 'user_find' -Options @{ userclass = 'ZZ-TEST-seed' } -Find

        DESCRIPTION: Lists every user carrying the seed tag
        OUTPUT: An array of user entries
        USE CASE: Ownership discovery before teardown

    .EXAMPLE
        PS> Invoke-FreeIPARequest -Method 'group_add' -Arguments 'zz-test-all-staff' -Options @{ description = 'Every employee [ZZ-TEST-seed]' }

        DESCRIPTION: Creates a group
        OUTPUT: The envelope, with the group under .result
        USE CASE: Every create in the seed

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z][a-z0-9_]*$')]
        [string]$Method,

        [Parameter()]
        [object[]]$Arguments = @(),

        [Parameter()]
        [hashtable]$Options,

        [Parameter()]
        [switch]$Find,

        [Parameter()]
        [string[]]$IgnoreError = @(),

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-FreeIPAConnection }

    $requestOptions = @{}
    if ($Options) {
        foreach ($key in $Options.Keys) {
            if ($null -eq $Options[$key]) { continue }
            $requestOptions[[string]$key] = $Options[$key]
        }
    }
    if ($Connection.ApiVersion -and -not $requestOptions.ContainsKey('version')) { $requestOptions['version'] = [string]$Connection.ApiVersion }
    if ($Find) {
        if (-not $requestOptions.ContainsKey('sizelimit')) { $requestOptions['sizelimit'] = 0 }
        if (-not $requestOptions.ContainsKey('timelimit')) { $requestOptions['timelimit'] = 0 }
    }

    # The params element is always [arguments, options], and the arguments must serialise as
    # a JSON array even when there is one, which is what the unary comma protects.
    $payload = [ordered]@{
        method = $Method
        params = @(, [object[]]@($Arguments)) + @(, $requestOptions)
        id     = 0
    }
    $json = $payload | ConvertTo-Json -Depth 20 -Compress

    $attempt = 0
    while ($true) {
        $attempt++
        $response = Send-FreeIPAHttpRequest -Connection $Connection -Path '/ipa/session/json' -Json $json -Accept 'application/json'

        if ($response.StatusCode -eq 401) {
            if ($attempt -ge 2) { throw "FreeIPA $Method failed: the session could not be renewed at $($Connection.BaseUrl)." }
            Write-Verbose 'The FreeIPA session has expired; opening a new one.'
            $login = Connect-FreeIPASession -Connection $Connection
            if (-not $login.Success) {
                throw "FreeIPA $Method failed: the session expired and the credential was rejected ($($login.Reason))."
            }
            continue
        }

        if ($response.StatusCode -ne 200) {
            $firstLine = @(($response.Body -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
            throw "FreeIPA $Method failed with HTTP $($response.StatusCode): $($firstLine -join '')"
        }

        $parsed = $null
        try { $parsed = $response.Body | ConvertFrom-Json -ErrorAction Stop }
        catch { throw "FreeIPA $Method answered something that is not JSON: $($_.Exception.Message)" }

        if ($parsed.PSObject.Properties['error'] -and $parsed.error) {
            $errorName = [string]$parsed.error.name
            if ($IgnoreError -contains $errorName) {
                Write-Verbose "FreeIPA $Method answered $errorName, which the caller expected."
                return $null
            }
            throw "FreeIPA $Method failed ($errorName $($parsed.error.code)): $($parsed.error.message)"
        }

        $envelope = $parsed.result
        if ($Find) {
            $entries = @()
            if ($envelope -and $envelope.PSObject.Properties['result']) { $entries = @($envelope.result) }
            if ($envelope -and $envelope.PSObject.Properties['truncated'] -and $envelope.truncated) {
                Write-Warning "FreeIPA truncated the $Method listing at $($entries.Count) entries; the server's own limit applied."
            }
            # Returned bare, deliberately: an empty array unrolls to nothing on the pipeline,
            # and every caller wraps the call in @().
            return $entries
        }
        return $envelope
    }
}
