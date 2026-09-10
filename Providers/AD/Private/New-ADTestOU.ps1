function New-ADTestOU {
    <#
    .SYNOPSIS
        Creates an Active Directory OU with WhatIf support

    .DESCRIPTION
        Helper function to create OUs with consistent error handling and WhatIf support

    .PARAMETER Name
        Name of the OU to create

    .PARAMETER Path
        Parent path where the OU should be created

    .PARAMETER Description
        Description for the OU

    .PARAMETER Unprotected
        Creates the OU without accidental deletion protection.

        New-ADOrganizationalUnit turns that protection on by default, and a protected child
        blocks a recursive delete of its parent. Pass this for OUs that a teardown is
        expected to remove as part of a subtree - the edge case tree is the case that needs
        it. Left off, the behaviour is unchanged: the OU is protected.

    .EXAMPLE
        New-ADTestOU -Name "TestUsers" -Path "DC=contoso,DC=com" -Description "Test user accounts"

        DESCRIPTION: Creates a protected OU
        OUTPUT: Hashtable with Success, Action, Message and DistinguishedName

    .EXAMPLE
        New-ADTestOU -Name "EdgeCases" -Path $testDataOU -Description "Disposable" -Unprotected

        DESCRIPTION: Creates an OU a recursive teardown can remove
        OUTPUT: Hashtable with Success, Action, Message and DistinguishedName

    .OUTPUTS
        System.Collections.Hashtable

        Success, Action ('Created', 'Skipped', 'WhatIf' or 'Failed'), Message, and
        DistinguishedName. DistinguishedName is returned whatever the action, so a caller
        that needs the path does not have to rebuild it.

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.1.0
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter()]
        [switch]$Unprotected
    )

    $fullPath = "OU=$Name,$Path"

    try {
        if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$fullPath'" -ErrorAction SilentlyContinue)) {
            if ($PSCmdlet.ShouldProcess($fullPath, "Create OU")) {
                $ouParam = @{
                    Name        = $Name
                    Path        = $Path
                    Description = $Description

                    # Every object this module creates carries the seed tag here, including the
                    # containers. adminDescription is base schema and on top, so one attribute
                    # covers organisational units, users, computers and groups alike.
                    OtherAttributes = @{ adminDescription = (Get-ADTestSeedMarker).Tag }
                }

                if ($Unprotected) {
                    $ouParam['ProtectedFromAccidentalDeletion'] = $false
                }

                New-ADOrganizationalUnit @ouParam
                Write-Verbose "Created OU: $Name"
                return @{
                    Success = $true; Action = 'Created'
                    Message = "OU created: $Name"; DistinguishedName = $fullPath
                }
            } else {
                return @{
                    Success = $true; Action = 'WhatIf'
                    Message = "Would create OU: $Name"; DistinguishedName = $fullPath
                }
            }
        } else {
            Write-Verbose "OU already exists: $Name"
            return @{
                Success = $true; Action = 'Skipped'
                Message = "OU already exists: $Name"; DistinguishedName = $fullPath
            }
        }
    } catch {
        Write-Error "Failed to create OU '$Name': $($_.Exception.Message)"
        return @{
            Success = $false; Action = 'Failed'
            Message = "Failed to create OU '$Name': $($_.Exception.Message)"
            DistinguishedName = $fullPath
        }
    }
}
