function Set-ADTestPolicyUserRight {
    <#
    .SYNOPSIS
        Writes user rights assignments into a Group Policy object.

    .DESCRIPTION
        The GroupPolicy module can set registry-backed policy but has no cmdlet for User
        Rights Assignment, so this writes the [Privilege Rights] section of the GPO's
        security template directly and then does the three things the cmdlets would
        otherwise have done:

        1. Writes GptTmpl.inf under Machine\Microsoft\Windows NT\SecEdit.
        2. Registers the Security client-side extension in gPCMachineExtensionNames, or a
           client has no reason to read the file.
        3. Bumps the computer half of the version, in both the directory and GPT.INI, or
           clients treat the policy as unchanged.

        Accounts are written as SIDs prefixed with an asterisk, which is the form secedit
        uses and the only form that survives a renamed or moved account.

        The SYSVOL location comes from the GPO's own gPCFileSysPath attribute rather than
        being assembled from the domain name, so it stays correct on a member server and
        wherever SYSVOL actually lives.

    .PARAMETER PolicyId
        GUID of the Group Policy object to write into.

    .PARAMETER Right
        The privilege constants to assign, for example SeDenyNetworkLogonRight.

    .PARAMETER Account
        Directory objects to name in each right. Anything exposing a SID works.

    .EXAMPLE
        Set-ADTestPolicyUserRight -PolicyId $gpo.Id -Right 'SeDenyNetworkLogonRight' -Account $users

    .OUTPUTS
        None.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$PolicyId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Right,

        [Parameter(Mandatory = $true)]
        [object[]]$Account
    )

    $sids = @($Account | ForEach-Object { $_.SID.Value } | Where-Object { $_ } | Sort-Object -Unique)
    if ($sids.Count -eq 0) {
        throw 'No usable SIDs in the supplied accounts'
    }

    $adPath = "CN={$PolicyId},CN=Policies,CN=System,$((Get-ADDomain).DistinguishedName)"
    $props = 'gPCFileSysPath', 'gPCMachineExtensionNames', 'versionNumber'
    $gpoObject = Get-ADObject -Identity $adPath -Properties $props -ErrorAction Stop

    $secEdit = Join-Path $gpoObject.gPCFileSysPath 'Machine\Microsoft\Windows NT\SecEdit'
    $template = Join-Path $secEdit 'GptTmpl.inf'

    if (-not $PSCmdlet.ShouldProcess($template, 'Write user rights')) {
        return
    }

    if (-not (Test-Path -LiteralPath $secEdit)) {
        $null = New-Item -Path $secEdit -ItemType Directory -Force
    }

    $accountList = ($sids | ForEach-Object { "*$_" }) -join ','
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('[Unicode]')
    $lines.Add('Unicode=yes')
    $lines.Add('[Version]')
    $lines.Add('signature="$CHICAGO$"')
    $lines.Add('Revision=1')
    $lines.Add('[Privilege Rights]')
    foreach ($privilege in $Right) {
        $lines.Add("$privilege = $accountList")
    }

    # secedit reads this as Unicode; writing it as anything else produces a template the
    # client silently ignores.
    [System.IO.File]::WriteAllLines($template, $lines, [System.Text.UnicodeEncoding]::new($false, $true))

    # Register the Security CSE so a client knows to read what was just written. The pair
    # is {CSE}{snap-in}; appending would duplicate it on a second run.
    $securityCse = '[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]'
    $currentCse = [string]$gpoObject.gPCMachineExtensionNames
    if ($currentCse -notlike "*827D319E-6EAC-11D2-A4EA-00C04F79F83A*") {
        Set-ADObject -Identity $adPath -Replace @{
            gPCMachineExtensionNames = ($currentCse + $securityCse)
        } -ErrorAction Stop
    }

    # Computer settings live in the low word of versionNumber. Incrementing by one is what
    # the console does for a computer-side edit.
    $newVersion = [int]$gpoObject.versionNumber + 1
    Set-ADObject -Identity $adPath -Replace @{ versionNumber = $newVersion } -ErrorAction Stop

    $gptIni = Join-Path $gpoObject.gPCFileSysPath 'GPT.INI'
    if (Test-Path -LiteralPath $gptIni) {
        $ini = Get-Content -LiteralPath $gptIni
        $ini = $ini | ForEach-Object {
            if ($_ -match '^\s*Version\s*=') { "Version=$newVersion" } else { $_ }
        }
        Set-Content -LiteralPath $gptIni -Value $ini -Encoding ASCII
    }
    else {
        Set-Content -LiteralPath $gptIni -Value @('[General]', "Version=$newVersion") -Encoding ASCII
    }

    Write-Verbose "Wrote $($Right.Count) right(s) naming $($sids.Count) account(s) to $template"
}
