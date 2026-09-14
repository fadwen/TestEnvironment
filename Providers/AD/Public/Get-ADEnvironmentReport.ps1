function Get-ADEnvironmentReport {
    <#
    .SYNOPSIS
        Generates a comprehensive report of the AD test environment

    .DESCRIPTION
        Reads the organizational units, users, service accounts, devices and groups under the
        seed OU, with every group's members, and reports them. Console output is for a person;
        JSON, CSV and HTML are for a file, written by the one writer every provider shares, as
        UTF-8, with CSV as a folder of one file per section. The report object is the shape
        every provider returns: Provider, Target, GeneratedOn, the domain, Counts, Sections, and
        one property per section.

    .PARAMETER OutputFormat
        Console, JSON, HTML or CSV.

    .PARAMETER OutputPath
        The file to write, or for CSV the folder. Required for anything but Console.

    .PARAMETER PassThru
        Returns the report object as well.

    .EXAMPLE
        Get-ADEnvironmentReport
        Displays a console report with complete details

    .EXAMPLE
        Get-ADEnvironmentReport -OutputFormat HTML -OutputPath "C:\Reports\ADTestReport.html"
        Writes one HTML page with a table per section

    .EXAMPLE
        Get-ADEnvironmentReport -OutputFormat CSV -OutputPath "C:\Reports\"
        Writes one ADLab<Section>.csv per section, group members included

    .EXAMPLE
        $report = Get-ADEnvironmentReport -PassThru
        The report object, for a script

    .OUTPUTS
        ADEnvironmentReport, the shape every provider returns, when -PassThru is supplied

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject], ParameterSetName = 'PassThru')]
    [OutputType([void], ParameterSetName = 'Default')]
    param(
        [ValidateSet('Console', 'JSON', 'HTML', 'CSV')]
        [string]$OutputFormat = 'Console',

        [string]$OutputPath,

        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting Get-ADEnvironmentReport - CorrelationId: $correlationId"

        # Get domain information
        $domain = Get-ADTestDomain

        if ($OutputFormat -ne 'Console' -and -not $OutputPath) {
            throw "-OutputPath is required for the $OutputFormat format."
        }
    }

    process {
        try {
            Write-TestMessage -Message "Generating Active Directory Test Data Report" -Type Header

            # Initialize report data structure
            $reportData = @{
                GeneratedOn = Get-Date
                Domain = $domain.DNSName
                CorrelationId = $correlationId
                TestOUs = @()
                TestUsers = @()
                TestServiceAccounts = @()
                TestDevices = @()
                TestGroups = @()
                GroupMembers = @()
            }

            # Collect Test OUs
            Write-TestMessage -Message "Collecting OU information..." -Type Info
            try {
                $searchBase = "OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $ouProps = 'Description', 'ProtectedFromAccidentalDeletion'
                $testOUs = Get-ADOrganizationalUnit -Filter '*' -SearchBase $searchBase -Properties $ouProps |
                    Select-Object Name, DistinguishedName, Description, ProtectedFromAccidentalDeletion,
                        @{Name='ParentOU';Expression={($_.DistinguishedName -split ',',2)[1]}}

                $reportData.TestOUs = $testOUs
            }
            catch {
                Write-Warning "Error collecting OU data: $($_.Exception.Message)"
                $reportData.TestOUs = @()
            }

            # Collect Test Users
            Write-TestMessage -Message "Collecting user information..." -Type Info
            try {
                # Get ALL properties from AD
                $searchBase = "OU=Users,OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $testUsers = Get-ADUser -Filter '*' -SearchBase $searchBase `
                    -Properties DisplayName, Department, Title, Office, Manager, Description

                $reportData.TestUsers = $testUsers
            }
            catch {
                Write-Warning "Error collecting user data: $($_.Exception.Message)"
                $reportData.TestUsers = @()
            }

            # Collect Test Service Accounts
            Write-TestMessage -Message "Collecting service account information..." -Type Info
            try {
                # Get ALL properties from AD
                $searchBase = "OU=ServiceAccounts,OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $testServiceAccounts = Get-ADUser -Filter '*' -SearchBase $searchBase `
                    -Properties Description, ServicePrincipalNames, TrustedForDelegation

                $reportData.TestServiceAccounts = $testServiceAccounts
            }
            catch {
                Write-Warning "Error collecting service account data: $($_.Exception.Message)"
                $reportData.TestServiceAccounts = @()
            }

            # Collect Test Devices
            Write-TestMessage -Message "Collecting device information..." -Type Info
            try {
                # Get ALL properties from AD
                $searchBase = "OU=Devices,OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $testDevices = Get-ADComputer -Filter '*' -SearchBase $searchBase `
                    -Properties OperatingSystem, OperatingSystemVersion, Description

                $reportData.TestDevices = $testDevices
            }
            catch {
                Write-Warning "Error collecting device data: $($_.Exception.Message)"
                $reportData.TestDevices = @()
            }

            # Collect Test Groups
            Write-TestMessage -Message "Collecting group information..." -Type Info
            try {
                # Get ALL properties from AD
                $searchBase = "OU=Groups,OU=$($script:ADTestRootName),$($domain.DomainDN)"
                $testGroups = Get-ADGroup -Filter '*' -SearchBase $searchBase -Properties Description

                # Always collect group members and add member counts
                $groupMembers = @()
                foreach ($group in $testGroups) {
                    try {
                        $getADGroupMemberArgs1 = @{
                            Identity    = $group.DistinguishedName
                            ErrorAction = 'SilentlyContinue'
                        }
                        $members = Get-ADGroupMember @getADGroupMemberArgs1
                        $countProp = @{
                            MemberType = 'NoteProperty'
                            Name       = 'MemberCount'
                            Value      = $members.Count
                            Force      = $true
                        }
                        $group | Add-Member @countProp

                        $memberSummary = $members | Select-Object Name, objectClass
                        $memberProp = @{
                            MemberType = 'NoteProperty'
                            Name       = 'Members'
                            Value      = $memberSummary
                            Force      = $true
                        }
                        $group | Add-Member @memberProp

                        # Create individual member records for the GroupMembers collection
                        foreach ($member in $members) {
                            $groupMembers += [PSCustomObject]@{
                                GroupName = $group.Name
                                GroupDistinguishedName = $group.DistinguishedName
                                MemberName = $member.Name
                                MemberType = $member.objectClass
                                MemberDistinguishedName = $member.DistinguishedName
                                    MemberSamAccountName = $member.SamAccountName
                                }
                            }
                        }
                        catch {
                            $group | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value 0 -Force
                            $group | Add-Member -MemberType NoteProperty -Name 'Members' -Value @() -Force
                        }
                    }
                    $reportData.GroupMembers = $groupMembers

                $reportData.TestGroups = $testGroups
            }
            catch {
                Write-Warning "Error collecting group data: $($_.Exception.Message)"
                $reportData.TestGroups = @()
            }

            # One shape and one file writer, shared with every provider. The AD objects are
            # projected to the columns a report reader wants rather than exported whole, because
            # a full ADUser is several hundred properties of which a handful say anything.
            $sections = [ordered]@{
                OrganizationalUnits = @($reportData.TestOUs)
                Users               = @($reportData.TestUsers | ForEach-Object {
                        [PSCustomObject]@{
                            Name              = $_.Name
                            SamAccountName    = $_.SamAccountName
                            UserPrincipalName = $_.UserPrincipalName
                            DisplayName       = $_.DisplayName
                            Department        = $_.Department
                            Title             = $_.Title
                            Office            = $_.Office
                            Enabled           = $_.Enabled
                            Manager           = $_.Manager
                            Description       = $_.Description
                            DistinguishedName = $_.DistinguishedName
                        }
                    })
                ServiceAccounts     = @($reportData.TestServiceAccounts | ForEach-Object {
                        [PSCustomObject]@{
                            Name                  = $_.Name
                            SamAccountName        = $_.SamAccountName
                            Description           = $_.Description
                            Enabled               = $_.Enabled
                            ServicePrincipalNames = @($_.ServicePrincipalNames)
                            TrustedForDelegation  = [bool]$_.TrustedForDelegation
                            DistinguishedName     = $_.DistinguishedName
                        }
                    })
                Devices             = @($reportData.TestDevices | ForEach-Object {
                        [PSCustomObject]@{
                            Name                   = $_.Name
                            OperatingSystem        = $_.OperatingSystem
                            OperatingSystemVersion = $_.OperatingSystemVersion
                            Enabled                = $_.Enabled
                            Description            = $_.Description
                            DistinguishedName      = $_.DistinguishedName
                        }
                    })
                Groups              = @($reportData.TestGroups | ForEach-Object {
                        [PSCustomObject]@{
                            Name              = $_.Name
                            GroupScope        = $_.GroupScope
                            GroupCategory     = $_.GroupCategory
                            Description       = $_.Description
                            MemberCount       = [int]$_.MemberCount
                            DistinguishedName = $_.DistinguishedName
                        }
                    })
                GroupMembers        = @($reportData.GroupMembers)
            }
            $report = New-TestEnvironmentReport -Provider 'AD' -Target $domain.DNSName -TypeName 'ADEnvironmentReport' -Section $sections `
                -Property ([ordered]@{ Domain = $domain.DNSName; CorrelationId = $correlationId })

            if ($OutputFormat -eq 'Console') {
                if ($report.Counts.OrganizationalUnits -gt 0) {
                    Write-Host "=== ORGANIZATIONAL UNITS ===" -ForegroundColor Yellow
                    $report.OrganizationalUnits | Format-Table Name, Description, ProtectedFromAccidentalDeletion -AutoSize | Out-String -Width 200 | Write-Host
                }
                if ($report.Counts.Users -gt 0) {
                    Write-Host "=== USERS ===" -ForegroundColor Yellow
                    $report.Users | Format-Table Name, Department, Title, Enabled -AutoSize | Out-String -Width 200 | Write-Host
                }
                if ($report.Counts.ServiceAccounts -gt 0) {
                    Write-Host "=== SERVICE ACCOUNTS ===" -ForegroundColor Yellow
                    $report.ServiceAccounts | Format-Table Name, SamAccountName, Description, Enabled -AutoSize | Out-String -Width 200 | Write-Host
                }
                if ($report.Counts.Devices -gt 0) {
                    Write-Host "=== DEVICES ===" -ForegroundColor Yellow
                    $report.Devices | Format-Table Name, OperatingSystem, Enabled -AutoSize | Out-String -Width 200 | Write-Host
                }
                if ($report.Counts.Groups -gt 0) {
                    Write-Host "=== SECURITY GROUPS ===" -ForegroundColor Yellow
                    $report.Groups | Format-Table Name, GroupScope, MemberCount -AutoSize | Out-String -Width 200 | Write-Host
                }
                Write-TestMessage -Message "Active Directory Test Data Report" -Type Success
                Write-Host ""
                Write-Host "Domain: $($report.Domain)" -ForegroundColor Cyan
                Write-Host "Generated: $($report.GeneratedOn)" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "=== SUMMARY ===" -ForegroundColor Yellow
                foreach ($property in $report.Counts.PSObject.Properties) {
                    Write-Host ("Total {0}: {1}" -f $property.Name, $property.Value) -ForegroundColor Green
                }
                Write-Host ""
            }
            else {
                Export-TestEnvironmentReport -Report $report -OutputFormat $OutputFormat -OutputPath $OutputPath `
                    -FilePrefix 'ADLab' -Title 'Active Directory Test Environment Report' -Note @("Domain $($domain.DNSName)")
            }

            if ($PassThru) { return $report }

        } catch {
            Write-Error "Failed to generate report: $($_.Exception.Message)" -ErrorAction Stop
        }
    }

    end {
        Write-Verbose "Completed Get-ADEnvironmentReport - CorrelationId: $correlationId"
    }
}
