function Get-TestRuntime {
    <#
    .SYNOPSIS
        Detects the PowerShell the module is running on and decides, once, which methods it uses

    .DESCRIPTION
        The module targets Windows PowerShell 5.1, because a freshly built domain controller has
        nothing else, and PowerShell 7.4, which the REST providers are better served by. The two
        differ in what Invoke-WebRequest can do and in what it gets wrong, and every place that
        cares used to test $PSVersionTable for itself. This is now the one place the edition is
        read, and what it returns is what the rest of the module acts on.

        Each capability is detected on the cmdlet, never inferred from a version number: a
        parameter that exists is one that works on whatever build this is, and a version check
        would be wrong the day a backport or a preview moved one. The result is computed on
        first use and cached in module scope, because it cannot change for the life of the
        session.

        What is decided here:

        - Http.ErrorBody: how the body of a failed response is read. 'SkipHttpErrorCheck' where
          Invoke-WebRequest has that switch (PowerShell 7), so a 4xx or 5xx comes back as a
          response and the body is read like any other; 'ResponseStream' on Windows PowerShell,
          where the cmdlet throws and the body has to be pulled from the exception's response
          stream, once, because the stream cannot be read twice.
        - Not HTTP/2, deliberately. -HttpVersion exists from PowerShell 7.3 and was tried: a
          core-tier PingOne seed measured 25 seconds with it and 25 without, twice each, so it
          is not requested and not listed. A capability that changes nothing is noise.
        - Http.Tls: 'Default' on PowerShell 7, whose HttpClient negotiates TLS 1.2 and 1.3 on
          its own; 'Tls12Added' on Windows PowerShell, which can still default to TLS 1.0 and
          has TLS 1.2 added to the enabled set, never removing any.
        - Http.Encoding and Http.Progress are the same on both editions and are listed so the
          object says everything the HTTP layer does: the body always goes out as UTF-8 bytes
          and the response is always decoded from its raw bytes, because Windows PowerShell
          corrupts both silently and PowerShell 7 merely hides that; and the progress bar is
          suppressed around every call, which on Windows PowerShell costs more than the call.
        - Parallel: 'RunspacePool' on both. Invoke-TestParallel runs a block over many items on
          a pool of runspaces with the module loaded, which is the mechanism ForEach-Object
          -Parallel is built on and is available on Windows PowerShell 5.1.
        - Preferred and Recommendation: whether this is the PowerShell the module is best run
          on, and one sentence saying so. PowerShell 7.4 or later is preferred for every
          provider; Windows PowerShell 5.1 is supported because a freshly built domain
          controller has nothing else, and the Active Directory provider is at home there.
          Said here, in the object, so a run on the slower edition can see it without reading
          the help.

    .PARAMETER Refresh
        Detect again rather than returning the cached result. For tests.

    .EXAMPLE
        PS> (Get-TestRuntime).Http.ErrorBody

        DESCRIPTION: Which way a failed response's body is read on this host
        OUTPUT: SkipHttpErrorCheck on PowerShell 7, ResponseStream on Windows PowerShell
        USE CASE: Called by Invoke-TestWebRequest on every call, from the cache

    .OUTPUTS
        PSCustomObject of type TestEnvironmentRuntime: Edition, Version, Platform, Preferred,
        Recommendation, Capability (one boolean per detected feature), Http, Parallel.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$Refresh
    )

    if ($script:TestEnvironmentRuntime -and -not $Refresh) { return $script:TestEnvironmentRuntime }

    # $PSVersionTable is a hashtable: a key it lacks reads as null, and Windows PowerShell 5.0
    # lacks PSEdition altogether.
    $edition = if ($PSVersionTable['PSEdition']) { [string]$PSVersionTable['PSEdition'] } else { 'Desktop' }
    $version = [version]$PSVersionTable['PSVersion']
    $platform = if ($edition -eq 'Desktop') { 'Windows' }
    elseif ($PSVersionTable['Platform'] -eq 'Win32NT') { 'Windows' }
    elseif ([string]$PSVersionTable['OS'] -match 'Darwin') { 'macOS' }
    elseif ($PSVersionTable['Platform'] -eq 'Unix') { 'Linux' }
    else { 'Unknown' }

    $webRequest = @((Get-Command -Name Invoke-WebRequest -CommandType Cmdlet -ErrorAction Stop).Parameters.Keys)
    $fromJson = @((Get-Command -Name ConvertFrom-Json -CommandType Cmdlet -ErrorAction Stop).Parameters.Keys)

    $capability = [PSCustomObject]@{
        SkipHttpErrorCheck = ($webRequest -contains 'SkipHttpErrorCheck')
        HttpTimeouts       = ($webRequest -contains 'ConnectionTimeoutSeconds')
        JsonAsHashtable    = ($fromJson -contains 'AsHashtable')
        ModernTls          = ($edition -eq 'Core')
        NativeUtf8         = ($edition -eq 'Core')
    }

    $http = [PSCustomObject]@{
        ErrorBody = if ($capability.SkipHttpErrorCheck) { 'SkipHttpErrorCheck' } else { 'ResponseStream' }
        Tls       = if ($capability.ModernTls) { 'Default' } else { 'Tls12Added' }
        Encoding  = 'Utf8Bytes'
        Progress  = 'Suppressed'
    }

    $preferred = ($edition -eq 'Core' -and $version -ge [version]'7.4')
    $recommendation = if ($preferred) {
        'PowerShell 7.4 or later: the preferred PowerShell for every provider.'
    }
    elseif ($edition -eq 'Core') {
        'PowerShell 7.4 or later is preferred; this build has the same HTTP paths and is supported.'
    }
    else {
        'Windows PowerShell 5.1 is supported and is what a freshly built domain controller has; the Entra, Okta, Authentik, FreeIPA and PingOne providers are better served by PowerShell 7.4 or later.'
    }

    $script:TestEnvironmentRuntime = [PSCustomObject]@{
        PSTypeName     = 'TestEnvironmentRuntime'
        Edition        = $edition
        Version        = $version
        Platform       = $platform
        Preferred      = $preferred
        Recommendation = $recommendation
        Capability     = $capability
        Http           = $http
        Parallel       = 'RunspacePool'
    }
    Write-Verbose ("Running on PowerShell $version ($edition, $platform): failed HTTP bodies read by " +
        "$($http.ErrorBody), TLS $($http.Tls)")
    return $script:TestEnvironmentRuntime
}
