function Write-TestProgress {
    <#
    .SYNOPSIS
        Reports seeding progress without writing to the host

    .DESCRIPTION
        Seeding a full environment is several hundred Graph calls over a minute or two, and
        during a live run against a tenant somebody is actually using, silence is not
        reassuring.

        Progress goes to Write-Progress, which the caller can suppress, and the same message
        goes to Write-Verbose so it lands in a transcript where a progress bar does not.
        Neither is Write-Host: an automated caller running this in a pipeline needs the
        output stream clean, and Write-Host cannot be redirected on Windows PowerShell 5.1.

    .PARAMETER Activity
        The step being performed, used as the progress bar title

    .PARAMETER Status
        What is happening right now

    .PARAMETER PercentComplete
        Completion between 0 and 100. Omit when the total is not known in advance.

    .PARAMETER Completed
        Clears the progress bar

    .PARAMETER ShowProgress
        Whether to draw a progress bar at all. The seeding functions pass their own switch
        straight through, so a caller can turn it off in one place.

    .OUTPUTS
        None

    .EXAMPLE
        PS> Write-TestProgress -Activity 'Seeding users' -Status 'Ada Whitfield' -PercentComplete 30 -ShowProgress

        DESCRIPTION: Updates the progress bar and writes the same line to the verbose stream
        OUTPUT: None
        USE CASE: Called from inside each seeding loop

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,

        [Parameter()]
        [string]$Status = ' ',

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$PercentComplete = -1,

        [Parameter()]
        [switch]$Completed,

        [Parameter()]
        [switch]$ShowProgress
    )

    Write-Verbose "$Activity - $Status"

    if (-not $ShowProgress) { return }

    if ($Completed) {
        Write-Progress -Activity $Activity -Completed
        return
    }

    if ($PercentComplete -ge 0) {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    }
    else {
        Write-Progress -Activity $Activity -Status $Status
    }
}
