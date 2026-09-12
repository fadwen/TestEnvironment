function Test-FreeIPAPrerequisite {
    <#
    .SYNOPSIS
        Checks that a seed can start: a connection, and every seed file present

    .DESCRIPTION
        Run once at the top of New-FreeIPAEnvironment so the failures that would otherwise
        appear one step at a time appear together, before anything is created. Each problem is
        written as its own error and the function returns false, rather than throwing on the
        first, because a person fixing three missing files wants to hear about all three.

    .PARAMETER CheckDataFiles
        Verify that every seed CSV the provider reads exists.

    .OUTPUTS
        System.Boolean. True when every check passed.

    .EXAMPLE
        PS> if (-not (Test-FreeIPAPrerequisite -CheckDataFiles)) { throw 'Prerequisites not met' }

        DESCRIPTION: Gates the seed on its prerequisites
        OUTPUT: One error per problem, then $false; or $true
        USE CASE: The begin block of New-FreeIPAEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$CheckDataFiles
    )

    $ok = $true

    if (-not (Get-FreeIPAConnection -AllowNone)) {
        Write-Error 'Not connected to FreeIPA. Run Connect-TestEnvironment -Provider FreeIPA first.'
        $ok = $false
    }

    if ($CheckDataFiles) {
        $dataPath = Get-FreeIPADataPath
        $requiredFiles = @(
            'FreeIPAGroups.csv', 'FreeIPAUsers.csv', 'FreeIPAHostgroups.csv', 'FreeIPAHosts.csv', 'FreeIPANetgroups.csv',
            'FreeIPAHbacServices.csv', 'FreeIPAHbacRules.csv', 'FreeIPASudoCommands.csv', 'FreeIPASudoRules.csv',
            'FreeIPAPermissions.csv', 'FreeIPAPrivileges.csv', 'FreeIPARoles.csv', 'FreeIPAPasswordPolicies.csv',
            'FreeIPAServices.csv', 'FreeIPAServiceDelegation.csv', 'FreeIPAIdViews.csv', 'FreeIPAIdOverrides.csv',
            'FreeIPAOtpTokens.csv', 'FreeIPAAutomemberRules.csv', 'FreeIPAAutomount.csv', 'FreeIPASelinuxUserMaps.csv',
            'FreeIPACertMapRules.csv', 'FreeIPACaAcls.csv', 'FreeIPACertificates.csv', 'FreeIPADnsRecords.csv'
        )
        foreach ($file in $requiredFiles) {
            $fullPath = Join-Path -Path $dataPath -ChildPath $file
            if (-not (Test-Path -LiteralPath $fullPath)) {
                Write-Error "Seed file missing: $fullPath"
                $ok = $false
            }
        }
    }

    return $ok
}
