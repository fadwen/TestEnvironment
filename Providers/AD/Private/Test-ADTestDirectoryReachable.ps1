function Test-ADTestDirectoryReachable {
    <#
    .SYNOPSIS
        Answers whether the pinned domain controller is still responding

    .DESCRIPTION
        One cheap query against the domain controller the connection is pinned to, used to
        tell "this step failed" apart from "the directory has gone". They need different
        handling: the first is worth reporting and carrying on from, the second means every
        remaining step will fail the same way and the run should stop.

        This exists because of a real seeding run that lost its domain controller after the
        devices step and then reported the same error twenty-five times for the service
        accounts, once more for the groups, and again for the policies, before finishing
        with a summary that said four of seven steps succeeded. The directory was left
        half-built and the failure that mattered was buried.

    .OUTPUTS
        System.Boolean.

    .EXAMPLE
        PS> Test-ADTestDirectoryReachable

        DESCRIPTION: Checks the pinned controller after a step failed
        OUTPUT: $false if it has stopped answering
        USE CASE: Called by New-ADEnvironment to decide whether to stop the run

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # The same question Select-ADTestServer asks a candidate, so "reachable" means the
        # same thing at both ends of a run. The pin supplies -Server.
        $null = Get-ADDomain -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose "The directory did not answer: $($_.Exception.Message)"
        return $false
    }
}
