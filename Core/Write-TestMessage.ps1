function Write-TestMessage {
    <#
    .SYNOPSIS
        Writes a formatted console message during a seeding or teardown run

    .DESCRIPTION
        The running commentary a long operation prints: which step it is on, what it skipped,
        what went wrong. Distinct from Write-TestProgress, which drives the progress bar - this
        writes lines a person reads afterwards in a transcript.

        The AD and Okta providers arrived with a copy of this each, identical down to the
        colours and the row of equals signs around a header, under two names that did not look
        related. That is the whole argument for Core in one function: neither copy was wrong,
        and keeping both would have meant changing a colour twice.

        Write-Host is deliberate rather than an oversight. The output is a running commentary
        for a human watching a five-minute operation, and it must not land in the pipeline where
        a caller assigning the result would silently collect it.

    .PARAMETER Message
        The text to write.

    .PARAMETER Type
        How to present it. Header wraps the message in rules; the rest are colour only.

    .EXAMPLE
        PS> Write-TestMessage -Message 'Step 2: Creating User Accounts' -Type Info

        DESCRIPTION: Writes a step heading in green
        OUTPUT: Step 2: Creating User Accounts
        USE CASE: Called throughout the seeding orchestrators

    .EXAMPLE
        PS> Write-TestMessage -Message 'Active Directory Test Environment Creation' -Type Header

        DESCRIPTION: Writes a banner bounded by rules
        OUTPUT: The message between two rows of equals signs, in cyan
        USE CASE: The start of a multi-step operation

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console commentary is the entire purpose of this function. Write-Output would put it in the pipeline, where a caller assigning a result would silently collect it.')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Header')]
        [string]$Type = 'Info'
    )

    switch ($Type) {
        'Header' {
            Write-Host "`n=========================================" -ForegroundColor Cyan
            Write-Host "   $Message" -ForegroundColor Cyan
            Write-Host "=========================================" -ForegroundColor Cyan
        }
        'Info' { Write-Host $Message -ForegroundColor Green }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error' { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}
