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

function Add-DnsServerPrimaryZone {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.String]$DirectoryPartitionName,
        [System.String]$DynamicUpdate,
        [System.Management.Automation.SwitchParameter]$LoadExisting,
        [System.String]$Name,
        [System.String]$NetworkId,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$ReplicationScope,
        [System.String]$ResponsiblePerson,
        [System.Int32]$ThrottleLimit,
        [System.String]$VirtualizationInstance,
        [System.String]$ZoneFile
    )
}

function Add-DnsServerResourceRecord {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$A,
        [System.Management.Automation.SwitchParameter]$AAAA,
        [System.String]$Address,
        [System.String]$AddressType,
        [System.Management.Automation.SwitchParameter]$Afsdb,
        [System.Management.Automation.SwitchParameter]$AgeRecord,
        [System.Management.Automation.SwitchParameter]$AllowUpdateAny,
        [System.Management.Automation.SwitchParameter]$AsJob,
        [System.Management.Automation.SwitchParameter]$Atma,
        [System.TimeSpan]$CacheTimeout,
        [System.String]$CertificateAssociationData,
        [System.String]$CertificateUsage,
        $CimSession,
        [System.Management.Automation.SwitchParameter]$CName,
        [System.String]$ComputerName,
        [System.String]$Cpu,
        [System.Management.Automation.SwitchParameter]$CreatePtr,
        [System.String]$Description,
        [System.String]$DescriptiveText,
        [System.Management.Automation.SwitchParameter]$DhcId,
        [System.String]$DhcpIdentifier,
        [System.Management.Automation.SwitchParameter]$DName,
        [System.String]$DomainName,
        [System.String]$DomainNameAlias,
        [System.Management.Automation.SwitchParameter]$Force,
        [System.Management.Automation.SwitchParameter]$HInfo,
        [System.String]$HostNameAlias,
        $InputObject,
        [System.String]$IntermediateHost,
        $InternetAddress,
        [System.String]$InternetProtocol,
        $IPv4Address,
        $IPv6Address,
        [System.Management.Automation.SwitchParameter]$Isdn,
        [System.String]$IsdnNumber,
        [System.String]$IsdnSubAddress,
        [System.TimeSpan]$LookupTimeout,
        [System.String]$MailExchange,
        [System.String]$MatchingType,
        [System.Management.Automation.SwitchParameter]$MX,
        [System.String]$Name,
        [System.String]$NameServer,
        [System.Management.Automation.SwitchParameter]$NS,
        [System.String]$OperatingSystem,
        [System.Management.Automation.SwitchParameter]$PassThru,
        $Port,
        $Preference,
        $Priority,
        [System.String]$PsdnAddress,
        [System.Management.Automation.SwitchParameter]$Ptr,
        [System.String]$PtrDomainName,
        [System.String]$RecordData,
        [System.Management.Automation.SwitchParameter]$Replicate,
        [System.String]$ResponsiblePerson,
        [System.String]$ResultDomain,
        [System.Management.Automation.SwitchParameter]$RP,
        [System.Management.Automation.SwitchParameter]$RT,
        [System.String]$Selector,
        [System.String]$ServerName,
        [System.String[]]$Service,
        [System.Management.Automation.SwitchParameter]$Srv,
        $SubType,
        [System.Int32]$ThrottleLimit,
        [System.TimeSpan]$TimeToLive,
        [System.Management.Automation.SwitchParameter]$TLSA,
        [System.Management.Automation.SwitchParameter]$Txt,
        $Type,
        [System.String]$VirtualizationInstance,
        $Weight,
        [System.Management.Automation.SwitchParameter]$Wins,
        [System.Management.Automation.SwitchParameter]$WinsR,
        $WinsServers,
        [System.Management.Automation.SwitchParameter]$Wks,
        [System.Management.Automation.SwitchParameter]$X25,
        [System.String]$ZoneName,
        [System.String]$ZoneScope
    )
}

function Add-DnsServerResourceRecordA {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AgeRecord,
        [System.Management.Automation.SwitchParameter]$AllowUpdateAny,
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.Management.Automation.SwitchParameter]$CreatePtr,
        $IPv4Address,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Int32]$ThrottleLimit,
        [System.TimeSpan]$TimeToLive,
        [System.String]$VirtualizationInstance,
        [System.String]$ZoneName,
        [System.String]$ZoneScope
    )
}

function Add-DnsServerResourceRecordCName {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AgeRecord,
        [System.Management.Automation.SwitchParameter]$AllowUpdateAny,
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.String]$HostNameAlias,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Int32]$ThrottleLimit,
        [System.TimeSpan]$TimeToLive,
        [System.String]$VirtualizationInstance,
        [System.String]$ZoneName,
        [System.String]$ZoneScope
    )
}

function Add-DnsServerResourceRecordPtr {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AgeRecord,
        [System.Management.Automation.SwitchParameter]$AllowUpdateAny,
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String]$PtrDomainName,
        [System.Int32]$ThrottleLimit,
        [System.TimeSpan]$TimeToLive,
        [System.String]$VirtualizationInstance,
        [System.String]$ZoneName,
        [System.String]$ZoneScope
    )
}

function Get-DnsServerResourceRecord {
    [CmdletBinding()]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$Node,
        [System.String]$RRType,
        [System.Int32]$ThrottleLimit,
        $Type,
        [System.String]$VirtualizationInstance,
        [System.String]$ZoneName,
        [System.String]$ZoneScope
    )
}

function Get-DnsServerZone {
    [CmdletBinding()]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.String[]]$Name,
        [System.Int32]$ThrottleLimit,
        [System.String]$VirtualizationInstance
    )
}

function Remove-DnsServerResourceRecord {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.Management.Automation.SwitchParameter]$Force,
        $InputObject,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.String[]]$RecordData,
        [System.String]$RRType,
        [System.Int32]$ThrottleLimit,
        $Type,
        [System.String]$VirtualizationInstance,
        [System.String]$ZoneName,
        [System.String]$ZoneScope
    )
}

function Remove-DnsServerZone {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [System.Management.Automation.SwitchParameter]$AsJob,
        $CimSession,
        [System.String]$ComputerName,
        [System.Management.Automation.SwitchParameter]$Force,
        [System.String]$Name,
        [System.Management.Automation.SwitchParameter]$PassThru,
        [System.Int32]$ThrottleLimit,
        [System.String]$VirtualizationInstance
    )
}

Export-ModuleMember -Function @(
    'Add-DnsServerPrimaryZone',
    'Add-DnsServerResourceRecord',
    'Add-DnsServerResourceRecordA',
    'Add-DnsServerResourceRecordCName',
    'Add-DnsServerResourceRecordPtr',
    'Get-DnsServerResourceRecord',
    'Get-DnsServerZone',
    'Remove-DnsServerResourceRecord',
    'Remove-DnsServerZone'
)
