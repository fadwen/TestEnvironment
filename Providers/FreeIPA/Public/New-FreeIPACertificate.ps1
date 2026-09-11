function New-FreeIPACertificate {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Has the realm's CA issue the seeded certificates from Data\FreeIPACertificates.csv, and revokes the ones the data says are revoked
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$CertificateKey,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPACertificates.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($CertificateKey) {
        $rows = @($rows | Where-Object { $CertificateKey -contains $_.Key })
        $unknown = @($CertificateKey | Where-Object { $rows.Key -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalCertificates = $rows.Count
        Issued            = 0
        Revoked           = 0
        Existing          = 0
        Certificates      = @()
        Errors            = @()
    }

    if ([string]::IsNullOrWhiteSpace($connection.Realm)) {
        throw 'The connection carries no realm, so a certificate subject cannot be built.'
    }

    $first = { param($value) if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } } else { if ($null -eq $value) { '' } else { [string]$value } } }
    $hostNamed = { param($key) Resolve-FreeIPASeedName -Key $key -Kind Host -Marker $marker -Connection $connection }

    # What the CA is asked for depends on the kind: the login or the host name as the common
    # name, the realm as the organisation, and the principal the realm checks it against.
    $describe = {
        param($row)
        switch ($row.Kind) {
            'User' {
                $uid = $row.Principal
                @{ Principal = ('{0}@{1}' -f $uid, $connection.Realm); CommonName = $uid; Search = @{ user = @($uid) }; Owner = $uid; HostName = $null }
            }
            'Service' {
                $type, $hostKey = $row.Principal -split '/', 2
                $fqdn = & $hostNamed $hostKey
                $principal = '{0}/{1}@{2}' -f $type, $fqdn, $connection.Realm
                @{ Principal = $principal; CommonName = $fqdn; Search = @{ service = @($principal) }; Owner = $principal; HostName = $fqdn }
            }
            'Host' {
                $fqdn = & $hostNamed $row.Principal
                @{ Principal = ('host/{0}@{1}' -f $fqdn, $connection.Realm); CommonName = $fqdn; Search = @{ host = @($fqdn) }; Owner = $fqdn; HostName = $fqdn }
            }
            default { throw "Unknown certificate kind '$($row.Kind)' on row '$($row.Key)'." }
        }
    }

    $certificates = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $wanted = if ($row.State -eq 'Revoked') { 'REVOKED' } else { 'VALID' }
        try {
            $target = & $describe $row
        }
        catch {
            $result.Errors += $_.Exception.Message
            Write-Error $_.Exception.Message
            continue
        }
        if (-not $PSCmdlet.ShouldProcess("$($target.Principal) ($($row.State))", 'Issue FreeIPA certificate')) { continue }

        try {
            if ($row.Profile -notlike 'builtin:*') { throw "A certificate profile can only be referenced as builtin:<name>; got '$($row.Profile)'." }
            $profileId = $row.Profile.Substring(8)

            # Already there in the state the row asks for: nothing to ask the CA.
            $searchOptions = @{ all = $true }
            foreach ($key in $target.Search.Keys) { $searchOptions[$key] = [object[]]$target.Search[$key] }
            $held = @(Invoke-FreeIPARequest -Method 'cert_find' -Options $searchOptions -Find -Connection $connection)
            $match = @($held | Where-Object { (& $first $_.status) -eq $wanted } | Select-Object -First 1)
            if ($match.Count -gt 0) {
                $result.Existing++
                $certificates.Add([PSCustomObject]@{
                        Key       = $row.Key; Principal = $target.Principal; Serial = (& $first $match[0].serial_number)
                        Subject   = (& $first $match[0].subject); State = $row.State
                        NotAfter  = (ConvertFrom-FreeIPACertificateDate -Value $match[0].valid_not_after)
                    })
                continue
            }

            $dnsNames = @()
            $emails = @()
            if ($row.SanDns -eq 'TRUE' -and $target.HostName) { $dnsNames = @($target.HostName) }
            if ($row.SanEmail -eq 'TRUE' -and $row.Kind -eq 'User') {
                # The realm checks an email in the request against the user's own.
                $shown = Invoke-FreeIPARequest -Method 'user_show' -Arguments $row.Principal -Connection $connection
                $mail = & $first $(if ($shown.result.PSObject.Properties['mail']) { $shown.result.mail } else { $null })
                if ($mail) { $emails = @($mail) }
            }

            $csr = New-FreeIPACertificateRequest -Subject ('CN={0},O={1}' -f $target.CommonName, $connection.Realm) -DnsName $dnsNames -EmailAddress $emails
            $issued = Invoke-FreeIPARequest -Method 'cert_request' -Arguments $csr -Connection $connection -Options @{
                principal  = $target.Principal
                profile_id = $profileId
                add        = $true
            }
            $result.Issued++
            $serial = & $first $issued.result.serial_number
            Write-Verbose "Issued certificate $serial to $($target.Principal)"

            if ($wanted -eq 'REVOKED') {
                $reason = if ($row.RevocationReason -match '^\d+$') { [int]$row.RevocationReason } else { 0 }
                $null = Invoke-FreeIPARequest -Method 'cert_revoke' -Arguments $serial -Options @{ revocation_reason = $reason } -Connection $connection
                $result.Revoked++
                Write-Verbose "Revoked certificate $serial (reason $reason)"
            }

            $certificates.Add([PSCustomObject]@{
                    Key       = $row.Key; Principal = $target.Principal; Serial = $serial
                    Subject   = (& $first $issued.result.subject); State = $row.State
                    NotAfter  = (ConvertFrom-FreeIPACertificateDate -Value $issued.result.valid_not_after)
                })
        }
        catch {
            $message = "Failed to issue certificate '$($row.Key)' to $($target.Principal): $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Certificates = $certificates.ToArray()
    Write-Verbose "Certificates: $($result.Issued) issued, $($result.Revoked) revoked, $($result.Existing) already there, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
