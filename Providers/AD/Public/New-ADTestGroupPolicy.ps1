function New-ADTestGroupPolicy {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Creates the companion Group Policy object that denies logon to the test service accounts.
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colour-coded console progress is intentional; results are returned as objects.')]
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $correlationId = [System.Guid]::NewGuid()
        Write-Verbose "Starting New-ADTestGroupPolicy - CorrelationId: $correlationId"

        $domain = Get-ADTestDomain
        $policy = Get-ADTestPolicySetting -DomainDN $domain.DomainDN

        $result = [PSCustomObject]@{
            CorrelationId = $correlationId
            Name          = $policy.Name
            Created       = $false
            Linked        = $false
            AccountCount  = 0
            LinkTarget    = $policy.LinkTarget
            Errors        = @()
            Warnings      = @()
        }
    }

    process {
        try {
            Write-TestMessage -Message 'Creating test deny-logon Group Policy' -Type Header

            try {
                Import-Module GroupPolicy -ErrorAction Stop -Verbose:$false
            }
            catch {
                $msg = 'GroupPolicy module not available - install RSAT-GPMC to create ' +
                       'the companion policy'
                Write-Warning $msg
                $result.Warnings += $msg
                return
            }

            # The policy is meaningless without machines to apply to, and linking it
            # somewhere else would widen its scope beyond the test data.
            $linkOU = Get-ADOrganizationalUnit -Identity $policy.LinkTarget -ErrorAction SilentlyContinue
            if (-not $linkOU) {
                $msg = "Link target not found: $($policy.LinkTarget). Create the OU " +
                       'structure before the policy.'
                Write-Warning $msg
                $result.Warnings += $msg
                return
            }

            $accounts = @(Get-ADUser -Filter * -SearchBase $policy.AccountOU -ErrorAction SilentlyContinue)
            $result.AccountCount = $accounts.Count

            if ($accounts.Count -eq 0) {
                $msg = 'No service accounts found; the policy would name nobody'
                Write-Warning $msg
                $result.Warnings += $msg
                return
            }

            Write-TestMessage -Message "Denying logon to $($accounts.Count) service accounts..." -Type Info

            $existing = Get-GPO -Name $policy.Name -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Verbose "Policy '$($policy.Name)' already exists - reusing it"
                $gpo = $existing
            }
            elseif ($PSCmdlet.ShouldProcess($policy.Name, 'Create Group Policy object')) {
                $gpo = New-GPO -Name $policy.Name -Comment $policy.Comment -ErrorAction Stop
                $result.Created = $true
                Write-Verbose "Created GPO $($gpo.Id)"
            }
            else {
                # Under -WhatIf there is no object to configure, so stop here rather than
                # reporting work that did not happen.
                return
            }

            if ($PSCmdlet.ShouldProcess($policy.LinkTarget, "Link GPO '$($policy.Name)'")) {
                $alreadyLinked = $false
                $inheritance = Get-GPInheritance -Target $policy.LinkTarget -ErrorAction SilentlyContinue
                if ($inheritance) {
                    $alreadyLinked = @($inheritance.GpoLinks |
                        Where-Object { $_.DisplayName -eq $policy.Name }).Count -gt 0
                }

                if (-not $alreadyLinked) {
                    $null = New-GPLink -Guid $gpo.Id -Target $policy.LinkTarget -LinkEnabled Yes -ErrorAction Stop
                }
                $result.Linked = $true
                Write-Verbose "Linked to $($policy.LinkTarget)"
            }

            if ($PSCmdlet.ShouldProcess($policy.Name, 'Write deny-logon user rights')) {
                Set-ADTestPolicyUserRight -PolicyId $gpo.Id -Right $policy.Right -Account $accounts
                Write-Verbose "Wrote $($policy.Right.Count) deny-logon rights"
            }

            Write-Host "  Policy: $($policy.Name)" -ForegroundColor Green
            Write-Host "  Linked to: $($policy.LinkTarget)" -ForegroundColor Green
            Write-Host "  Accounts denied logon: $($accounts.Count)" -ForegroundColor Green
        }
        catch {
            $errorMsg = "Failed to create test Group Policy: $($_.Exception.Message)"
            $result.Errors += $errorMsg
            Write-Error $errorMsg
        }
    }

    end {
        if ($PassThru) {
            return $result
        }
    }
}
