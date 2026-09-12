#Requires -Version 5.1

# TestEnvironment PowerShell Module
#
# One module, several identity providers. The shared concerns - SecretStore, password
# generation, certificate handling, progress, base64url - live in Core and have exactly one
# implementation. Everything that genuinely differs between an on-premises directory, Okta and
# Entra lives in its own provider.
#
# The dependency stance is what makes this possible. RequiredModules is empty and a contract
# test enforces it, so importing this module installs and requires nothing. The AD provider
# needs RSAT's ActiveDirectory and GroupPolicy modules, and imports them LAZILY at connect time
# rather than declaring them - otherwise a Windows-only, RSAT-only dependency would be imposed
# on somebody who only wanted to seed an Okta org from a Linux container.

$ModuleRoot = $PSScriptRoot
Write-Verbose "Initializing TestEnvironment module from: $ModuleRoot"

# The naming prefix every provider stamps on everything it creates except human user accounts,
# and the root the seed tag is derived from. Defined once here rather than three times in three
# Connect functions, because a prefix that differs by provider is a prefix that cannot be used
# to find this module's objects across a hybrid estate.
#
# ZZ- leads so that seeded objects sort to the bottom of an alphabetical console listing, out of
# the way in a directory that also holds real work. No asterisks or other wildcard characters:
# they have to be escaped in an LDAP distinguished name and are rejected outright in an Entra
# group's mailNickname.
$script:TestEnvironmentDefaultPrefix = 'ZZ-TEST-'

# --- Core -------------------------------------------------------------------------------
# Loaded first, because providers call into it.
foreach ($function in (Get-ChildItem -Path "$ModuleRoot\Core\*.ps1" -ErrorAction SilentlyContinue)) {
    Write-Verbose "Loading core function: $($function.Name)"
    . $function.FullName
}

# --- Providers --------------------------------------------------------------------------
# Every provider is dot-sourced at import. That costs nothing: a provider's functions only
# reference their platform's cmdlets when actually invoked, so loading the AD provider on a
# host with no RSAT is harmless right up until somebody connects to a domain.
$script:TestEnvironmentProvider = @{}

foreach ($providerFolder in (Get-ChildItem -Path "$ModuleRoot\Providers" -Directory -ErrorAction SilentlyContinue)) {
    $providerName = $providerFolder.Name
    Write-Verbose "Loading provider: $providerName"

    foreach ($subFolder in 'Private', 'Public') {
        foreach ($function in (Get-ChildItem -Path "$($providerFolder.FullName)\$subFolder\*.ps1" -ErrorAction SilentlyContinue)) {
            . $function.FullName
        }
    }

    # A provider may ship module-scope constants its functions read. They are dot-sourced last,
    # and the file is optional. This exists because the Okta provider's seed domain lived in its
    # old root module and was lost in the move - nothing failed at import, and the -replace that
    # used it silently matched an empty pattern instead. A contract test now proves every
    # script-scope variable a provider reads is assigned somewhere.
    $providerInit = Join-Path $providerFolder.FullName 'Initialize.ps1'
    if (Test-Path -LiteralPath $providerInit) {
        Write-Verbose "Loading provider constants: $providerName"
        . $providerInit
    }

    $script:TestEnvironmentProvider[$providerName] = @{
        Name     = $providerName
        Root     = $providerFolder.FullName
        DataPath = Join-Path $providerFolder.FullName 'Data'
    }
}

# --- Shared dispatch --------------------------------------------------------------------
foreach ($function in (Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue)) {
    Write-Verbose "Loading public function: $($function.Name)"
    . $function.FullName
}

# --- Module state -----------------------------------------------------------------------
# Which provider the session is connected through. Set by Connect-TestEnvironment and read by
# every dispatching function, so the provider is named once rather than on every call.
$script:ActiveProvider = $null

Export-ModuleMember -Function @(
    # Shared, provider-agnostic
    'Connect-TestEnvironment',
    'Disconnect-TestEnvironment',
    'Get-TestEnvironmentProvider',
    'New-TestEnvironment',
    'Remove-TestEnvironment',
    'Get-TestEnvironmentReport',
    'Get-TestAccessToken',
    'New-TestServiceApp',
    'Get-TestServiceApp',
    'Update-TestContainment',

    # Entra provider components. Exposed under their own names because the objects they create
    # genuinely have no counterpart in the other providers - an administrative unit is not an
    # OU and a Conditional Access policy is not an Okta sign-on policy. Pretending otherwise
    # behind a shared noun would be a worse abstraction than naming them honestly.
    'New-EntraAdministrativeUnit',
    'New-EntraUser',
    'New-EntraGuestUser',
    'New-EntraGroup',
    'New-EntraDevice',
    'New-EntraApplication',
    'New-EntraNamedLocation',
    'New-EntraConditionalAccessPolicy',
    'New-EntraAuthenticationStrength',
    'New-EntraDirectoryRole',
    'New-EntraRoleEligibility',
    'New-EntraDirectoryExtension',
    'Set-EntraLicense',

    # Active Directory provider components. The Test infix survives here where Entra's did
    # not, because New-ADUser, New-ADGroup and Get-ADDomain are real cmdlets from the RSAT
    # module this provider imports, and shadowing one would be found ahead of the real
    # cmdlet by everything else in the session.
    'New-ADTestOUStructure',
    'New-ADTestUser',
    'New-ADTestDevice',
    'New-ADTestSecurityGroups',
    'New-ADTestServiceAccount',
    'New-ADTestEdgeCase',
    'New-ADTestGroupPolicy',
    'Get-ADTestPasswordFromVault',

    # Okta provider components. These drop the Test infix as the Entra ones did, because Okta
    # ships no PowerShell cmdlets of its own for them to collide with.
    'New-OktaProfileAttribute',
    'New-OktaUser',
    'New-OktaGroup',
    'New-OktaGroupRule',
    'New-OktaApp',
    'New-OktaUserType',
    'New-OktaNetworkZone',
    'New-OktaPolicy',
    'New-OktaLinkedObject',
    'New-OktaTrustedOrigin',
    'New-OktaEventHook',

    # Authentik provider components. No Test infix, for the same reason as Entra and Okta:
    # Authentik ships no PowerShell cmdlets to collide with.
    'New-AuthentikGroup',
    'New-AuthentikUser',
    'New-AuthentikRole',
    'New-AuthentikApplication',
    'New-AuthentikOutpost',
    'New-AuthentikFlow',
    'New-AuthentikScopeMapping',
    'New-AuthentikEntitlement',
    'New-AuthentikPolicy',
    'New-AuthentikNotificationRule',
    'New-AuthentikBinding',
    'New-AuthentikToken',
    'New-AuthentikInvitation',

    # FreeIPA provider components. No Test infix, for the same reason as Entra and Okta: FreeIPA
    # ships no PowerShell cmdlets of its own for them to collide with.
    'New-FreeIPAGroup',
    'New-FreeIPAUser',
    'New-FreeIPAHostgroup',
    'New-FreeIPAHost',
    'New-FreeIPANetgroup',
    'New-FreeIPAHbacRule',
    'New-FreeIPASudoRule',
    'New-FreeIPARole',
    'New-FreeIPAPasswordPolicy',
    'New-FreeIPAService',
    'New-FreeIPAIdView',
    'New-FreeIPAOtpToken',
    'New-FreeIPAAutomemberRule',
    'New-FreeIPAAutomount',
    'New-FreeIPASelinuxUserMap',
    'New-FreeIPACertMapRule',
    'New-FreeIPACaAcl',
    'New-FreeIPACertificate',
    'New-FreeIPADnsZone'
)

$ExecutionContext.SessionState.Module.OnRemove = {
    Write-Verbose "Cleaning up TestEnvironment module"
    Remove-Variable -Name EntraConnection -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name ADConnection -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name OktaConnection -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name AuthentikConnection -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name ActiveProvider -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name TestEnvironmentProvider -Scope Script -ErrorAction SilentlyContinue
}
