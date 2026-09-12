# GENERATED FILE - do not edit by hand. See Tests/Stubs/README.md.
#
# A stand-in for a module the CI runner does not have, so the suite can import
# ADTestEnvironment and Pester can mock commands that would otherwise not exist.
# Every function is empty: it exists only to reproduce the real binding surface,
# so a call the real cmdlet would reject fails here too. Parameter types are
# carried over wherever the type ships with PowerShell itself.
#
# The suppressions below are the point of the file, not an oversight. The
# parameters are deliberately unused, and a body-less function can neither
# handle a password nor call ShouldProcess.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
    Justification = 'Stub parameters reproduce real cmdlet binding surfaces.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
    Justification = 'Stubs have no body to guard; the attribute mirrors the real cmdlet.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '',
    Justification = 'Mirrors the real cmdlet parameter set; the stub stores nothing.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
    Justification = 'Mirrors the real cmdlet parameter set; the stub stores nothing.')]
param()

function Add-ADFineGrainedPasswordPolicySubject {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Identity,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$Server,
        $Subjects
    )
}

function Add-ADGroupMember {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.Management.Automation.SwitchParameter]$DisablePermissiveModify,
        $Identity,
        $Members,
        [System.Nullable[System.TimeSpan]]$MemberTimeToLive,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$Server
    )
}

function Get-ADComputer {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.String]$LDAPFilter,
        [System.String]$Partition,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server
    )
}

function Get-ADDomain {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Current,
        $Identity,
        [System.String]$Server
    )
}

function Get-ADFineGrainedPasswordPolicy {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.String]$LDAPFilter,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server
    )
}

function Get-ADGroup {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.String]$LDAPFilter,
        [System.String]$Partition,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server,
        [System.Management.Automation.SwitchParameter]$ShowMemberTimeToLive
    )
}

function Get-ADGroupMember {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Identity,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$Recursive,
        [System.String]$Server
    )
}

function Get-ADObject {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.Management.Automation.SwitchParameter]$IncludeDeletedObjects,
        [System.String]$LDAPFilter,
        [System.String]$Partition,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server
    )
}

function Get-ADOrganizationalUnit {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.String]$LDAPFilter,
        [System.String]$Partition,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server
    )
}

function Get-ADUser {
    [CmdletBinding()]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Filter,
        $Identity,
        [System.String]$LDAPFilter,
        [System.String]$Partition,
        [System.String[]]$Properties,
        [System.Int32]$ResultPageSize,
        [System.Nullable[System.Int32]]$ResultSetSize,
        [System.String]$SearchBase,
        $SearchScope,
        [System.String]$Server
    )
}

function New-ADComputer {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Nullable[System.DateTime]]$AccountExpirationDate,
        [System.Nullable[System.Boolean]]$AccountNotDelegated,
        [System.Security.SecureString]$AccountPassword,
        [System.Nullable[System.Boolean]]$AllowReversiblePasswordEncryption,
        $AuthenticationPolicy,
        $AuthenticationPolicySilo,
        $AuthType,
        [System.Nullable[System.Boolean]]$CannotChangePassword,
        $Certificates,
        [System.Nullable[System.Boolean]]$ChangePasswordAtLogon,
        [System.Nullable[System.Boolean]]$CompoundIdentitySupported,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        [System.String]$DNSHostName,
        [System.Nullable[System.Boolean]]$Enabled,
        [System.String]$HomePage,
        $Instance,
        $KerberosEncryptionType,
        [System.String]$Location,
        $ManagedBy,
        [System.String]$Name,
        [System.String]$OperatingSystem,
        [System.String]$OperatingSystemHotfix,
        [System.String]$OperatingSystemServicePack,
        [System.String]$OperatingSystemVersion,
        [System.Collections.Hashtable]$OtherAttributes,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Nullable[System.Boolean]]$PasswordNeverExpires,
        [System.Nullable[System.Boolean]]$PasswordNotRequired,
        [System.String]$Path,
        $PrincipalsAllowedToDelegateToAccount,
        [System.String]$SAMAccountName,
        [System.String]$Server,
        [System.String[]]$ServicePrincipalNames,
        [System.Nullable[System.Boolean]]$TrustedForDelegation,
        [System.String]$UserPrincipalName
    )
}

function New-ADFineGrainedPasswordPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Nullable[System.Boolean]]$ComplexityEnabled,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $Instance,
        [System.Nullable[System.TimeSpan]]$LockoutDuration,
        [System.Nullable[System.TimeSpan]]$LockoutObservationWindow,
        [System.Nullable[System.Int32]]$LockoutThreshold,
        [System.Nullable[System.TimeSpan]]$MaxPasswordAge,
        [System.Nullable[System.TimeSpan]]$MinPasswordAge,
        [System.Nullable[System.Int32]]$MinPasswordLength,
        [System.String]$Name,
        [System.Collections.Hashtable]$OtherAttributes,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Nullable[System.Int32]]$PasswordHistoryCount,
        [System.Nullable[System.Int32]]$Precedence,
        [System.Nullable[System.Boolean]]$ProtectedFromAccidentalDeletion,
        [System.Nullable[System.Boolean]]$ReversibleEncryptionEnabled,
        [System.String]$Server
    )
}

function New-ADGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $GroupCategory,
        $GroupScope,
        [System.String]$HomePage,
        $Instance,
        $ManagedBy,
        [System.String]$Name,
        [System.Collections.Hashtable]$OtherAttributes,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$Path,
        [System.String]$SamAccountName,
        [System.String]$Server
    )
}

function New-ADObject {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $Instance,
        [System.String]$Name,
        [System.Collections.Hashtable]$OtherAttributes,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$Path,
        [System.Nullable[System.Boolean]]$ProtectedFromAccidentalDeletion,
        [System.String]$Server,
        [System.String]$Type
    )
}

function New-ADOrganizationalUnit {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.String]$City,
        [System.String]$Country,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $Instance,
        $ManagedBy,
        [System.String]$Name,
        [System.Collections.Hashtable]$OtherAttributes,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$Path,
        [System.String]$PostalCode,
        [System.Nullable[System.Boolean]]$ProtectedFromAccidentalDeletion,
        [System.String]$Server,
        [System.String]$State,
        [System.String]$StreetAddress
    )
}

function New-ADUser {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Nullable[System.DateTime]]$AccountExpirationDate,
        [System.Nullable[System.Boolean]]$AccountNotDelegated,
        [System.Security.SecureString]$AccountPassword,
        [System.Nullable[System.Boolean]]$AllowReversiblePasswordEncryption,
        $AuthenticationPolicy,
        $AuthenticationPolicySilo,
        $AuthType,
        [System.Nullable[System.Boolean]]$CannotChangePassword,
        $Certificates,
        [System.Nullable[System.Boolean]]$ChangePasswordAtLogon,
        [System.String]$City,
        [System.String]$Company,
        [System.Nullable[System.Boolean]]$CompoundIdentitySupported,
        [System.String]$Country,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Department,
        [System.String]$Description,
        [System.String]$DisplayName,
        [System.String]$Division,
        [System.String]$EmailAddress,
        [System.String]$EmployeeID,
        [System.String]$EmployeeNumber,
        [System.Nullable[System.Boolean]]$Enabled,
        [System.String]$Fax,
        [System.String]$GivenName,
        [System.String]$HomeDirectory,
        [System.String]$HomeDrive,
        [System.String]$HomePage,
        [System.String]$HomePhone,
        [System.String]$Initials,
        $Instance,
        $KerberosEncryptionType,
        [System.String]$LogonWorkstations,
        $Manager,
        [System.String]$MobilePhone,
        [System.String]$Name,
        [System.String]$Office,
        [System.String]$OfficePhone,
        [System.String]$Organization,
        [System.Collections.Hashtable]$OtherAttributes,
        [System.String]$OtherName,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Nullable[System.Boolean]]$PasswordNeverExpires,
        [System.Nullable[System.Boolean]]$PasswordNotRequired,
        [System.String]$Path,
        [System.String]$POBox,
        [System.String]$PostalCode,
        $PrincipalsAllowedToDelegateToAccount,
        [System.String]$ProfilePath,
        [System.String]$SamAccountName,
        [System.String]$ScriptPath,
        [System.String]$Server,
        [System.String[]]$ServicePrincipalNames,
        [System.Nullable[System.Boolean]]$SmartcardLogonRequired,
        [System.String]$State,
        [System.String]$StreetAddress,
        [System.String]$Surname,
        [System.String]$Title,
        [System.Nullable[System.Boolean]]$TrustedForDelegation,
        [System.String]$Type,
        [System.String]$UserPrincipalName
    )
}

function Remove-ADComputer {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Identity,
        [System.String]$Partition,
        [System.String]$Server
    )
}

function Remove-ADFineGrainedPasswordPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Identity,
        [System.String]$Server
    )
}

function Remove-ADGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Identity,
        [System.String]$Partition,
        [System.String]$Server
    )
}

function Remove-ADOrganizationalUnit {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Identity,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$Recursive,
        [System.String]$Server
    )
}

function Remove-ADUser {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        $AuthType,
        [System.Management.Automation.PSCredential]$Credential,
        $Identity,
        [System.String]$Partition,
        [System.String]$Server
    )
}

function Set-ADComputer {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Nullable[System.DateTime]]$AccountExpirationDate,
        [System.Nullable[System.Boolean]]$AccountNotDelegated,
        [System.Collections.Hashtable]$Add,
        [System.Nullable[System.Boolean]]$AllowReversiblePasswordEncryption,
        $AuthenticationPolicy,
        $AuthenticationPolicySilo,
        $AuthType,
        [System.Nullable[System.Boolean]]$CannotChangePassword,
        [System.Collections.Hashtable]$Certificates,
        [System.Nullable[System.Boolean]]$ChangePasswordAtLogon,
        [System.String[]]$Clear,
        [System.Nullable[System.Boolean]]$CompoundIdentitySupported,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        [System.String]$DNSHostName,
        [System.Nullable[System.Boolean]]$Enabled,
        [System.String]$HomePage,
        $Identity,
        $Instance,
        $KerberosEncryptionType,
        [System.String]$Location,
        $ManagedBy,
        [System.String]$OperatingSystem,
        [System.String]$OperatingSystemHotfix,
        [System.String]$OperatingSystemServicePack,
        [System.String]$OperatingSystemVersion,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Nullable[System.Boolean]]$PasswordNeverExpires,
        [System.Nullable[System.Boolean]]$PasswordNotRequired,
        $PrincipalsAllowedToDelegateToAccount,
        [System.Collections.Hashtable]$Remove,
        [System.Collections.Hashtable]$Replace,
        [System.String]$SAMAccountName,
        [System.String]$Server,
        [System.Collections.Hashtable]$ServicePrincipalNames,
        [System.Nullable[System.Boolean]]$TrustedForDelegation,
        [System.String]$UserPrincipalName
    )
}

function Set-ADFineGrainedPasswordPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Collections.Hashtable]$Add,
        $AuthType,
        [System.String[]]$Clear,
        [System.Nullable[System.Boolean]]$ComplexityEnabled,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $Identity,
        $Instance,
        [System.Nullable[System.TimeSpan]]$LockoutDuration,
        [System.Nullable[System.TimeSpan]]$LockoutObservationWindow,
        [System.Nullable[System.Int32]]$LockoutThreshold,
        [System.Nullable[System.TimeSpan]]$MaxPasswordAge,
        [System.Nullable[System.TimeSpan]]$MinPasswordAge,
        [System.Nullable[System.Int32]]$MinPasswordLength,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Nullable[System.Int32]]$PasswordHistoryCount,
        [System.Nullable[System.Int32]]$Precedence,
        [System.Nullable[System.Boolean]]$ProtectedFromAccidentalDeletion,
        [System.Collections.Hashtable]$Remove,
        [System.Collections.Hashtable]$Replace,
        [System.Nullable[System.Boolean]]$ReversibleEncryptionEnabled,
        [System.String]$Server
    )
}

function Set-ADGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Collections.Hashtable]$Add,
        $AuthType,
        [System.String[]]$Clear,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $GroupCategory,
        $GroupScope,
        [System.String]$HomePage,
        $Identity,
        $Instance,
        $ManagedBy,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Collections.Hashtable]$Remove,
        [System.Collections.Hashtable]$Replace,
        [System.String]$SamAccountName,
        [System.String]$Server
    )
}

function Set-ADObject {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Collections.Hashtable]$Add,
        $AuthType,
        [System.String[]]$Clear,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $Identity,
        $Instance,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Nullable[System.Boolean]]$ProtectedFromAccidentalDeletion,
        [System.Collections.Hashtable]$Remove,
        [System.Collections.Hashtable]$Replace,
        [System.String]$Server
    )
}

function Set-ADOrganizationalUnit {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Collections.Hashtable]$Add,
        $AuthType,
        [System.String]$City,
        [System.String[]]$Clear,
        [System.String]$Country,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Description,
        [System.String]$DisplayName,
        $Identity,
        $Instance,
        $ManagedBy,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$PostalCode,
        [System.Nullable[System.Boolean]]$ProtectedFromAccidentalDeletion,
        [System.Collections.Hashtable]$Remove,
        [System.Collections.Hashtable]$Replace,
        [System.String]$Server,
        [System.String]$State,
        [System.String]$StreetAddress
    )
}

function Set-ADUser {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Nullable[System.DateTime]]$AccountExpirationDate,
        [System.Nullable[System.Boolean]]$AccountNotDelegated,
        [System.Collections.Hashtable]$Add,
        [System.Nullable[System.Boolean]]$AllowReversiblePasswordEncryption,
        $AuthenticationPolicy,
        $AuthenticationPolicySilo,
        $AuthType,
        [System.Nullable[System.Boolean]]$CannotChangePassword,
        [System.Collections.Hashtable]$Certificates,
        [System.Nullable[System.Boolean]]$ChangePasswordAtLogon,
        [System.String]$City,
        [System.String[]]$Clear,
        [System.String]$Company,
        [System.Nullable[System.Boolean]]$CompoundIdentitySupported,
        [System.String]$Country,
        [System.Management.Automation.PSCredential]$Credential,
        [System.String]$Department,
        [System.String]$Description,
        [System.String]$DisplayName,
        [System.String]$Division,
        [System.String]$EmailAddress,
        [System.String]$EmployeeID,
        [System.String]$EmployeeNumber,
        [System.Nullable[System.Boolean]]$Enabled,
        [System.String]$Fax,
        [System.String]$GivenName,
        [System.String]$HomeDirectory,
        [System.String]$HomeDrive,
        [System.String]$HomePage,
        [System.String]$HomePhone,
        $Identity,
        [System.String]$Initials,
        $Instance,
        $KerberosEncryptionType,
        [System.String]$LogonWorkstations,
        $Manager,
        [System.String]$MobilePhone,
        [System.String]$Office,
        [System.String]$OfficePhone,
        [System.String]$Organization,
        [System.String]$OtherName,
        [System.String]$Partition,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Nullable[System.Boolean]]$PasswordNeverExpires,
        [System.Nullable[System.Boolean]]$PasswordNotRequired,
        [System.String]$POBox,
        [System.String]$PostalCode,
        $PrincipalsAllowedToDelegateToAccount,
        [System.String]$ProfilePath,
        [System.Collections.Hashtable]$Remove,
        [System.Collections.Hashtable]$Replace,
        [System.String]$SamAccountName,
        [System.String]$ScriptPath,
        [System.String]$Server,
        [System.Collections.Hashtable]$ServicePrincipalNames,
        [System.Nullable[System.Boolean]]$SmartcardLogonRequired,
        [System.String]$State,
        [System.String]$StreetAddress,
        [System.String]$Surname,
        [System.String]$Title,
        [System.Nullable[System.Boolean]]$TrustedForDelegation,
        [System.String]$UserPrincipalName
    )
}

Export-ModuleMember -Function @(
    'Add-ADFineGrainedPasswordPolicySubject',
    'Add-ADGroupMember',
    'Get-ADComputer',
    'Get-ADDomain',
    'Get-ADFineGrainedPasswordPolicy',
    'Get-ADGroup',
    'Get-ADGroupMember',
    'Get-ADObject',
    'Get-ADOrganizationalUnit',
    'Get-ADUser',
    'New-ADComputer',
    'New-ADFineGrainedPasswordPolicy',
    'New-ADGroup',
    'New-ADObject',
    'New-ADOrganizationalUnit',
    'New-ADUser',
    'Remove-ADComputer',
    'Remove-ADFineGrainedPasswordPolicy',
    'Remove-ADGroup',
    'Remove-ADOrganizationalUnit',
    'Remove-ADUser',
    'Set-ADComputer',
    'Set-ADFineGrainedPasswordPolicy',
    'Set-ADGroup',
    'Set-ADObject',
    'Set-ADOrganizationalUnit',
    'Set-ADUser'
)
