function New-ADTestGroupPolicy {
    <#
    .SYNOPSIS
        Creates the companion Group Policy object that denies logon to the test service accounts.

    .DESCRIPTION
        New-ADTestServiceAccount documents that its accounts should be denied interactive,
        remote interactive and network logon, but cannot apply that itself: those are LSA
        account rights granted per machine, not attributes New-ADUser can set. This creates
        the GPO that carries them.

        The policy is deliberately narrow:

        - It is named and commented so it is obviously test data.
        - It is linked ONLY to OU=Devices,OU=TestData. User rights assignment is Computer
          Configuration, so it must be linked where the machines are; linking it over the
          ServiceAccounts OU would have no effect. It is never linked at the domain root.
        - It names only accounts found in the test ServiceAccounts OU.
        - Remove-ADEnvironment deletes it, matching on the marker in its comment as
          well as the name so it cannot remove a real policy that happens to share a name.

        User rights cannot be written through the GroupPolicy cmdlets, so the [Privilege
        Rights] section is written into the GPO's GptTmpl.inf in SYSVOL, the Security
        client-side extension is registered on the GPO object, and the version is bumped so
        clients pick the change up. The SYSVOL location is read from the GPO's
        gPCFileSysPath attribute rather than assembled by hand.

        In a test environment built by this module the computer objects are synthetic, so
        no machine actually processes the policy. It exists so that tooling which audits
        GPOs, user rights or service account hardening finds a realistic object to read.

    .PARAMETER PassThru
        Returns a PSCustomObject describing what was created.

    .EXAMPLE
        New-ADTestGroupPolicy
        Creates the deny-logon policy and links it to the test Devices OU.

    .EXAMPLE
        New-ADTestGroupPolicy -WhatIf
        Shows what would be created without making changes.

    .EXAMPLE
        $result = New-ADTestGroupPolicy -PassThru
        Creates the policy and returns the account count and link target.

    .OUTPUTS
        PSCustomObject (when -PassThru is specified)

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

        Requires the GroupPolicy module (RSAT-GPMC) and rights to create and link a GPO.
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
