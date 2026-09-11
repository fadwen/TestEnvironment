function Get-FreeIPAEnvironmentReport {
    <#
    .SYNOPSIS
        Reads back what the seed created and renders it to the console or a file

    .DESCRIPTION
        Lists the seeded users in every lifecycle state with their memberships, class,
        authentication type and expiries, the groups with their type, GID, member counts and
        parents, the host groups with their member counts and parents, the hosts with their
        operating system, class, host groups, manager and whether anything has ever enrolled,
        the netgroups with their members, the HBAC and sudo rules with who, where and what
        they grant and whether they are on, the roles with their privileges and holders, the
        password policies by priority, the services with their indicators and the delegation
        rules and targets between them, the ID views with the hosts they apply to and every
        override inside them, the tokens with their state and expiry, the automember rules
        with their conditions, the automount keys, the SELinux maps, the certificate
        mapping rules, the CA ACLs with who they cover and the certificates the realm's CA
        issued with their status and expiry. Only objects the module can prove it owns are included, so the report
        is a picture of the seed and not of the realm.

        Console output is for a person; JSON, CSV and HTML are for a file, and each writes
        UTF-8 explicitly, because the seeded names carry accents on purpose and the default
        encoding on Windows PowerShell would destroy them.

    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV.

    .PARAMETER OutputPath
        The file to write, or for CSV the folder. Required for anything but Console.

    .PARAMETER PassThru
        Returns the report object as well.

    .OUTPUTS
        PSCustomObject. The report, when -PassThru is supplied.

    .EXAMPLE
        PS> Get-FreeIPAEnvironmentReport

        DESCRIPTION: Prints the seeded estate to the console
        OUTPUT: One table per object type
        USE CASE: A quick look after seeding

    .EXAMPLE
        PS> Get-FreeIPAEnvironmentReport -OutputFormat JSON -OutputPath ./freeipa-report.json

        DESCRIPTION: Writes the report as JSON
        OUTPUT: The file, and nothing on the pipeline
        USE CASE: Diffing the estate before and after a change

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'The console format exists to be read by a person at the console.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    if ($OutputFormat -ne 'Console' -and [string]::IsNullOrWhiteSpace($OutputPath)) {
        throw "-OutputPath is required for the $OutputFormat format."
    }

    $first = { param($value) if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } } else { if ($null -eq $value) { '' } else { [string]$value } } }
    $list = { param($value) if ($null -eq $value) { @() } else { @($value | ForEach-Object { [string]$_ }) } }
    $has = { param($entry, $name) $entry.PSObject.Properties[$name] -and $null -ne $entry.$name }
    $get = { param($entry, $name) if (& $has $entry $name) { $entry.$name } else { $null } }
    $prefixed = { param($names) @($names | Where-Object { ([string]$_).StartsWith($marker.NamePrefix, [StringComparison]::OrdinalIgnoreCase) }) }
    $withoutMarker = { param($text) ([string]$text).Replace($marker.Marker, '').Trim() }
    $classOf = { param($entry) (@(& $list (& $get $entry 'userclass') | Where-Object { $_ -ne $marker.Tag }) -join '; ') }
    $whenUtc = { param($value) $offset = ConvertFrom-FreeIPADateTime -Value $value; if ($offset) { $offset.UtcDateTime } else { $null } }

    $active = @(Get-FreeIPASeededObject -Type Users -IncludeServiceAccount -Detail -Connection $connection)
    $preserved = @(Get-FreeIPASeededObject -Type PreservedUsers -Detail -Connection $connection)
    $staged = @(Get-FreeIPASeededObject -Type StagedUsers -Detail -Connection $connection)
    $groups = @(Get-FreeIPASeededObject -Type Groups -Detail -Connection $connection)
    $hostgroups = @(Get-FreeIPASeededObject -Type Hostgroups -Detail -Connection $connection)
    $hosts = @(Get-FreeIPASeededObject -Type Hosts -Detail -Connection $connection)
    $netgroups = @(Get-FreeIPASeededObject -Type Netgroups -Detail -Connection $connection)
    $hbacRules = @(Get-FreeIPASeededObject -Type HbacRules -Detail -Connection $connection)
    $sudoRules = @(Get-FreeIPASeededObject -Type SudoRules -Detail -Connection $connection)
    $roles = @(Get-FreeIPASeededObject -Type Roles -Detail -Connection $connection)
    $policies = @(Get-FreeIPASeededObject -Type PasswordPolicies -Detail -Connection $connection)
    $services = @(Get-FreeIPASeededObject -Type Services -Detail -Connection $connection)
    $delegationRules = @(Get-FreeIPASeededObject -Type ServiceDelegationRules -Detail -Connection $connection)
    $delegationTargets = @(Get-FreeIPASeededObject -Type ServiceDelegationTargets -Detail -Connection $connection)
    $views = @(Get-FreeIPASeededObject -Type IdViews -Detail -Connection $connection)
    $tokens = @(Get-FreeIPASeededObject -Type OtpTokens -Detail -Connection $connection)
    $automemberRules = @(Get-FreeIPASeededObject -Type AutomemberRules -Detail -Connection $connection)
    $locations = @(Get-FreeIPASeededObject -Type AutomountLocations -Connection $connection)
    $selinuxMaps = @(Get-FreeIPASeededObject -Type SelinuxUserMaps -Detail -Connection $connection)
    $certMapRules = @(Get-FreeIPASeededObject -Type CertMapRules -Detail -Connection $connection)
    $caAcls = @(Get-FreeIPASeededObject -Type CaAcls -Detail -Connection $connection)
    $certificates = @(Get-FreeIPASeededObject -Type Certificates -Connection $connection)

    $joined = { param($entry, $name) ((& $list (& $get $entry $name)) -join '; ') }
    $first0 = { param($value) if ($value -is [array]) { if ($value.Count -gt 0) { [string]$value[0] } else { '' } } else { if ($null -eq $value) { '' } else { [string]$value } } }

    # A view's hosts and overrides, and a location's maps and keys, are read per object;
    # the listing does not carry them.
    $viewDetail = @{}
    foreach ($view in $views) {
        $viewName = & $first0 $view.cn
        $shown = Invoke-FreeIPARequest -Method 'idview_show' -Arguments $viewName -Options @{ show_hosts = $true } -Connection $connection -IgnoreError 'NotFound'
        $viewDetail[$viewName] = @{
            Hosts  = @(if ($shown -and $shown.result) { & $list (& $get $shown.result 'appliedtohosts') })
            Users  = @(Invoke-FreeIPARequest -Method 'idoverrideuser_find' -Arguments $viewName -Options @{ all = $true } -Find -Connection $connection)
            Groups = @(Invoke-FreeIPARequest -Method 'idoverridegroup_find' -Arguments $viewName -Options @{ all = $true } -Find -Connection $connection)
        }
    }
    $automountKeys = foreach ($location in $locations) {
        $locationName = & $first0 $location.cn
        foreach ($map in @(Invoke-FreeIPARequest -Method 'automountmap_find' -Arguments $locationName -Find -Connection $connection)) {
            $mapName = & $first0 $map.automountmapname
            foreach ($key in @(Invoke-FreeIPARequest -Method 'automountkey_find' -Arguments @($locationName, $mapName) -Find -Connection $connection)) {
                [PSCustomObject]@{
                    Location = $locationName
                    Map      = $mapName
                    Key      = (& $first0 $key.automountkey)
                    Info     = (& $first0 (& $get $key 'automountinformation'))
                }
            }
        }
    }
    # A who/where/what clause is either a category of all or the members it names.
    $clause = { param($entry, $category, $names) if ((& $first (& $get $entry $category)) -eq 'all') { 'all' } else { (@($names | ForEach-Object { & $list (& $get $entry $_) }) -join '; ') } }
    $isOn = { param($entry) $flag = & $get $entry 'ipaenabledflag'; if ($null -eq $flag) { $true } else { [bool](@($flag)[0]) } }

    $userRow = {
        param($entry, $lifecycle)
        [PSCustomObject]@{
            Login             = (& $first $entry.uid)
            Name              = (& $first (& $get $entry 'cn'))
            Lifecycle         = $lifecycle
            Class             = (& $classOf $entry)
            Title             = (& $first (& $get $entry 'title'))
            OrgUnit           = (& $first (& $get $entry 'ou'))
            Manager           = (& $first (& $get $entry 'manager'))
            Groups            = ((& $prefixed (& $list (& $get $entry 'memberof_group'))) -join '; ')
            AuthType          = ((& $list (& $get $entry 'ipauserauthtype')) -join '; ')
            PasswordExpires   = (& $whenUtc (& $get $entry 'krbpasswordexpiration'))
            PrincipalExpires  = (& $whenUtc (& $get $entry 'krbprincipalexpiration'))
            PublicKeys        = @(& $list (& $get $entry 'ipasshpubkey')).Count
        }
    }

    $groupType = {
        param($entry)
        $classes = @(& $list (& $get $entry 'objectclass'))
        if ($classes -contains 'ipaexternalgroup') { 'external' }
        elseif ($classes -contains 'posixgroup') { 'posix' }
        else { 'nonposix' }
    }

    $report = [PSCustomObject]@{
        GeneratedUtc = [DateTime]::UtcNow.ToString('o')
        BaseUrl      = $connection.BaseUrl
        Prefix       = $connection.Prefix
        AuthType     = $connection.AuthType
        Users        = @(
            @($active | ForEach-Object { & $userRow $_ $(if ((& $get $_ 'nsaccountlock') -eq $true) { 'Disabled' } else { 'Active' }) }) +
            @($preserved | ForEach-Object { & $userRow $_ 'Preserved' }) +
            @($staged | ForEach-Object { & $userRow $_ 'Staged' }) | Sort-Object Login
        )
        Groups       = @($groups | ForEach-Object {
                [PSCustomObject]@{
                    Name         = (& $first $_.cn)
                    Type         = (& $groupType $_)
                    Gid          = (& $first (& $get $_ 'gidnumber'))
                    Description  = (& $withoutMarker (& $first (& $get $_ 'description')))
                    MemberUsers  = @(& $list (& $get $_ 'member_user')).Count
                    MemberGroups = ((& $list (& $get $_ 'member_group')) -join '; ')
                    MemberOf     = ((& $prefixed (& $list (& $get $_ 'memberof_group'))) -join '; ')
                }
            } | Sort-Object Name)
        Hostgroups   = @($hostgroups | ForEach-Object {
                [PSCustomObject]@{
                    Name         = (& $first $_.cn)
                    Description  = (& $withoutMarker (& $first (& $get $_ 'description')))
                    MemberHosts  = @(& $list (& $get $_ 'member_host')).Count
                    MemberGroups = ((& $list (& $get $_ 'member_hostgroup')) -join '; ')
                    MemberOf     = ((& $prefixed (& $list (& $get $_ 'memberof_hostgroup'))) -join '; ')
                }
            } | Sort-Object Name)
        Hosts        = @($hosts | ForEach-Object {
                $fqdn = (& $first $_.fqdn)
                [PSCustomObject]@{
                    Name            = $fqdn
                    Description     = (& $withoutMarker (& $first (& $get $_ 'description')))
                    OperatingSystem = (& $first (& $get $_ 'nsosversion'))
                    Platform        = (& $first (& $get $_ 'nshardwareplatform'))
                    Locality        = (& $first (& $get $_ 'l'))
                    Class           = (& $classOf $_)
                    Hostgroups      = ((& $prefixed (& $list (& $get $_ 'memberof_hostgroup'))) -join '; ')
                    ManagedBy       = (@(& $list (& $get $_ 'managedby_host') | Where-Object { $_ -ne $fqdn }) -join '; ')
                    Enrolled        = ((& $get $_ 'has_keytab') -eq $true)
                }
            } | Sort-Object Name)
        Netgroups         = @($netgroups | ForEach-Object {
                [PSCustomObject]@{
                    Name        = (& $first $_.cn)
                    Description = (& $withoutMarker (& $first (& $get $_ 'description')))
                    Users       = (& $clause $_ 'usercategory' @('memberuser_user'))
                    Groups      = (& $joined $_ 'memberuser_group')
                    Hosts       = (& $clause $_ 'hostcategory' @('memberhost_host'))
                    Hostgroups  = (& $joined $_ 'memberhost_hostgroup')
                    Netgroups   = (& $joined $_ 'member_netgroup')
                }
            } | Sort-Object Name)
        HbacRules         = @($hbacRules | ForEach-Object {
                [PSCustomObject]@{
                    Name          = (& $first $_.cn)
                    Enabled       = (& $isOn $_)
                    Users         = (& $clause $_ 'usercategory' @('memberuser_user', 'memberuser_group'))
                    Hosts         = (& $clause $_ 'hostcategory' @('memberhost_host', 'memberhost_hostgroup'))
                    Services      = (& $clause $_ 'servicecategory' @('memberservice_hbacsvc', 'memberservice_hbacsvcgroup'))
                    Description   = (& $withoutMarker (& $first (& $get $_ 'description')))
                }
            } | Sort-Object Name)
        SudoRules         = @($sudoRules | ForEach-Object {
                [PSCustomObject]@{
                    Name          = (& $first $_.cn)
                    Enabled       = (& $isOn $_)
                    Order         = (& $first (& $get $_ 'sudoorder'))
                    Users         = (& $clause $_ 'usercategory' @('memberuser_user', 'memberuser_group'))
                    Hosts         = (& $clause $_ 'hostcategory' @('memberhost_host', 'memberhost_hostgroup'))
                    AllowCommands = (& $clause $_ 'cmdcategory' @('memberallowcmd_sudocmd', 'memberallowcmd_sudocmdgroup'))
                    DenyCommands  = (& $joined $_ 'memberdenycmd_sudocmd')
                    RunAsUsers    = (& $clause $_ 'ipasudorunasusercategory' @('ipasudorunas_user', 'ipasudorunasextuser'))
                    Options       = (& $joined $_ 'ipasudoopt')
                }
            } | Sort-Object Name)
        Roles             = @($roles | ForEach-Object {
                [PSCustomObject]@{
                    Name        = (& $first $_.cn)
                    Description = (& $withoutMarker (& $first (& $get $_ 'description')))
                    Privileges  = (& $joined $_ 'memberof_privilege')
                    Users       = (& $joined $_ 'member_user')
                    Groups      = (& $joined $_ 'member_group')
                    Hosts       = (& $joined $_ 'member_host')
                }
            } | Sort-Object Name)
        PasswordPolicies  = @($policies | ForEach-Object {
                [PSCustomObject]@{
                    Group       = (& $first $_.cn)
                    Priority    = (& $first (& $get $_ 'cospriority'))
                    MaxLife     = (& $first (& $get $_ 'krbmaxpwdlife'))
                    MinLength   = (& $first (& $get $_ 'krbpwdminlength'))
                    MinClasses  = (& $first (& $get $_ 'krbpwdmindiffchars'))
                    History     = (& $first (& $get $_ 'krbpwdhistorylength'))
                    MaxFail     = (& $first (& $get $_ 'krbpwdmaxfailure'))
                    LockoutTime = (& $first (& $get $_ 'krbpwdlockoutduration'))
                    GraceLimit  = (& $first (& $get $_ 'passwordgracelimit'))
                }
            } | Sort-Object Priority)
        Services          = @($services | ForEach-Object {
                $principal = (& $first $_.krbcanonicalname)
                [PSCustomObject]@{
                    Principal      = $principal
                    Host           = ((($principal -split '@')[0] -split '/', 2)[-1])
                    AuthIndicators = (& $joined $_ 'krbprincipalauthind')
                    ManagedBy      = (@(& $list (& $get $_ 'managedby_host') | Where-Object { $_ -ne ((($principal -split '@')[0] -split '/', 2)[-1]) }) -join '; ')
                    Enrolled       = ((& $get $_ 'has_keytab') -eq $true)
                }
            } | Sort-Object Principal)
        ServiceDelegation = @(
            @($delegationRules | ForEach-Object {
                    [PSCustomObject]@{ Kind = 'Rule'; Name = (& $first $_.cn); Members = (& $joined $_ 'memberprincipal'); Targets = (& $joined $_ 'ipaallowedtarget_servicedelegationtarget') }
                }) +
            @($delegationTargets | ForEach-Object {
                    [PSCustomObject]@{ Kind = 'Target'; Name = (& $first $_.cn); Members = (& $joined $_ 'memberprincipal'); Targets = '' }
                }) | Sort-Object Kind, Name
        )
        IdViews           = @($views | ForEach-Object {
                $viewName = (& $first $_.cn)
                [PSCustomObject]@{
                    Name           = $viewName
                    Description    = (& $withoutMarker (& $first (& $get $_ 'description')))
                    AppliedTo      = (@($viewDetail[$viewName].Hosts) -join '; ')
                    UserOverrides  = @($viewDetail[$viewName].Users).Count
                    GroupOverrides = @($viewDetail[$viewName].Groups).Count
                }
            } | Sort-Object Name)
        IdOverrides       = @(
            @(foreach ($viewName in ($viewDetail.Keys | Sort-Object)) {
                    foreach ($o in $viewDetail[$viewName].Users) {
                        [PSCustomObject]@{ View = $viewName; Kind = 'User'; Anchor = (& $first0 (& $get $o 'ipaoriginaluid')); Login = (& $first0 (& $get $o 'uid')); Uid = (& $first0 (& $get $o 'uidnumber')); Gid = (& $first0 (& $get $o 'gidnumber')); Shell = (& $first0 (& $get $o 'loginshell')); Home = (& $first0 (& $get $o 'homedirectory')) }
                    }
                    foreach ($o in $viewDetail[$viewName].Groups) {
                        [PSCustomObject]@{ View = $viewName; Kind = 'Group'; Anchor = (& $first0 (& $get $o 'ipaanchoruuid')); Login = (& $first0 (& $get $o 'cn')); Uid = ''; Gid = (& $first0 (& $get $o 'gidnumber')); Shell = ''; Home = '' }
                    }
                })
        )
        OtpTokens         = @($tokens | ForEach-Object {
                $notAfter = & $whenUtc (& $get $_ 'ipatokennotafter')
                [PSCustomObject]@{
                    Id       = (& $first $_.ipatokenuniqueid)
                    Owner    = (& $first (& $get $_ 'ipatokenowner'))
                    Type     = (& $first (& $get $_ 'type'))
                    Enabled  = -not ((& $get $_ 'ipatokendisabled') -eq $true)
                    NotAfter = $notAfter
                    Expired  = ($null -ne $notAfter -and $notAfter -lt [DateTime]::UtcNow)
                    Digits   = (& $first (& $get $_ 'ipatokenotpdigits'))
                    Vendor   = (& $first (& $get $_ 'ipatokenvendor'))
                    Model    = (& $first (& $get $_ 'ipatokenmodel'))
                }
            } | Sort-Object Id)
        AutomemberRules   = @($automemberRules | ForEach-Object {
                [PSCustomObject]@{
                    Target      = (& $first $_.cn)
                    Type        = $_.automembertype
                    Inclusive   = (& $joined $_ 'automemberinclusiveregex')
                    Exclusive   = (& $joined $_ 'automemberexclusiveregex')
                    Description = (& $withoutMarker (& $first (& $get $_ 'description')))
                }
            } | Sort-Object Type, Target)
        Automount         = @($automountKeys | Sort-Object Location, Map, Key)
        SelinuxUserMaps   = @($selinuxMaps | ForEach-Object {
                [PSCustomObject]@{
                    Name        = (& $first $_.cn)
                    SelinuxUser = (& $first (& $get $_ 'ipaselinuxuser'))
                    Enabled     = (& $isOn $_)
                    HbacRule    = (& $first (& $get $_ 'seealso'))
                    Users       = (& $clause $_ 'usercategory' @('memberuser_user', 'memberuser_group'))
                    Hosts       = (& $clause $_ 'hostcategory' @('memberhost_host', 'memberhost_hostgroup'))
                }
            } | Sort-Object Name)
        CertMapRules      = @($certMapRules | ForEach-Object {
                [PSCustomObject]@{
                    Name      = (& $first $_.cn)
                    Enabled   = (& $isOn $_)
                    Priority  = (& $first (& $get $_ 'ipacertmappriority'))
                    MatchRule = (& $first (& $get $_ 'ipacertmapmatchrule'))
                    MapRule   = (& $first (& $get $_ 'ipacertmapmaprule'))
                }
            } | Sort-Object Name)
        CaAcls            = @($caAcls | ForEach-Object {
                [PSCustomObject]@{
                    Name     = (& $first $_.cn)
                    Enabled  = (& $isOn $_)
                    Users    = (& $clause $_ 'usercategory' @('memberuser_user', 'memberuser_group'))
                    Hosts    = (& $clause $_ 'hostcategory' @('memberhost_host', 'memberhost_hostgroup'))
                    Services = (& $clause $_ 'servicecategory' @('memberservice_service'))
                    Profiles = (& $clause $_ 'ipacertprofilecategory' @('ipamembercertprofile_certprofile'))
                    CAs      = (& $clause $_ 'ipacacategory' @('ipamemberca_ca'))
                }
            } | Sort-Object Name)
        Certificates      = @($certificates | ForEach-Object {
                $notAfter = ConvertFrom-FreeIPACertificateDate -Value (& $get $_ 'valid_not_after')
                $ownerAttribute = switch ($_.ownerkind) { 'user' { 'owner_user' } 'service' { 'owner_service' } default { 'owner_host' } }
                [PSCustomObject]@{
                    Serial   = (& $first $_.serial_number)
                    Owner    = (& $first (& $get $_ $ownerAttribute))
                    Kind     = $_.ownerkind
                    Subject  = (& $first (& $get $_ 'subject'))
                    Status   = (& $first (& $get $_ 'status'))
                    Reason   = (& $first (& $get $_ 'revocation_reason'))
                    NotAfter = $notAfter
                    Expired  = ($null -ne $notAfter -and $notAfter -lt [DateTime]::UtcNow)
                }
            } | Sort-Object Kind, Owner, Serial)
    }

    switch ($OutputFormat) {
        'Console' {
            Write-TestMessage -Message "FreeIPA Test Environment Report ($($connection.BaseUrl))" -Type Header
            foreach ($section in $script:FreeIPAReportSections) {
                Write-Host "$section ($(@($report.$section).Count)):" -ForegroundColor Cyan
                if (@($report.$section).Count -gt 0) {
                    $report.$section | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
                }
                else { Write-Host '' }
            }
        }
        'JSON' {
            $json = $report | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::UTF8.GetBytes($json))
            Write-Verbose "Wrote $OutputPath"
        }
        'CSV' {
            if (-not (Test-Path -LiteralPath $OutputPath)) { $null = New-Item -ItemType Directory -Path $OutputPath -Force }
            foreach ($section in $script:FreeIPAReportSections) {
                $file = Join-Path -Path $OutputPath -ChildPath "FreeIPALab$section.csv"
                $report.$section | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
            }
            Write-Verbose "Wrote $($script:FreeIPAReportSections.Count) CSV files to $OutputPath"
        }
        'HTML' {
            $style = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 2em; color: #222; }
h1 { font-size: 1.4em; } h2 { font-size: 1.1em; margin-top: 1.5em; }
table { border-collapse: collapse; } th, td { border: 1px solid #ccc; padding: 4px 8px; text-align: left; }
th { background: #f0f0f0; }
</style>
'@
            $fragments = foreach ($section in $script:FreeIPAReportSections) {
                "<h2>$section ($(@($report.$section).Count))</h2>"
                if (@($report.$section).Count -gt 0) { $report.$section | ConvertTo-Html -Fragment }
            }
            $html = @(
                '<!DOCTYPE html><html><head><meta charset="utf-8"><title>FreeIPA Test Environment Report</title>', $style, '</head><body>'
                "<h1>FreeIPA Test Environment Report</h1><p>$($connection.BaseUrl) &middot; prefix $($connection.Prefix) &middot; generated $($report.GeneratedUtc)</p>"
                $fragments
                '</body></html>'
            ) -join "`n"
            [System.IO.File]::WriteAllBytes($OutputPath, [System.Text.Encoding]::UTF8.GetBytes($html))
            Write-Verbose "Wrote $OutputPath"
        }
    }

    if ($PassThru) { return $report }
}
