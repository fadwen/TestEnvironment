function Confirm-TestTeardown {
    <#
    .SYNOPSIS
        Asks the one teardown question, and reads a session that cannot answer as a refusal

    .DESCRIPTION
        Every provider's teardown asks once, for the whole run, whether to go ahead. The question
        is asked through the calling cmdlet's ShouldContinue, which is the only prompt that -Force
        can bypass without also bypassing -WhatIf: ShouldProcess is still called per object, and
        still returns false under -WhatIf.

        A session with no host to answer - a scheduled task, a CI runner, a job - throws from
        ShouldContinue rather than returning false. That is a refusal, not an agreement: an
        unattended teardown has to say -Force. This is the one place that rule lives, so every
        provider's teardown behaves the same way and a test can mock the answer instead of relying
        on the host it happens to run under. A suite that relied on the host once hung a developer's
        terminal: the test expected an unanswerable prompt, and the terminal answered by waiting.

    .PARAMETER Cmdlet
        The calling cmdlet's $PSCmdlet, whose ShouldContinue asks the question.

    .PARAMETER Question
        What is about to be removed, and where.

    .PARAMETER Caption
        The prompt's title, naming the provider.

    .OUTPUTS
        System.Boolean. True only when the question was asked and answered yes.

    .EXAMPLE
        PS> if (-not (Confirm-TestTeardown -Cmdlet $PSCmdlet -Question $prompt -Caption 'Remove Okta test environment')) { return }

        DESCRIPTION: Stops a teardown the operator did not confirm
        OUTPUT: False when refused, or when nobody could answer
        USE CASE: The guard at the top of every Remove-*Environment, skipped under -Force and -WhatIf

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Cmdlet,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Question,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Caption
    )

    try {
        return [bool]$Cmdlet.ShouldContinue($Question, $Caption)
    }
    catch {
        Write-Verbose "The confirmation could not be asked, so the teardown is treated as refused: $($_.Exception.Message)"
        return $false
    }
}
