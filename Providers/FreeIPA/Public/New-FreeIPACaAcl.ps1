function New-FreeIPACaAcl {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the seeded certificate authority access control rules from Data\FreeIPACaAcls.csv
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$AclName,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-FreeIPAConnection
    $marker = Get-FreeIPASeedMarker -Connection $connection

    $csvPath = Join-Path -Path (Get-FreeIPADataPath) -ChildPath 'FreeIPACaAcls.csv'
    $rows = @(Import-Csv -Path $csvPath -Encoding UTF8)
    if ($AclName) {
        $rows = @($rows | Where-Object { $AclName -contains $_.Name })
        $unknown = @($AclName | Where-Object { $rows.Name -notcontains $_ })
        if ($unknown) { throw "No definition in $csvPath for: $($unknown -join ', ')" }
    }

    $result = [PSCustomObject]@{
        TotalAcls          = $rows.Count
        CreatedAcls        = 0
        UpdatedAcls        = 0
        MembershipsApplied = 0
        Acls               = @()
        Errors             = @()
    }

    $split = { param($value) @([string]$value -split ';' | Where-Object { $_ }) }
    $named = { param($key) Resolve-FreeIPASeedName -Key $key -Marker $marker -Connection $connection }
    $hostNamed = { param($key) Resolve-FreeIPASeedName -Key $key -Kind Host -Marker $marker -Connection $connection }
    # 'HTTP/web01' -> 'HTTP/zz-test-web01.ipa.example.com@IPA.EXAMPLE.COM'
    $serviceNamed = {
        param($key)
        $type, $hostKey = $key -split '/', 2
        $principal = '{0}/{1}' -f $type, (& $hostNamed $hostKey)
        if ($connection.Realm) { '{0}@{1}' -f $principal, $connection.Realm } else { $principal }
    }
    # A profile or a CA is only ever a stock object, and the row has to say so.
    $builtin = {
        param($value, $what)
        @(& $split $value | ForEach-Object {
                if ($_ -notlike 'builtin:*') { throw "A $what can only be referenced as builtin:<name>; got '$_'." }
                $_.Substring(8)
            })
    }

    $existing = @{}
    foreach ($entry in (Get-FreeIPASeededObject -Type CaAcls -Connection $connection)) { $existing[[string](@($entry.cn)[0])] = $entry }

    $acls = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $name = & $named $row.Name
        if (-not $PSCmdlet.ShouldProcess($name, 'Create FreeIPA CA ACL')) { continue }
        try {
            $options = @{ description = ('{0} {1}' -f $row.Description, $marker.Marker).Trim() }
            foreach ($category in @(
                    @{ Column = 'UserCategory'; Option = 'usercategory' }, @{ Column = 'HostCategory'; Option = 'hostcategory' },
                    @{ Column = 'ServiceCategory'; Option = 'servicecategory' }, @{ Column = 'ProfileCategory'; Option = 'ipacertprofilecategory' },
                    @{ Column = 'CaCategory'; Option = 'ipacacategory' })) {
                if ($row.($category.Column) -eq 'all') { $options[$category.Option] = 'all' }
            }

            if ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'caacl_mod' -Arguments $name -Options $options -Connection $connection -IgnoreError 'EmptyModlist'
                $result.UpdatedAcls++
            }
            else {
                $null = Invoke-FreeIPARequest -Method 'caacl_add' -Arguments $name -Options $options -Connection $connection
                $result.CreatedAcls++
                Write-Verbose "Created CA ACL $name"
            }

            $members = @(
                @{ Method = 'caacl_add_user'; Members = @{ user = @(& $split $row.Users); group = @(& $split $row.Groups | ForEach-Object { & $named $_ }) } }
                @{ Method = 'caacl_add_host'; Members = @{ host = @(& $split $row.Hosts | ForEach-Object { & $hostNamed $_ }); hostgroup = @(& $split $row.Hostgroups | ForEach-Object { & $named $_ }) } }
                @{ Method = 'caacl_add_service'; Members = @{ service = @(& $split $row.Services | ForEach-Object { & $serviceNamed $_ }) } }
                @{ Method = 'caacl_add_profile'; Members = @{ certprofile = @(& $builtin $row.Profiles 'certificate profile') } }
                @{ Method = 'caacl_add_ca'; Members = @{ ca = @(& $builtin $row.Cas 'certificate authority') } }
            )
            foreach ($membership in $members) {
                $any = @($membership.Members.Values | ForEach-Object { $_ }).Count -gt 0
                if (-not $any) { continue }
                $added = Add-FreeIPAMember -Method $membership.Method -Name $name -Members $membership.Members -Connection $connection
                $result.MembershipsApplied += $added.Completed
                foreach ($problem in $added.Errors) {
                    $result.Errors += "CA ACL '$name': $problem"
                    Write-Error "CA ACL '$name': $problem"
                }
            }

            if ($row.Enabled -eq 'FALSE') {
                $null = Invoke-FreeIPARequest -Method 'caacl_disable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyInactive'
            }
            elseif ($existing.ContainsKey($name)) {
                $null = Invoke-FreeIPARequest -Method 'caacl_enable' -Arguments $name -Connection $connection -IgnoreError 'AlreadyActive'
            }

            $acls.Add([PSCustomObject]@{ Key = $row.Name; Name = $name; Enabled = ($row.Enabled -ne 'FALSE') })
        }
        catch {
            $message = "Failed to create CA ACL '$name': $($_.Exception.Message)"
            $result.Errors += $message
            Write-Error $message
        }
    }

    $result.Acls = $acls.ToArray()
    Write-Verbose "CA ACLs: $($result.CreatedAcls) created, $($result.UpdatedAcls) updated, $($result.MembershipsApplied) memberships, $($result.Errors.Count) problems"
    if ($PassThru) { return $result }
}
