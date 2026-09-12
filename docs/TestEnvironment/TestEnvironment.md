---
document type: module
Help Version: 1.0.0.0
HelpInfoUri: ''
Locale: en-US
Module Guid: c4e91b7d-5a63-4f28-9d10-8b2e6f3a71c5
Module Name: TestEnvironment
ms.date: 09 10 2026
PlatyPS schema version: 2024-05-01
title: TestEnvironment Module
---

# TestEnvironment Module

## Description

Seeds and tears down realistic identity test environments across several providers, sharing one implementation of the concerns they have in common

## TestEnvironment Cmdlets

### [Connect-TestEnvironment](Connect-TestEnvironment.md)

Connects to an identity provider, and fixes which provider the session works against

### [Disconnect-TestEnvironment](Disconnect-TestEnvironment.md)

Clears the stored connection for the active provider

### [Get-ADTestPasswordFromVault](Get-ADTestPasswordFromVault.md)

Retrieves a stored password from the ADTestEnvironment SecretStore vault

### [Get-TestAccessToken](Get-TestAccessToken.md)

Returns the active provider's access token and its expiry

### [Get-TestEnvironmentProvider](Get-TestEnvironmentProvider.md)

Lists the identity providers this module can seed, and which one is active

### [Get-TestEnvironmentReport](Get-TestEnvironmentReport.md)

Reports what is currently seeded through the active provider

### [Get-TestServiceApp](Get-TestServiceApp.md)

Reports the bootstrapped credential and whether it still works

### [New-ADTestDevice](New-ADTestDevice.md)

Creates Active Directory test device objects from CSV data

### [New-ADTestEdgeCase](New-ADTestEdgeCase.md)

Creates the awkward directory states that CSV-driven test data cannot express

### [New-ADTestGroupPolicy](New-ADTestGroupPolicy.md)

Creates the companion Group Policy object that denies logon to the test service accounts.

### [New-ADTestOUStructure](New-ADTestOUStructure.md)

Creates the standardized organizational unit (OU) structure for AD test data.

### [New-ADTestSecurityGroups](New-ADTestSecurityGroups.md)

Creates Active Directory test security groups from CSV data

### [New-ADTestServiceAccount](New-ADTestServiceAccount.md)

Creates Active Directory test service accounts from CSV data

### [New-ADTestUser](New-ADTestUser.md)

Creates Active Directory test user accounts from CSV data

### [New-AuthentikApplication](New-AuthentikApplication.md)

Creates the seeded Authentik applications and the OAuth2, proxy, SAML, LDAP and RADIUS providers behind them

### [New-AuthentikBinding](New-AuthentikBinding.md)

Creates the seeded group, user and policy bindings from Data\AuthentikBindings.csv

### [New-AuthentikEntitlement](New-AuthentikEntitlement.md)

Creates the seeded application entitlements from Data\AuthentikEntitlements.csv

### [New-AuthentikFlow](New-AuthentikFlow.md)

Creates the seeded stages and flows from Data\AuthentikStages.csv and Data\AuthentikFlows.csv, and attaches the flows to seeded providers

### [New-AuthentikGroup](New-AuthentikGroup.md)

Creates the seeded Authentik groups, nested as Data\AuthentikGroups.csv describes

### [New-AuthentikInvitation](New-AuthentikInvitation.md)

Creates the seeded enrolment invitations from Data\AuthentikInvitations.csv

### [New-AuthentikNotificationRule](New-AuthentikNotificationRule.md)

Creates the seeded notification rules and the webhook transports they deliver to

### [New-AuthentikOutpost](New-AuthentikOutpost.md)

Creates the seeded outposts from Data\AuthentikOutposts.csv, carrying the seeded providers

### [New-AuthentikPolicy](New-AuthentikPolicy.md)

Creates the seeded Authentik policies from Data\AuthentikPolicies.csv and binds them to applications

### [New-AuthentikRole](New-AuthentikRole.md)

Creates the seeded Authentik RBAC roles from Data\AuthentikRoles.csv and assigns them to groups

### [New-AuthentikScopeMapping](New-AuthentikScopeMapping.md)

Creates the seeded OAuth2 scope mappings from Data\AuthentikScopeMappings.csv and attaches them to providers

### [New-AuthentikToken](New-AuthentikToken.md)

Creates the seeded user tokens from Data\AuthentikTokens.csv

### [New-AuthentikUser](New-AuthentikUser.md)

Creates the seeded Authentik users from Data\AuthentikUsers.csv, in their groups

### [New-EntraAdministrativeUnit](New-EntraAdministrativeUnit.md)

Creates the administrative units that contain the seeded environment

### [New-EntraApplication](New-EntraApplication.md)

Creates the seeded app registrations, their service principals and their assignments

### [New-EntraAuthenticationStrength](New-EntraAuthenticationStrength.md)

Creates custom authentication strength policies

### [New-EntraConditionalAccessPolicy](New-EntraConditionalAccessPolicy.md)

Creates the seeded Conditional Access policies, always in report-only state

### [New-EntraDevice](New-EntraDevice.md)

Creates the seeded device objects defined in Data\EntraDevices.csv

### [New-EntraDirectoryExtension](New-EntraDirectoryExtension.md)

Creates custom directory extension attributes and populates them

### [New-EntraDirectoryRole](New-EntraDirectoryRole.md)

Creates custom directory role definitions

### [New-EntraGroup](New-EntraGroup.md)

Creates the seeded groups defined in Data\EntraGroups.csv, and their membership

### [New-EntraGuestUser](New-EntraGuestUser.md)

Creates the external identities defined in Data\EntraGuestUsers.csv

### [New-EntraNamedLocation](New-EntraNamedLocation.md)

Creates the named locations Conditional Access policies condition on

### [New-EntraRoleEligibility](New-EntraRoleEligibility.md)

Makes seeded principals *eligible* for the seeded custom roles, and never active in them

### [New-EntraUser](New-EntraUser.md)

Creates the seeded users defined in Data\EntraUsers.csv

### [New-FreeIPAAutomemberRule](New-FreeIPAAutomemberRule.md)

Creates the seeded automember rules from Data\FreeIPAAutomemberRules.csv and rebuilds the seeded entries against them

### [New-FreeIPAAutomount](New-FreeIPAAutomount.md)

Creates the seeded automount location, maps and keys from Data\FreeIPAAutomount.csv

### [New-FreeIPACaAcl](New-FreeIPACaAcl.md)

Creates the seeded certificate authority access control rules from Data\FreeIPACaAcls.csv

### [New-FreeIPACertificate](New-FreeIPACertificate.md)

Has the realm's CA issue the seeded certificates from Data\FreeIPACertificates.csv, and revokes the ones the data says are revoked

### [New-FreeIPACertMapRule](New-FreeIPACertMapRule.md)

Creates the seeded certificate identity mapping rules from Data\FreeIPACertMapRules.csv

### [New-FreeIPADnsZone](New-FreeIPADnsZone.md)

Creates the seed's own DNS zones and the records in them from Data\FreeIPADnsRecords.csv

### [New-FreeIPAGroup](New-FreeIPAGroup.md)

Creates the seeded FreeIPA groups, nested as Data\FreeIPAGroups.csv describes

### [New-FreeIPAHbacRule](New-FreeIPAHbacRule.md)

Creates the seeded HBAC services, service groups and rules from Data\FreeIPAHbacServices.csv and Data\FreeIPAHbacRules.csv

### [New-FreeIPAHost](New-FreeIPAHost.md)

Creates the seeded FreeIPA hosts from Data\FreeIPAHosts.csv, in their host groups

### [New-FreeIPAHostgroup](New-FreeIPAHostgroup.md)

Creates the seeded FreeIPA host groups, nested as Data\FreeIPAHostgroups.csv describes

### [New-FreeIPAIdentityProvider](New-FreeIPAIdentityProvider.md)

Creates the seeded RADIUS proxies and external identity providers from Data\FreeIPAIdentityProviders.csv

### [New-FreeIPAIdView](New-FreeIPAIdView.md)

Creates the seeded ID views and overrides from Data\FreeIPAIdViews.csv and Data\FreeIPAIdOverrides.csv, and applies them to hosts

### [New-FreeIPANetgroup](New-FreeIPANetgroup.md)

Creates the seeded FreeIPA netgroups from Data\FreeIPANetgroups.csv, with their members

### [New-FreeIPAOtpToken](New-FreeIPAOtpToken.md)

Creates the seeded OTP tokens from Data\FreeIPAOtpTokens.csv on their users

### [New-FreeIPAPasswordPolicy](New-FreeIPAPasswordPolicy.md)

Creates the seeded password policies from Data\FreeIPAPasswordPolicies.csv, one per seeded group

### [New-FreeIPARole](New-FreeIPARole.md)

Creates the seeded permissions, privileges and roles from Data\FreeIPAPermissions.csv, Data\FreeIPAPrivileges.csv and Data\FreeIPARoles.csv

### [New-FreeIPASelinuxUserMap](New-FreeIPASelinuxUserMap.md)

Creates the seeded SELinux user maps from Data\FreeIPASelinuxUserMaps.csv

### [New-FreeIPAService](New-FreeIPAService.md)

Creates the seeded Kerberos services and delegation rules from Data\FreeIPAServices.csv and Data\FreeIPAServiceDelegation.csv

### [New-FreeIPASudoRule](New-FreeIPASudoRule.md)

Creates the seeded sudo commands, command groups and rules from Data\FreeIPASudoCommands.csv and Data\FreeIPASudoRules.csv

### [New-FreeIPAUser](New-FreeIPAUser.md)

Creates the seeded FreeIPA users from Data\FreeIPAUsers.csv, in their groups and lifecycle states

### [New-OktaApp](New-OktaApp.md)

Creates the seeded app integrations and assigns groups and users to them

### [New-OktaEventHook](New-OktaEventHook.md)

Creates the seeded event hooks

### [New-OktaGroup](New-OktaGroup.md)

Creates the seeded Okta groups and assigns their members

### [New-OktaGroupRule](New-OktaGroupRule.md)

Creates the group rules that populate the automatic groups

### [New-OktaLinkedObject](New-OktaLinkedObject.md)

Creates the linked object definition and links seeded users with it

### [New-OktaNetworkZone](New-OktaNetworkZone.md)

Creates the seeded network zones that policies condition on

### [New-OktaPolicy](New-OktaPolicy.md)

Creates the seeded sign-on and password policies, with their rules

### [New-OktaProfileAttribute](New-OktaProfileAttribute.md)

Adds the module's custom attributes to the Okta user schemas

### [New-OktaTrustedOrigin](New-OktaTrustedOrigin.md)

Creates the seeded trusted origins

### [New-OktaUser](New-OktaUser.md)

Creates the seeded Okta users from Data\OktaUsers.csv

### [New-OktaUserType](New-OktaUserType.md)

Creates the second Okta user type and extends its schema

### [New-TestEnvironment](New-TestEnvironment.md)

Seeds the complete test environment through the active provider

### [New-TestServiceApp](New-TestServiceApp.md)

Bootstraps the application the module authenticates as

### [Remove-TestEnvironment](Remove-TestEnvironment.md)

Removes everything the active provider created, and nothing else

### [Set-EntraLicense](Set-EntraLicense.md)

Assigns licences by group and directly, so the assignment path is ambiguous on purpose

### [Update-TestContainment](Update-TestContainment.md)

Places any seeded object that is not in its container

