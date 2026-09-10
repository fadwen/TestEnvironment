function Test-AuthentikPrerequisite {
    <#
    .SYNOPSIS
        Checks that a seed can start: a connection, and every seed file present

    .DESCRIPTION
        Run once at the top of New-AuthentikEnvironment so the failures that would otherwise
        appear one step at a time appear together, before anything is created. Each problem is
        written as its own error and the function returns false, rather than throwing on the
        first, because a person fixing three missing files wants to hear about all three.

    .PARAMETER CheckDataFiles
        Verify that every seed CSV the provider reads exists.

    .OUTPUTS
        System.Boolean. True when every check passed.

    .EXAMPLE
        PS> if (-not (Test-AuthentikPrerequisite -CheckDataFiles)) { throw 'Prerequisites not met' }

        DESCRIPTION: Gates the seed on its prerequisites
        OUTPUT: One error per problem, then $false; or $true
        USE CASE: The begin block of New-AuthentikEnvironment

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

    if (-not (Get-AuthentikConnection -AllowNone)) {
        Write-Error 'Not connected to Authentik. Run Connect-TestEnvironment -Provider Authentik first.'
        $ok = $false
    }

    if ($CheckDataFiles) {
        $dataPath = Get-AuthentikDataPath
        $requiredFiles = @(
            'AuthentikGroups.csv', 'AuthentikUsers.csv', 'AuthentikRoles.csv', 'AuthentikApplications.csv', 'AuthentikOutposts.csv',
            'AuthentikScopeMappings.csv', 'AuthentikEntitlements.csv', 'AuthentikPolicies.csv',
            'AuthentikNotificationRules.csv', 'AuthentikBindings.csv', 'AuthentikTokens.csv',
            'AuthentikInvitations.csv'
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
