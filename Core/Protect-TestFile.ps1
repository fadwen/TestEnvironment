function Protect-TestFile {
    <#
    .SYNOPSIS
        Restricts a file or folder to the current user

    .DESCRIPTION
        A credential record's folder is locked down before anything sensitive lands in it, and
        the record again after it is written. On Windows that is an ACL with inheritance broken
        and a single full-control entry for the current user; elsewhere it is chmod 700 for a
        folder and 600 for a file. Either way this is defence in depth behind the encryption,
        and the only defence where the platform could not encrypt.

    .PARAMETER Path
        The file or folder to restrict.

    .OUTPUTS
        System.Boolean. Whether the permissions were changed.

    .EXAMPLE
        PS> Protect-TestFile -Path $recordPath -Confirm:$false

        DESCRIPTION: Locks the record down to the current user
        OUTPUT: $true
        USE CASE: A provider's Export-<Provider>Credential, after writing

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        Write-Warning "Cannot restrict permissions on '$Path' because it does not exist."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($Path, 'Restrict access to the current user only')) {
        return $false
    }

    $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or
        ($PSVersionTable.PSObject.Properties['Platform'] -and $PSVersionTable.Platform -eq 'Win32NT') -or
        ($env:OS -eq 'Windows_NT')

    try {
        if ($onWindows) {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $item = Get-Item -LiteralPath $Path -Force
            $isContainer = $item -is [System.IO.DirectoryInfo]

            # Only the access section is read and written. Get-Acl and Set-Acl carry the
            # owner and audit sections too, and writing those back needs SeSecurityPrivilege,
            # which an ordinary session does not hold - the call then fails and the file
            # keeps its inherited permissions, with a warning nobody can act on.
            #
            # On Windows PowerShell the methods are on FileInfo and DirectoryInfo. On PowerShell 7
            # they are extension methods in FileSystemAclExtensions, which PowerShell does not
            # bind as instance members, so they are called by class where that class exists.
            $sections = [System.Security.AccessControl.AccessControlSections]::Access
            $extensions = 'System.IO.FileSystemAclExtensions' -as [type]
            $acl = if ($extensions) { $extensions::GetAccessControl($item, $sections) } else { $item.GetAccessControl($sections) }
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($rule in @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
                $null = $acl.RemoveAccessRule($rule)
            }
            $inheritance = if ($isContainer) { 'ContainerInherit, ObjectInherit' } else { 'None' }
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $identity, 'FullControl', $inheritance, 'None', 'Allow')
            $acl.SetAccessRule($rule)
            if ($extensions) { $extensions::SetAccessControl($item, $acl) } else { $item.SetAccessControl($acl) }
        }
        else {
            $chmod = @(Get-Command -Name chmod -CommandType Application -ErrorAction SilentlyContinue |
                    Select-Object -First 1)
            if ($chmod.Count -eq 0) {
                Write-Warning "chmod was not found, so '$Path' keeps its inherited permissions."
                return $false
            }
            $mode = if (Test-Path -Path $Path -PathType Container) { '700' } else { '600' }
            & $chmod[0].Source $mode $Path
            if ($LASTEXITCODE -ne 0) { throw "chmod $mode exited with $LASTEXITCODE" }
        }
        return $true
    }
    catch {
        Write-Warning "Could not restrict permissions on '$Path': $($_.Exception.Message)"
        return $false
    }
}
