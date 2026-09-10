# TestEnvironment

[![PowerShell Gallery](https://img.shields.io/badge/PowerShell%20Gallery-v1.0.0-blue)](https://www.powershellgallery.com/packages/TestEnvironment)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Quality Gates](https://github.com/fadwen/TestEnvironment/actions/workflows/quality-gates.yml/badge.svg)](https://github.com/fadwen/TestEnvironment/actions/workflows/quality-gates.yml)
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)

## 📖 Purpose

**TestEnvironment** seeds a realistic identity environment you can point scripts at, and tears
it down again cleanly. One module, several directories: you name the provider once, at connect
time, and everything afterwards reads the connection rather than being told again.

```powershell
Connect-TestEnvironment -Provider Entra -TenantId <tenant-guid> -CertificateThumbprint <thumb>
New-TestEnvironment
Get-TestEnvironmentReport
Remove-TestEnvironment -Force
```

**Three providers.**

| Provider | Connecting needs | Seeds |
|---|---|---|
| `Entra` | a certificate, or a one-off device-code bootstrap | ~1,150 objects held in administrative units |
| `AD` | nothing — the caller's own Windows identity | ~1,100 objects held in `OU=TestData` |
| `Okta` | an OAuth service app, bootstrapped once from an API token | ~60 objects across ten types, seed-tagged |

Most of what follows describes the **Entra** provider; the other two have their own sections under
[The Active Directory provider](#-the-active-directory-provider) and
[The Okta provider](#-the-okta-provider), and [Architecture](#-architecture) covers what all three
share.

The Entra provider follows the AD module's shape rather than the licence-starved Okta one:
**volume, contained in a container.** AD puts roughly eleven hundred objects under `OU=TestData`
and can therefore say exactly what it created by asking the directory. This does the same thing
with the nearest equivalent Entra has.

| | Count | Why it is there |
|---|---|---|
| Administrative units | 4 | The containers. Entra's nearest equivalent to an OU |
| Users | 305 | 9 designed edge cases, 296 mapped from AD for volume |
| External identities | 4 | B2B guests and a local one, arranged so no single property separates insiders from outsiders |
| Groups | 104 | 14 designed shapes, 90 from AD including its real nesting |
| Devices | 694 | 6 designed states, 688 from AD |
| Applications | 8 | The direct-vs-group assignment split access reviews miss, plus reply URLs |
| Service principals | 7 | Distinct from their applications, because people conflate them |
| Named locations | 6 | The network-zone equivalent: IPv4, IPv6, trusted, single-host, country |
| Directory extensions | 10 | Custom schema attributes across six data types and three object classes |
| Auth strengths | 3 | Named credential-combination bars, which Okta has no equivalent of |
| Custom roles | 3 | Least-privilege role definitions, created but never assigned |
| Role eligibilities | 3 | PIM schedules over those roles — **eligible, never active**, so `roleAssignments` returns nothing for any of them |
| CA policies | 11 | Ten control shapes report-only plus one deliberately **disabled**; this module can never create an enforcing policy |

**Key differentiators:**

- ✅ **Contained, not just named** — every object lives in an administrative unit, so teardown asks the container rather than guessing from names
- ✅ **Ownership is proven** — nothing is deleted for merely looking like test data
- ✅ **Safe in a tenant you care about** — a seeded CA policy is report-only or disabled, never enforcing; a seeded role eligibility is eligible, never active; neither state is a parameter
- ✅ **Nothing leaves the tenant** — the four guests are invited with `sendInvitationMessage` false on RFC 2606 reserved domains, and there is no parameter that makes the module send mail
- ✅ **Batched** — ~1,150 objects in about five minutes, not an hour
- ✅ **Idempotent** — a re-run reuses what exists rather than duplicating it
- ✅ **Shares AD's directory** — the same people exist in both labs, so hybrid identity matching is testable
- ✅ **No dependencies** — no Graph SDK, no gallery installs, works on a stock 5.1 host

## 📦 Installation

From the [PowerShell Gallery](https://www.powershellgallery.com/packages/TestEnvironment):

```powershell
Install-PSResource -Name TestEnvironment

# Or, on a host that still only has PowerShellGet v2:
Install-Module -Name TestEnvironment -Scope CurrentUser
```

Requires Windows PowerShell 5.1 or PowerShell 7, and nothing else: `RequiredModules` is empty
and a contract test keeps it that way. The AD provider needs RSAT's `ActiveDirectory` and
`GroupPolicy` modules, which it imports at connect time and names clearly when they are absent.
The Entra and Okta providers need nothing beyond a stock host, on any platform.

From a clone:

```powershell
git clone https://github.com/fadwen/TestEnvironment.git
Import-Module .\TestEnvironment\TestEnvironment.psd1
```

## 🚀 Quick Start

```powershell
Import-Module TestEnvironment

# First run against a tenant: sign in once, and the module creates the app it uses from then on
Connect-TestEnvironment -Provider Entra -TenantId <tenant-guid> -Interactive
New-TestServiceApp

# Every run afterwards is app-only, with no human involved
Connect-TestEnvironment -Provider Entra -TenantId <tenant-guid> -ClientId <app-guid> `
    -CertificateThumbprint <thumbprint>

New-TestEnvironment -WhatIf          # see what it would do
New-TestEnvironment -ShowProgress    # do it
Get-TestEnvironmentReport            # see what you got
```

```
Entra test environment in Contoso Ltd (b818de68-...)
Prefix ENTRALAB- on contoso.onmicrosoft.com

  Users                      309
  GuestsByUserType             3
  GuestsByExternalUpn          3
  GuestsPendingAcceptance      3
  Groups                     104
  Devices                    694
  Applications               8
  ServicePrincipals          7
  NamedLocations             6
  ConditionalAccessPolicies 11
  AuthenticationStrengths    3
  DirectoryRoles             3
  RoleEligibilities            3
  RoleAssignments              0
  DirectoryExtensions       10

⏱️  Seed: ~5 minutes.  Teardown: ~8 minutes.  Report: ~30 seconds.
```

## 🔑 Bootstrapping, and why there is nothing to paste

Okta's module trades a pasted SSWS token for an OAuth service app, then tells you to revoke the
token. Entra has no equivalent to trade: there is **no long-lived personal API key** a human can
generate and hand to a script. So the bootstrap credential is the human, signed in for exactly as
long as it takes to create an application that can act on its own.

```powershell
# Once, as a Global Administrator
Connect-TestEnvironment -Provider Entra -TenantId <tenant> -Interactive
New-TestServiceApp

#   Sign in to authorise the bootstrap:
#     1. Open https://microsoft.com/devicelogin
#     2. Enter the code: F7Q2KXPNL
#     3. Sign in as a Global Administrator of this tenant
#
#   Bootstrap complete. From now on, connect app-only:
#     Connect-TestEnvironment -Provider Entra -TenantId <tenant> `
#         -ClientId 0efd9e3e-... `
#         -CertificateThumbprint E64EBA34...
```

Every run after that is app-only, and the human is never needed again.

**Device code flow** is used rather than a browser redirect because it needs no listener, no
reply URL, and no application of its own — it works over SSH, in a container, and on a machine
with no browser. The bootstrap client is Microsoft Graph PowerShell's first-party application,
which is pre-consented in every tenant, so there is no chicken-and-egg problem of registering an
application in order to register an application.

### What actually happens

1. An RSA key pair is generated locally. **Only the public half is ever sent** — the private key
   stays on this machine and Entra never sees it. A unit test decodes the uploaded blob and
   asserts `HasPrivateKey` is false on it.
2. The application is created and the public key attached as a credential.
3. Its service principal is created.
4. **Admin consent is granted.** Consent for an application permission *is* an
   `appRoleAssignment` on the Microsoft Graph service principal — which is why this needs a
   Global Administrator and is the one step the application cannot do for itself.
5. **The handover is proved before success is reported.** The new application must acquire a
   token with its own certificate first; an application that exists, is consented, and cannot
   authenticate is the worst of the three outcomes because it fails later and elsewhere.

The certificate goes into `Cert:\CurrentUser\My` and a record of what to connect with goes to
`~/.entratestenvironment/<tenant>.serviceapp.json`, outside the repository — a path inside the
module folder would sit in a working tree, one `.gitignore` mistake away from being pushed. The
private key is not in that file; it is in the certificate store.

```powershell
Get-TestServiceApp -TestCredential   # what am I meant to connect as, and does it still work
```

### Where the private key lives

Two options, and the record on disk is the authority on which is in use — so
`Connect-TestEnvironment` looks in the right place rather than guessing.

| `-UseSecretStore` | Key lives in | Encrypted at rest | Dependencies |
|---|---|---|---|
| **not passed** (default) | `Cert:\CurrentUser\My` | ✅ by the platform key store | none |
| **passed** | A SecretStore vault | ✅ AES, password-protected | 2 gallery modules, installed on demand |

The certificate store is the right default on Windows. Off it, `X509Store` is a file-backed shim
whose behaviour varies by distribution, so **`-UseSecretStore` is the portable path** — the same
reasoning that made it the cross-platform option in `OktaTestEnvironment`.

```powershell
Connect-TestEnvironment -Provider Entra -TenantId <tenant> -Interactive
New-TestServiceApp -UseSecretStore

# Afterwards, the tenant id is the only thing you type
Connect-TestEnvironment -Provider Entra -TenantId <tenant> -UseSecretStore
```

The client id and thumbprint come from the record; the key comes from the vault. The PFX is
reconstituted in memory and loaded with `EphemeralKeySet`, so reading the credential does not
quietly install it into the certificate store as a side effect.

`SecretManagement` and `SecretStore` stay out of `RequiredModules` — a contract test enforces it —
and are installed on demand only under this explicit opt-in, to `CurrentUser` scope, so nobody
pays for a vault they never asked for.

> **SecretStore is shared, in two ways that are not obvious.**
>
> **The configuration is per user, not per vault.** `ADTestEnvironment`, `OktaTestEnvironment`
> and `TestEnvironment` all register vaults against the same physical store, so whatever
> one of them configures, the others inherit. None of the three reconfigures a store it did not
> configure — each adapts to what it finds, and asks for `-VaultPassword` when the store wants
> one it does not know. If a run fails to unlock, the likeliest cause is that one of the other
> two set the password first.
>
> **The vaults are not isolated from each other.** Registering two vaults against
> `Microsoft.PowerShell.SecretStore` produces two *names* for one store, not two containers —
> verified by writing a secret to one and reading it back unchanged from the other. Secret names
> are therefore globally unique per user, which is why every module namespaces its own, and a
> vault name is a label rather than a boundary.

> **SecretStore configuration is per user, and shared with anything else using it.** If
> `ADTestEnvironment` or `OktaTestEnvironment` configured it first, the store already has a
> password and this module's default will not open it — pass `-VaultPassword` with the existing
> one. The module detects that case and says so, rather than failing with SecretStore's own
> message about not being able to add a new password, which describes a different problem
> entirely. The vault is checked *before* anything is created, so a store it cannot open never
> leaves an orphaned application behind.

That checks the three things independently, because they fail apart: the record on disk, the
application in the tenant, and the private key in the store. Any one can be missing while the
others look fine.

### Two things worth knowing

> **The bootstrapped app is excluded from teardown, always.** It carries the seed prefix and the
> seed tag like everything else, so without an explicit exclusion `Remove-TestEnvironment`
> would delete the credential it is authenticating with, halfway through, stranding whatever had
> not been deleted yet. Removing it is opt-in via `-RemoveServiceApp` and nothing else.

> **`RoleManagement.ReadWrite.Directory` is privileged.** It is granted by default because the
> module seeds custom directory roles, and it also permits *assigning* directory roles — an
> escalation path. Pass `-Scope` without it, and skip the `DirectoryRoles` seeding step, if that
> is not a trade you want. Everything else the app is granted is scoped to what it creates:
> note `Application.ReadWrite.OwnedBy` rather than the tenant-wide `.All`, which a contract test
> enforces.

## 📋 Prerequisites

| Requirement | Minimum | Notes |
|---|---|---|
| **PowerShell** | 5.1 | Desktop and Core; developed on pwsh 7.6 |
| **Entra tenant** | Any | Dynamic groups need Entra ID P1; everything else works without |
| **App registration** | Certificate credential | Created for you by `New-TestServiceApp`, or supply your own |
| **Permissions** | Directory writes | See below — the token does not tell you the whole story |
| **Modules** | none | Deliberately zero dependencies |

The client assertion is signed with the in-box .NET crypto types and every call goes through
`Invoke-WebRequest`. That is a deliberate constraint: a lab module that first requires you to
install 46 SDK sub-modules is one more thing to get working before you can start.
`RequiredModules` is empty and a contract test enforces it.

### Permissions, and why the token understates them

The app needs `User.ReadWrite.All`, `Group.ReadWrite.All`, `Device.ReadWrite.All`,
`Application.ReadWrite.OwnedBy`, `AdministrativeUnit.ReadWrite.All`,
`Policy.ReadWrite.ConditionalAccess`, `Policy.Read.All`, `Directory.Read.All` and
`Organization.Read.All`; `Providers\Entra\Data\EntraServiceAppPermissions.csv` is the
authority and says why each is there.

`OwnedBy` has a consequence for teardown worth knowing in advance. The service app can delete
only applications it owns, which is every application it created itself. Seeded applications
created by another identity - a human signed in with `-Interactive`, or a service app that has
since been replaced - have no owner it can claim, and `Remove-TestEnvironment` reports them as
skipped with an insufficient-privileges error rather than deleting them. Remove those with the
identity that created them, or from the portal.

But **the token's `roles` claim is not the whole story, and reading it as a safety limit is a
mistake.** A service principal also inherits whatever *directory roles* it has been assigned, and
those do not appear in the token at all. The tenant this was developed against holds an app whose
Graph permissions are almost entirely `*.Read.All` — and which creates and deletes users, groups,
devices and applications perfectly happily, because the service principal is a Global
Administrator.

Scopes say which APIs may be called; directory roles say which objects may be touched. An app can
be over-privileged through the second while looking read-only through the first.

## 🗂️ Containment

This is the part worth understanding, because everything else follows from it.

ADTestEnvironment puts everything under `OU=TestData`. Entra has no OUs, but it has
**administrative units**, and they are close enough to be the primary containment mechanism here.
Four are created, one per object class:

```
ENTRALAB-Users          305 members
ENTRALAB-Groups         104 members
ENTRALAB-Devices        694 members
ENTRALAB-Applications     8 members
```

Teardown asks each container what it holds. That is authoritative in a way a name match never
is: an object is in the unit because this module put it there.

Three properties of an AU differ from an OU and all three shape the design:

- **They do not nest.** Verified against a live tenant: adding one AU to another is refused with
  *"The reference target ... of type 'AdministrativeUnit' is invalid for the 'members'
  reference"*. So AD's sub-OU tree flattens into four siblings.
- **They are containers, not parents.** Deleting a unit does not delete its members — verified
  live, all members survived. So the units are removed *last*, after their contents, and they
  exist to identify what to delete rather than to do it.
- **Membership is not exclusive.** An object can be in several units or none, and it lives in the
  tenant root regardless. Membership proves this module created something; it is not a location.

### The fallback, and why it still exists

A name prefix and a second marker are still checked, as a fallback, for two reasons: some objects
**cannot** belong to an administrative unit at all, and deleting the container would otherwise
strand everything it held.

| Object | In a unit? | Fallback marker | Fallback proof required |
|---|---|---|---|
| **Users** | ✅ | Prefixed UPN on the seed domain, `extensionAttribute15` | **Either** |
| **Groups** | ✅ | `displayName` prefix + seed tag in `description` | **Both** |
| **Applications** | ✅ | `displayName` prefix + seed tag in `tags` | **Both** |
| **Devices** | ✅ | `displayName` prefix | Name alone |
| **Service principals** | ❌ | `displayName` prefix + seed tag in `tags` | **Both** |
| **Named locations** | ❌ | `displayName` prefix | Name alone |
| **CA policies** | ❌ | `displayName` prefix | Name alone |

Every claimed object carries a `SeedProof` property recording which routes found it — `unit`,
`unit+upn+tag`, `name+description` — so a report can show whether the container or the name did
the work.

> **The marker cannot simply be queried.** Verified live: `employeeType`, `companyName` and every
> `extensionAttribute` are **writable but not filterable**. Graph rejects all of them in `$filter`
> with `Request_UnsupportedQuery`, even with `ConsistencyLevel: eventual`. Only
> `startswith(userPrincipalName, ...)` works server-side for users, and
> `startswith(displayName, ...)` for everything else.

The prefix is validated to end in a separator (`-` or `_`), which is what stops `ENTRALAB-` from
matching a genuine object called `ENTRALABORATORY`.

Seeded users are created on the tenant's **initial `onmicrosoft.com` routing domain**, identified
by `isInitial` rather than by suffix match — a tenant can hold several `onmicrosoft.com` domains
and only one is the routing domain. That domain accepts no external mail, so a seeded account
cannot reach a real recipient.

### `Update-TestContainment`

Placement is the one part of seeding that fails without anything else being wrong. The references
are added seconds after the objects are created, so they lose races with replication, and a batch
that exhausts its retries leaves objects that exist, work, and are simply not in their container.
Nothing looks broken until teardown falls back to names.

`Update-TestContainment` reconciles the difference. It runs as the last step of
`New-TestEnvironment`, and it is idempotent, so it is safe to run again whenever you want:

```powershell
Update-TestContainment -PassThru

ObjectType   AdministrativeUnit    Seeded AlreadyContained Missing Placed
----------   ------------------    ------ ---------------- ------- ------
Users        ENTRALAB-Users           305              305       0      0
Groups       ENTRALAB-Groups          104              104       0      0
Devices      ENTRALAB-Devices         694              694       0      0
Applications ENTRALAB-Applications      6                6       0      0
```

It reconciles in one direction only. An object in a unit that this module cannot otherwise
account for is reported and left alone, never removed.

## ⚡ Batching

Everything that can go through Graph's `$batch` endpoint does, in chunks of twenty — verified
live, a twenty-first is refused with *"Number of requests inside batch exceed the limit"*.

At AD parity that is the difference between a four-minute run and an hour-long one. Three
properties of `$batch` are worth knowing, because none behaves like a normal call:

- **The outer call returns 200 even when every request inside it failed.** The real status is per
  response, so a caller checking only the outer result sees success while nothing was created.
- **Responses come back in arbitrary order.** They are correlated by the id sent with each
  request, never by position.
- **Throttling appears per response as a 429.** Those individual requests are retried in a fresh
  batch rather than the whole chunk being resent, so one throttled request does not duplicate the
  nineteen that succeeded.

### Two Graph rules the seed data records

Both cost a live 400 to discover, and both are recorded in the `ca-user-risk` row's `Purpose`
so the next person changing that data does not rediscover them:

- **1066** — `passwordChange` is refused unless combined with a strong-auth control using the
  `AND` operator, e.g. `mfa;passwordChange`.
- **1092** — a policy carrying `passwordChange` must apply to **all** client app types, not a
  named subset.

## 🛡️ Conditional Access policies never enforce

Ten of the eleven are report-only and one is deliberately `disabled`, because real tenants
keep retired policies and an inventory script must not count one as active. Disabled is quieter
than report-only, which still logs. What can never appear is `enabled`: the state is not a
parameter, a row asking for anything but those two values is refused rather than trusted, and a
contract test asserts both halves.

Every seeded policy is created in `enabledForReportingButNotEnforced`, and **there is no parameter
to change that.** A contract test asserts the function exposes no `-State`, `-Enabled` or
`-Enforce` parameter.

This is the single most consequential decision in the module and it is deliberately not
configurable. A report-only policy is fully evaluated and fully logged — it appears in sign-in
logs, What If returns it, `CaOutcome` can fold it — but it never denies anything. That is the
whole value for none of the risk.

Policies are scoped to seeded groups only, never to all users. A policy that resolves no groups is
**refused rather than created**, because an unscoped Conditional Access policy applies
tenant-wide.

## 💡 Core functions

### Connection
- **`Connect-TestEnvironment`** — `TenantId`, `ClientId`, `CertificateThumbprint` / `CertificatePath` / `Certificate`, `Prefix`, `UpnSuffix`, `GraphBaseUri`, `PassThru`
  - Reads the organisation back from Graph rather than trusting the parameter, so a connection to the wrong directory is visible immediately
- **`Disconnect-TestEnvironment`** — clears the credential without unloading the module
- **`Get-TestAccessToken`** — the token, its expiry, and the roles it carries
- **`New-TestServiceApp`** — bootstraps the application the module authenticates as, and hands over to it
  - `Scope[]`, `UseSecretStore`, `VaultName`, `VaultPassword`, `CertificateValidityDays`, `Force`, `PassThru`
- **`Get-TestServiceApp`** — what is stored, and whether the credential still works

### Environment
- **`New-TestEnvironment`** — the orchestrator, twelve steps in dependency order
  - `Skip[]`, `SkuPartNumber`, `ShowProgress`, `PassThru`
- **`Remove-TestEnvironment`** — teardown
  - `Keep[]`, `PurgeRecycleBin`, `Force`, `ShowProgress`, `PassThru`
- **`Update-TestContainment`** — reconciles unit membership
- **`Get-TestEnvironmentReport`** — Console, Object, JSON, CSV or HTML

`-Skip` and `-Keep` take the same names: `AdministrativeUnits`, `Users`, `Groups`, `Licenses`,
`Devices`, `Applications`, `NamedLocations`, `ConditionalAccessPolicies`, `Containment`.

```powershell
# Directory only - no policy objects at all
New-TestEnvironment -Skip NamedLocations, ConditionalAccessPolicies

# Rebuild just the access layer over an existing directory
New-TestEnvironment -Skip Users, Groups, Licenses
```

### Components

Each runs standalone, and the orchestrator runs them in the order listed — the only order that
works, because each depends on the last.

- **`New-EntraAdministrativeUnit`** — the four containers. First, because nothing can be placed in a container that does not exist
- **`New-EntraUser`** — the users, their manager chain and their containment
  - `UserKey[]`, `Tier`, `SkipManagers`, `ShowProgress`, `PassThru`
- **`New-EntraGroup`** — the groups, their membership and the nesting
  - `GroupKey[]`, `Tier`, `SkipMembership`, `ShowProgress`, `PassThru`
- **`Set-EntraLicense`** — group-based and direct licence assignment
- **`New-EntraDevice`** — the device objects and their registered owners
  - `DeviceKey[]`, `Tier`, `SkipOwners`, `ShowProgress`, `PassThru`
- **`New-EntraApplication`** — applications, service principals and app role assignments
- **`New-EntraNamedLocation`** — the IP and country locations policies condition on
- **`New-EntraConditionalAccessPolicy`** — the report-only policies

### `-Tier`, for a fast rebuild

The seed data has two halves, and `-Tier` selects between them. `Core` is the hand-designed rows —
nine users, fourteen groups, six devices — chosen to be awkward in ways that break scripts. `Bulk`
is the volume mapped from AD.

```powershell
# The designed edge cases only. Seconds rather than minutes.
New-EntraUser -Tier Core
New-EntraGroup -Tier Core
New-EntraDevice -Tier Core
```

Volume does not make any of the designed cases more likely to be found, so when the thing under
test is behaviour rather than scale, `-Tier Core` is the faster loop.

## 📊 Test data inventory

### Users (305 = 9 core + 296 bulk)

Source: `Data\EntraUsers.csv`. The nine core rows each differ along an axis that breaks scripts.

| Key | Name | Department | State | Why this one |
|---|---|---|---|---|
| `awhitfield` | Ada Whitfield | Executive | Active | Top of the chain, **no manager** — the null that breaks recursive walks |
| `jnino` | José Niño | Engineering | Active | **Non-ASCII** display name with an ASCII UPN |
| `zmueller` | Zoë Müller | Engineering | Active | Non-ASCII, and an employeeId of **`0007`** |
| `mbell` | Marcus Bell | Sales | **Disabled** | Still licensed and still in groups — the half-finished offboarding |
| `praghunathan` | Priya Raghunathan | Finance | Active | Holds the same licence **directly and by group** |
| `talvarez` | Tomás Álvarez | IT | Active | In **two** departments' groups at once |
| `hkobayashi` | Hana Kobayashi | HR | Active | No manager, no groups, no licence — every empty case at once |
| `ofitzgerald` | Owen Fitzgerald | Sales | Active | **No usageLocation**, so licence assignment fails on purpose |
| `svcreporting` | Reporting Service | IT | Active | **No given or surname**, which name-splitting assumes exists |

The other 296 are AD's people, with their departments, titles and manager chains preserved. That
reuse is deliberate: the same person exists in both labs, so anything matching identities across a
hybrid boundary — by UPN, by employeeId, by display name — has two directories that genuinely
correspond.

- **Non-ASCII names, ASCII logins.** Windows PowerShell writes CSV as ASCII unless told otherwise
  and silently replaces those characters with `?`, so without them that data loss is invisible.
- **An employeeId of `0007`.** Any numeric cast turns it into `7`, and nothing says so.
- **A disabled user who still holds a licence.** Disabling an account does not release its licence.
- **A user with no usageLocation.** Entra accepts the user and then refuses every licence
  assignment for it. The seeding step reports it and continues rather than treating it as fatal.

### Groups (104 = 14 core + 90 bulk)

Source: `Data\EntraGroups.csv`.

| Category | Groups |
|---|---|
| Organisational | **All Staff** — contains only other groups |
| Department | Engineering, Sales, Finance, IT |
| Nesting | **Nested Tier 1 → Tier 2 → Tier 3**, three deep |
| Dynamic | Dynamic Engineering, Dynamic Disabled Accounts |
| Microsoft 365 | Collaboration Workspace |
| Licensing | Licence Power BI — carries the group-based licence |
| Privileged | Role Assignable Support — `isAssignableToRole` |
| Lifecycle | Offboarding Hold — **deliberately empty** |

The 90 bulk groups bring AD's own `MemberOfGroup` nesting with them, which is what makes
transitive expansion genuinely expensive rather than a two-element chain:

```
ENTRALAB-All Employees          direct=17   transitive=87
ENTRALAB-File Share Users       direct=11   transitive=54
ENTRALAB-Test Domain Admins     direct=6    transitive=42
```

- **All Staff contains no users at all.** If direct and transitive ever match, either the nesting
  failed or whatever produced the report only expanded one level.
- **The nesting is three deep in the core.** One level is satisfied by any implementation that
  expands members once; three is what separates transitive from recursive.
- **The empty group is the point.** An empty group and a failed query look identical in most
  reports.

> **Only two of Entra's four group flavours can be created here.** Verified live: Graph refuses
> **distribution lists and mail-enabled security groups** outright — *"Cannot Create a mail-enabled
> security groups and or distribution list"* — whatever combination of `mailEnabled`,
> `securityEnabled` and `groupTypes` is sent. Exchange Online PowerShell is the only route.

> **Every dynamic rule is scoped to the seed prefix, and the module refuses one that is not.** The
> first live run used `(user.userType -eq "Guest")`, and Entra immediately put **two real external
> accounts** into a seeded group. A seeded group silently containing real people is precisely the
> blast radius this module exists to avoid.

### External identities (4)

Source: `Data\EntraGuestUsers.csv`. Four rows arranged so that **no single property separates the
insiders from the outsiders** — which is exactly what most access-review scripts assume there is.

| Key | Name | How it is made | `userType` | UPN carries `#EXT#` | `externalUserState` |
|---|---|---|---|---|---|
| `gpending` | Nadia Sorensen | Invitation | Guest | ✅ | **PendingAcceptance** |
| `gmember` | Rafael Ortiz | Invitation | Guest | ✅ | PendingAcceptance |
| `gconverted` | Ingrid Halvorsen | Invitation | **Member** | ✅ | PendingAcceptance |
| `glocal` | Bartek Nowak | Direct `POST /users` | Guest | ❌ | *(none)* |

Read the last two rows together, because they are the point:

- Filter on `userType eq 'Guest'` and you miss **`gconverted`** — a genuine external identity that
  was converted to a member, which is what happens to every long-running contractor. A headcount
  built that way counts an outsider as staff.
- Filter on `#EXT#` in the UPN and you miss **`glocal`** — `userType` is Guest on an otherwise
  ordinary cloud account with an in-tenant UPN and no external mail at all.
- Filter on `externalUserState` and you see only the invitations nobody has redeemed.

`gpending` carries the case that catches the most reports: it is **enabled and cannot sign in**.
The invitation was never redeemed, so anything counting active accounts by `accountEnabled`
counts it, and anything looking for disabled accounts to clean up never finds it.

`gmember` sits in `dept-engineering`, one level down the nesting chain, so `all-staff` reaches an
external identity **transitively** without holding one directly. Its department also satisfies the
`dyn-engineering` rule, so Entra adds it to a dynamic group whose author never considered guests.

Two of the four are left with **no `usageLocation`**, which is the default state of every
invitation and the state in which licence assignment fails.

#### The guest step needs the tenant's permission as well as Graph's

Verified live, and it is the one prerequisite that is not a Graph permission. `POST /invitations`
is refused with **403 "Guest invitations not allowed for your company"** whenever the tenant's
`allowInvitesFrom` restricts who may invite — `adminsAndGuestInviters` is enough to block it — and
that happens even though `User.ReadWrite.All` is granted and consented, because the setting
governs *who invites* rather than *what the app may call*. An app-only principal does not count as
an admin for this unless it holds a directory role that says so.

Two plausible readings of that message are both wrong, and both were tested live rather than
reasoned about:

- **It is not `User.ReadWrite.All` missing.** That was granted, consented, and present in the
  token's `roles` claim. Microsoft documents it as sufficient for the endpoint, and it is — for the
  *permission* check. `allowInvitesFrom` is a separate gate that it does not open.
- **It is not the Guest Inviter directory role either.** Assigning it to the service principal and
  re-acquiring the token so that `95e79109-…` appeared in the token's `wids` changed nothing: the
  same 403 came back. Worth knowing while testing this, because an app-only token carries its
  directory roles *in* the token — retrying with the token already in hand can never pick up a new
  role, however long you wait.

What is left is **`User.Invite.All`**, the permission built for this, which the module now requests
as an optional permission. Drop it and skip the `GuestUsers` step; keep it and the invitations
work. The seed app asks for it separately rather than relying on `User.ReadWrite.All` precisely
because the documented coverage turned out not to survive a tenant that restricts invitations.

Without it the step warns, names the setting, and continues, so `glocal` and the rest of the
environment are still seeded. `-Skip GuestUsers` opts out entirely.

> A Global Administrator role is **not** a substitute for the Graph permission on the endpoints
> that check scopes explicitly. Verified against an app-only token whose service principal was a
> Global Administrator but held neither permission: `POST /invitations` answered 401, and
> `POST /roleEligibilityScheduleRequests` answered 403 `PermissionScopeNotGranted`.

#### Nothing ever leaves the tenant

An invitation names a real mailbox and Entra will mail it, so this is the one object in the module
that could reach a person who never agreed to be in a lab. Three things prevent it, and a contract
test pins each:

- `sendInvitationMessage` is **false and is not a parameter**. There is no `-SendInvitationMessage`,
  no `-Notify`, and no way to make this module send mail.
- Every address is on **`example.com`**, which RFC 2606 reserves and nobody can register — the same
  rule the named locations follow with RFC 5737 documentation ranges.
- The redemption redirect points at the same reserved domain.

#### The prefix goes in the local part, and that is load-bearing

Entra derives a B2B UPN by replacing the `@` in the invited address:

```
ENTRALAB-gmember@example.com  ->  ENTRALAB-gmember_example.com#EXT#@contoso.onmicrosoft.com
```

So the prefix survives into the UPN **only from the local part**. Put it in the domain instead and
every guest stops matching `startswith(userPrincipalName, 'ENTRALAB-')`, which is the query
teardown finds users by. A contract test asserts the prefix token is anchored at the start.

One related detail in `Get-EntraSeededObject`: a B2B UPN always lands on the tenant's **initial**
`onmicrosoft.com` domain, never on a custom one. Requiring the seed suffix would leave every guest
unclaimed whenever `-UpnSuffix` names a verified domain, so a `#EXT#` UPN carrying the prefix is
accepted on any domain. The `#EXT#` marker is minted by Entra and cannot be typed by hand, which
is what makes widening it safe.

### Licensing

The one shape reporting scripts consistently get wrong: **Priya holds the same SKU twice**, once
inherited from the licence group and once assigned directly.

Graph reports both identically in `assignedLicenses` — the same `skuId`, once. Only
`licenseAssignmentStates` distinguishes them, where the inherited entry carries the group's object
id in `assignedByGroup`. A script that reads `assignedLicenses` and stops there cannot tell
"remove this user from the group" from "remove the licence from this user".

```
ENTRALAB-Priya Raghunathan
    FLOW_FREE (Direct)
    FLOW_FREE (Inherited from ENTRALAB-Licence Power BI)
ENTRALAB-Marcus Bell
    FLOW_FREE (Inherited from ENTRALAB-Licence Power BI)
```

The SKU is chosen at run time from what the tenant has spare, preferring the no-cost ones.

### Devices (694 = 6 core + 688 bulk)

Source: `Data\EntraDevices.csv`. Compliant, non-compliant, unmanaged, mobile, **orphaned** (no
registered owner — what a departed user leaves behind) and disabled. The bulk devices carry a
deterministic mix of platforms and compliance states derived from a stable hash of their own name.

> **These are directory objects, not registered devices.** A real device object is created by a
> device actually joining, which produces a certificate and a hardware identity. One created
> through Graph has neither. It is enough to be found by a report, counted in an inventory, owned
> by a user and named by a membership rule. It is **not** enough to sign in from, so a Conditional
> Access evaluation will never see one as the device in play.

> **`trustType` and `profileType` are not settable.** Verified live: both are accepted in the
> create body and silently come back empty. `isCompliant`, `isManaged` and `accountEnabled` stick.

### Applications (6)

| App | Service principal | Assignment shape it creates |
|---|---|---|
| Expense Portal | ✅ | A group **and** a user already in it — a naive union double-counts |
| Engineering Wiki | ✅ | Group only — the control case |
| **Payroll Console** | ✅ | **A direct assignee in no assigned group** |
| Legacy Reporting Tool | ✅ | **Nobody at all** — what access reviews exist to find |
| Hidden Utility | ✅ | Carries `HideApp` — absent from My Apps, present in every audit |
| Unconsented Integration | ❌ | **An application with no service principal** |

Marcus is assigned to the Payroll Console directly and belongs to no group that has it, so a report
that expands group assignments and stops there misses him entirely.

### Named locations (3) and Conditional Access policies (8)

All IP ranges are IANA documentation blocks, reserved by RFC 5737 so they cannot belong to
anybody. A lab location containing a real routable range is a policy that could really lock
somebody out; a contract test enforces it.

| Policy | What it demonstrates |
|---|---|
| Require MFA for Seeded Staff | The ordinary baseline, with a break-glass style exclusion group |
| Require Compliant Device | **Unsatisfiable** for anyone on a non-compliant device |
| Block Legacy Authentication | Legacy clients cannot satisfy any grant, so this blocks regardless |
| Block Outside Permitted Countries | The **inverted** condition — everywhere except these |
| Require MFA on Elevated Sign-in Risk | Conditions on risk, so it applies to only a subset |
| Limit Unmanaged Browser Session | **Session controls only, no grant control** |
| Require Phishing Resistant MFA | An authentication **strength** rather than a plain MFA grant |
| Require MFA And Compliant Device | An **AND**, where satisfying one control is not enough |

These are the inputs a Conditional Access evaluation tool such as `CaOutcome` exists to evaluate.

## ☁️ The cloud IdP layer, and Okta parity

Okta's module seeds a set of features that are not directory objects at all — network zones,
trusted origins, event hooks, custom profile attributes on multiple user schemas. This is where
each of those lands in Entra, and where it does not.

| Okta | Entra equivalent | Seeded |
|---|---|---|
| Network zones | **Named locations** — IP and country | ✅ 6 |
| Custom profile attributes | **Directory extensions** on a schema app | ✅ 10 |
| Trusted origins (CORS/redirect) | **Reply URLs**: `web` for redirects, `spa` for CORS | ✅ on 6 apps |
| Group rules | **Dynamic groups** | ✅ 2 |
| Sign-on policies | **Conditional Access policies** | ✅ 8 |
| Custom admin roles | **Custom directory roles** | ✅ 3 (definitions only) |
| *(no equivalent)* | **Authentication strengths** | ✅ 3 |
| Password policy | Authentication methods policy — a tenant-wide singleton | ❌ read only |
| Event hooks | Change notification subscriptions | ❌ see below |
| User types | *(no equivalent — Entra has one user schema)* | — |
| Linked objects | *(no equivalent — `manager` is the only typed relationship)* | — |

### Directory extensions: the custom-attribute story

Ten attributes on a dedicated `ENTRALAB-Schema` application, chosen for **type coverage rather
than realism**, because a schema of nothing but strings will not tell you that your export
flattened a binary value or that a 64-bit integer lost precision through a double.

| Attribute | Type | Target | What it exercises |
|---|---|---|---|
| `labSeedTag` | String | User | A **filterable** marker — see below |
| `labBadgeId` | String | User | A predictable shape for pattern matching |
| `labClearanceLevel` | String | User | Where Okta would validate an enum, Entra cannot |
| `labIsContractor` | Boolean | User | The non-string branch |
| `labRiskScore` | Integer | User | **Zero is falsy**, so `if ($value)` drops it |
| `labHeadcount` | LargeInteger | User | 64-bit, loses precision through a double |
| `labContractEndDate` | DateTime | User | A real date type, where Okta stores a string |
| `labBadgePhoto` | Binary | User | Breaks anything assuming a profile is printable |
| `labCostCentre` | String | **Group** | Okta cannot attribute a group at all |
| `labAssetTag` | String | **Device** | Okta cannot attribute a device at all |

Three things make these different from the `extensionAttribute1-15` used as the seed tag:

- **They are filterable.** Verified live: `$filter=extension_..._labSeedTag eq 'ENTRALAB-seed'`
  returns all 305 users, where `extensionAttribute15`, `employeeType` and `companyName` are all
  rejected with `Request_UnsupportedQuery`. A directory extension is the only writable, queryable
  marker on a user.
- **They target more than users** — two of the ten sit on groups and devices.
- **They are namespaced to the owning application**, as `extension_<appId>_<name>`. Deleting that
  application takes the attributes and every value stored in them with it, which is why teardown
  of the schema is a single operation.

What they cannot do, and Okta can: there is **no enum type** and **no multi-valued type**. Okta's
`labEntitlements` array has no equivalent here.

> **Three constraints, all verified live and none documented on the request.**
>
> 1. **An extension is unusable until the owning application has a service principal.** Without
>    one the definitions are created, appear on the application, and every PATCH naming them is
>    refused with *"The following extension properties are not available"* — indefinitely, not as
>    a delay. Ten attributes sat unusable until a service principal existed.
> 2. **Existing and being writable are different states**, minutes apart.
>    `getAvailableExtensionProperties` is the authoritative signal and is polled; until an
>    attribute appears there, writes fail. On a brand-new schema application the first run
>    typically populates only some — the command says so and is idempotent, so **run it again**.
> 3. **Directory extensions can only be written to Windows devices.** A PATCH against a macOS,
>    iOS or Android device object is refused with *"Properties other than AccountEnabled and
>    ExtensionAttribute1..15 can be modified only on windows devices"*, so non-Windows devices are
>    filtered out rather than left to fail.

### Authentication strengths

Three custom strengths — hardware-backed only, passwordless, and deliberately permissive. The
permissive one exists because of a finding from `CaOutcome`: **a custom strength is editable**, so
widening one weakens every policy referencing it with no policy document changing. A baseline
watching only Conditional Access policies will not notice.

> **Two constraints.** The `displayName` is capped at **30 characters**, and the seed prefix counts
> toward it — the module checks before sending, because the failure names a length rather than the
> prefix that caused it. And a single allowed combination is *itself* comma-joined
> (`password,sms` is one value), so the seed data separates combinations with semicolons.
> `microsoftAuthenticatorPush` is **not** valid alone; Entra rejects it unless paired with
> `password`.

### Custom directory roles

Three definitions: read-only, narrow write, and one spanning two resource types.

**Definitions only — nothing is assigned to anybody.** A role definition is inert until assigned
to a principal at a scope, so creating one is safe in a tenant in real use, while assigning one is
a privilege grant that should be a deliberate human decision. The seeded role-assignable group
exists if you want to exercise that path yourself.

> Not every action is permitted in a custom role. `microsoft.directory/users/allProperties/read`
> is rejected with *"not supported for Custom Role creation"*, so the seeded write role uses
> `basic/update` and `manager/update` instead.

### Role eligibilities never activate

The counterpart rule to *CA policies never enforce*, and it strikes the same bargain. Three PIM
schedules are created over the three custom roles — all **eligible**, none active. An eligible
schedule confers nothing until a human signs in and activates it, so like a report-only policy it
is fully visible to every privilege report and grants nothing at all.

**The state is not a parameter.** There is no `-Active`, no `-AssignmentType`, no `-Permanent`,
and a contract test asserts their absence — the same test the CA policies have for `-State`. A
second test asserts that nothing is ever posted to `roleAssignmentScheduleRequests`, the endpoint
that would make an assignment standing.

| Key | Role | Principal | Scope | What it breaks |
|---|---|---|---|---|
| `elig-groupreader-user` | Lab Group Reader | Tomás Álvarez | Directory | The plain case — see below |
| `elig-userwriter-au` | Lab User Attribute Writer | Hana Kobayashi | **Administrative unit** | A report reading `roleDefinitionId` and ignoring `directoryScopeId` calls this tenant-wide |
| `elig-appreader-group` | Lab Application Reader | `role-support` **group** | Directory | The humans who can activate are one membership expansion away |

The plain case is the whole point: **`GET /roleManagement/directory/roleAssignments` returns
nothing for any of these roles.** A standing-privilege report that reads that endpoint and stops —
which is most of them — concludes the custom roles are held by nobody, while three principals are
one click away from holding them. The absence is the finding. `Get-TestEnvironmentReport` prints
`RoleEligibilities` and `RoleAssignments` side by side, and the second number is *measured*, not
assumed — if it is ever non-zero, somebody made a standing assignment by hand.

Three safety properties, none configurable:

1. **Only seeded custom roles.** The role is resolved through `Get-EntraSeededObject`, which
   returns prefixed custom definitions and refuses built-ins. A row naming a role that does not
   resolve that way is skipped rather than guessed at, so there is no path from seed data to
   eligibility for Global Administrator. A contract test asserts every `RoleKey` in the CSV
   resolves to a row in `EntraDirectoryRoles.csv`.
2. **An AU-scoped row whose unit is missing is skipped, never widened.** Falling back to `/`
   would silently turn a deliberately narrow grant into a directory-wide one.
3. **Each schedule expires on its own** — `afterDuration`, thirty days, rather than
   `noExpiration`. A lab nobody ever tore down stops offering the activation.

At teardown these are **withdrawn rather than deleted**: a schedule has no `DELETE`, so the removal
is a second request posted with `action: adminRemove`. It runs before the role definitions, because
a definition with a live eligibility pointing at it cannot be deleted, and before the users and
groups, because deleting a principal strands its eligibility.

Verified against a live tenant that held five real eligibilities of its own, one of them **Global
Administrator**: creating the three seeded schedules left `roleAssignments` returning **zero** for
all three custom roles, discovery claimed exactly the three and none of the five, and the teardown
withdrew exactly the three and left the tenant back at five. Two details worth knowing from that
run — Graph rewrites an `afterDuration` expiry into `afterDateTime` with a concrete `endDateTime`,
and the id to keep is `targetScheduleId` off the request rather than the request's own `id`, which
addresses a different object at a different endpoint.

> **Needs Entra ID P2.** Without it the create is refused and the step warns and continues; the
> custom roles still exist and nothing is eligible for them. Skip it with
> `-Skip RoleEligibilities`. The permission is the same `RoleManagement.ReadWrite.Directory` the
> role definitions already need, so no re-consent is required.

### What cannot be seeded, and why

- **Event hooks / change notification subscriptions.** Graph performs a validation handshake at
  creation: it POSTs to the `notificationUrl` and requires a `200 OK` echoing a token within
  seconds. There is nothing to answer it, so creation fails with *"Subscription validation request
  failed"*. Okta's event hooks seed fine because Okta only checks the hostname resolves. This one
  needs a real listener and cannot be faked.
- **Custom security attributes.** These would give the enum and multi-valued types directory
  extensions lack, but they need the **Attribute Definition Administrator** role, which a Global
  Administrator does **not** hold by default — verified live, the create is refused with
  `Authorization_RequestDenied`. Assign that role to the app and they become possible.
- **Terms of use agreements.** Need `Agreement.ReadWrite.All`, which is not covered by directory
  roles.
- **The authentication methods policy and cross-tenant access settings.** Both are tenant-wide
  singletons rather than objects, so seeding them would mean editing live configuration that
  applies to real users. They are deliberately read-only here.

## 🔄 Regenerating the seed data

`Tools\New-EntraSeedData.ps1` rebuilds the CSVs from ADTestEnvironment's. It is an authoring
tool: the module never calls it and has no run-time dependency on the AD module.

```powershell
.\Tools\New-EntraSeedData.ps1 -Verbose
```

The hand-designed core rows are written into the tool and preserved verbatim; only the bulk is
generated. Everything derived — compliance state, usage location, platform — comes from a stable
SHA-256 hash of the object's own key rather than `Get-Random`, so regenerating produces
**byte-identical files** and a diff shows real changes rather than churn.

## 🧹 Teardown

```powershell
Remove-TestEnvironment -WhatIf                    # always worth running first
Remove-TestEnvironment -Force
Remove-TestEnvironment -Force -PurgeRecycleBin    # ready for an immediate re-seed
Remove-TestEnvironment -Keep Users, Groups -Force # rebuild everything above the directory
```

**`-WhatIf` beats `-Force`.** Somebody passing both is asking what would happen, not asking to be
spared the question.

The order is forced by Entra's own dependencies. Three steps are not obvious and none is inferable
from the API surface:

1. **Conditional Access policies**, then **named locations** — and a trusted location is
   **un-marked as trusted first**, because Entra refuses to delete one while it is trusted.
2. **Licences are removed from the group before the group is deleted**, because Entra refuses to
   delete a group that still holds one.
3. **Administrative units go genuinely last**, after their contents, because deleting a container
   first would discard the authoritative record of what to delete.

Users, groups and devices are deleted in batches, for the same reason they are created in them.

### Soft delete, and why `-PurgeRecycleBin` exists

Users, groups and applications go to the directory recycle bin for thirty days, and **they behave
differently there**:

- A deleted **user** has its UPN rewritten to `<id-without-dashes><original-upn>`, freeing the
  original for immediate reuse.
- A deleted **group keeps** its `displayName` and `mailNickname` reserved for the full thirty days.

So a tear-down-then-immediately-re-seed collides on groups and not on users. `-PurgeRecycleBin`
removes them permanently, which is irreversible and is why it is not the default. Devices, named
locations, Conditional Access policies and administrative units are not soft-deleted at all.

The purge only ever touches objects matching the prefix.

## 🔍 Gotchas worth knowing

Every one of these actually happened while building this, against a real tenant.

**Replication lag is real, reproducible, and reported three different ways.** A `DELETE`, `PATCH`
or `$ref` POST issued seconds after a create returns **404**. Creating a service principal for a
just-created application returns **400** — *"The appId does not reference a valid application
object"* — which is indistinguishable from a malformed request by status code alone. And a
**read** lags too: immediately after placing 305 users in an administrative unit, the unit
reported 72 members, then 684, then all of them. That last one matters most, because a report run
too early looks like a failure that never happened.

**`onPremisesExtensionAttributes` cannot be set on create.** Graph rejects it on `POST /users` and
accepts it on `PATCH`. Every seeded user therefore takes two calls.

**Graph reports a duplicate administrative unit membership differently from a duplicate group
member.** It is *"A conflicting object with one or more of the specified property values is
present in the directory"*, not the *"already exist"* wording used elsewhere. Matching only the
latter made a fully successful placement report zero placed and 305 failed.

**Conditional Access reports every body it dislikes as one generic error.** Error 1007, *"Incoming
ConditionalAccessPolicy object is null or does not match the schema"*, names no field. The real
cause was that `includeLocations = if (...) { $ids } else { @('All') }` **unrolled the
single-element array to a bare string**, so the request carried `"includeLocations":"All"` instead
of `["All"]`. A PowerShell trap, not a Graph one. The seeding function dumps the constructed body
to the verbose stream so the next one is diagnosable in one run, and it is deliberately **not**
retried — 1007 is not transient.

**`continue` inside a `switch` does not continue the enclosing `foreach`.** It breaks out of the
switch. A guard written as a `default` branch rejecting an unsupported group kind therefore fell
straight through and created the group anyway. Found by a unit test, not by a run.

**Batched requests need their own headers.** A `$count` segment needs `ConsistencyLevel: eventual`
and a body needs `Content-Type`, and the outer batch call's headers reach neither.

**`Uri.ToString()` renders a URI in its *unescaped* form.** A test asserting a query value was
escaped will read a literal space where the request really carries `%20`. `AbsoluteUri` preserves
it.

**Graph pages with an absolute URL, and will hand back one pointing at the page you just
fetched.** Following it without comparing against the current URL is an infinite loop that presents
as a slow tenant.

**A token's `roles` claim understates what an app can do.** Directory roles assigned to the service
principal grant permissions that never appear in the token.

## 📖 Command help

`Get-Help` on any exported command reads compiled MAML, not the comment block. The source is the
Markdown under `docs\TestEnvironment\`, one page per command plus a module page, and
`about_TestEnvironment` covers what no single command owns: the provider model, the prefix and
seed tag, the two safety properties with no parameter, and how teardown proves ownership.

```powershell
Get-Help New-TestEnvironment -Full
Get-Help about_TestEnvironment
Get-Help New-EntraGroup -Online          # the same page on GitHub
```

Editing help means editing the Markdown and rebuilding:

```powershell
./Build/Build-Help.ps1                   # validates docs\ and rebuilds en-US\TestEnvironment-Help.xml
```

Commit the rebuilt MAML with the Markdown. CI rebuilds from the committed Markdown and fails if
the two disagree, because `.EXTERNALHELP` serves stale compiled help in preference to anything
correct.

## 🧪 Tests

Pester 6 unit tests live in `Tests\Unit\`, mirroring the module's own layout: shared concerns
under `Core\`, provider-specific ones under `Providers\<name>\`, and the module-wide contract at
the root. **1,241 tests, every Graph call, RSAT cmdlet and Okta request mocked**, so the suite reaches no tenant, no domain and no org, creates
nothing, and is safe to run on a workstation.

```powershell
Invoke-Pester -Path .\Tests

Invoke-Pester -Path .\Tests -TagFilter 'Contract'     # manifest, exports, layout, seed data
Invoke-Pester -Path .\Tests -TagFilter 'Safety'       # ownership proof, report-only, scoping
Invoke-Pester -Path .\Tests -TagFilter 'Destructive'  # the teardown paths
```

| File | Covers |
|---|---|
| `Module.Contract.Tests.ps1` | Manifest validity, export agreement, one function per file, no cmdlet shadowing, no stray files at the module root, no duplicate function names across providers, and that nothing provider-specific has crept into `Core` |
| `Core\ConvertTo-TestBase64Url.Tests.ps1` | Padding, URL-unsafe characters, byte-exact round trips including leading zeros |
| `Core\Initialize-TestSecretVault.Tests.ps1` | That a locked store is detected by the error it throws, that an unlock failure is fatal rather than a warning, and that the vault is proven before anything remote is created |
| `Providers\Entra\SeedData.Tests.ps1` | The shape and referential integrity of all 1,100 seed rows |
| `Providers\Entra\New-EntraClientAssertion.Tests.ps1` | That the JWT verifies against its own public key, that `x5t` is the thumbprint **bytes** not its hex text, and that the audience is the v2.0 tenant endpoint |
| `Providers\Entra\Invoke-EntraRequest.Tests.ps1` | UTF-8 both ways, query encoding, pagination and its loop guard, both retry policies, and that the inner exception is set rather than stringified |
| `Providers\Entra\Invoke-EntraBatch.Tests.ps1` | Chunking at twenty, correlation by id rather than position, per-response status, and that only the throttled request is retried |
| `Providers\Entra\Get-EntraSeededObject.Tests.ps1` | That the container is authoritative, that the fallback still runs when it is gone, and that neither claims **anybody else's** objects |
| `Providers\Entra\New-EntraGroup.Tests.ps1` | That a dynamic rule without the seed prefix is refused, that an uncreatable group kind is refused, that nesting is built and groups are contained |
| `Providers\Entra\New-EntraConditionalAccessPolicy.Tests.ps1` | That every policy is report-only, that no parameter can enable one, that an unscoped policy is refused, and that `includeLocations` survives JSON as an array |
| `Providers\Entra\Remove-EntraEnvironment.Tests.ps1` | That `-WhatIf` beats `-Force`, the licence-before-group, untrust-before-delete and units-last ordering, and that the bin purge spares objects that are not ours |
| `Providers\Entra\New-EntraEnvironment.Tests.ps1` | Step ordering, `-Skip`, failure isolation, and a backstop that fails loudly if any step escapes the mocks and reaches a real tenant |
| `Providers\AD\SeedData.Tests.ps1` | The shape and referential integrity of all 1,099 AD seed rows: the 20-character `sAMAccountName` cap, dangling managers and group nesting, group scopes AD will actually accept, and that the people are still shared with the Entra data |
| `Providers\AD\Remove-ADEnvironment.Tests.ps1` | That `-WhatIf` beats `-Force`, and that the group sweep searches the whole container rather than one sub-OU |
| `Providers\AD\New-ADTestGroupPolicy.Tests.ps1` | That a real policy sharing the seeded name is not adopted, linked or deleted |
| `Providers\AD\New-ADTestOU.Tests.ps1` | Path construction and the skip-if-present behaviour a re-run depends on |
| `Providers\AD\Remove-ADTestSecretVault.Tests.ps1` | That the vault is unregistered without resetting a store other modules share |

The AD provider's tests run without RSAT at all, against generated stubs in `Tests\Stubs`, which are appended to `PSModulePath` rather than prepended - so a host that really has RSAT exercises the true binding surface instead.

The compatibility shims for the three modules this one replaced stayed behind in the repository
this module was split from, each with a small suite asserting that the old names still accept
the parameters they used to.

Several are regressions for bugs found while building — the array unrolling, the `continue` in a
`switch`, the unscoped dynamic rule that captured two real accounts, the 404 that placed 72 of 305
users — and each assertion would have caught its bug before a tenant ever saw it.

The backstop in `New-TestEnvironment.Tests.ps1` exists because of a defect in the Okta
module's suite: a step was added to the orchestrator without a mock, and those tests quietly made
real network calls for a while. A suite whose central promise is "this reaches no tenant" has to
enforce that promise rather than assert it in a comment.

## 🖥️ The Active Directory provider

Seeds a domain the way the Entra provider seeds a tenant: volume, held in one container, with
ownership proved before anything is deleted. `OU=TestData` is the container, and it is where the
Entra seed users came from — the same people exist in both labs, which is what makes hybrid
identity matching testable.

```powershell
Connect-TestEnvironment -Provider AD
New-TestEnvironment -ShowProgress
Get-TestEnvironmentReport
Remove-TestEnvironment -Force
```

| | Count |
|---|---|
| Organisational units | 43 |
| Users | 296 |
| Service accounts | 25 |
| Devices | 688 |
| Security groups | 90 (5,685 memberships) |

### Connecting, when there is nothing to authenticate

Active Directory is reached with the caller's own Windows identity, so `Connect-TestEnvironment
-Provider AD` takes no credentials. It exists to prove, once, the four things every later call
assumes: that the RSAT modules import, that the session is elevated, that a domain answers, and
that the seed data is on disk. Without it the first failure lands halfway through a seeding run,
after some objects exist and some do not, naming a missing cmdlet rather than a missing feature.

`-Server` pins the session to one domain controller. `-InstallRsat` installs the RSAT features if
they are absent — opt-in, because it is a machine-wide change.

### Why the AD commands keep their `Test` infix

The Entra components dropped it: `New-EntraTestUser` became `New-EntraUser`. The AD ones did not,
and the reason is collision rather than taste. `New-ADUser`, `New-ADGroup`, `New-ADComputer` and
`Get-ADDomain` are real cmdlets from the module this provider imports. A function of the same
name is found ahead of the cmdlet by everything else in the session, so `New-ADTestUser` stays
`New-ADTestUser`. A contract test enforces that no provider function shadows a cmdlet.

Only the environment-level commands changed, because the shared dispatchers need a predictable
shape: `New-ADTestEnvironment` → `New-TestEnvironment`, and likewise for teardown and the report.

### 📌 This provider writes `adminDescription` on every object it creates

**If you use `adminDescription` for anything in your directory, read this before seeding.**

Every object the AD provider creates — users, computers, groups, service accounts and the
organisational units themselves — is stamped with the seed tag in the **`adminDescription`**
attribute:

```
adminDescription : ZZ-TEST-seed
```

Find them all, and only them, with one filter:

```powershell
Get-ADObject -LDAPFilter '(adminDescription=ZZ-TEST-seed)'
```

**Why that attribute.** It is base schema — present in every AD since Windows 2000, so nothing is
installed and **no schema extension is made**. It is defined on `top`, so one attribute covers
every class this provider creates rather than needing a different field per class. ADUC does not
show it in the default view, so it does not clutter what a person reads. And nothing else
typically writes it, which is the point: the tag cannot be defeated by somebody editing a
description.

**What was rejected, and why.** `extensionAttribute1`–`15` come from the Exchange schema
extension and simply do not exist on a forest that has never had Exchange — verified absent on
the lab domain — and where they do exist they are commonly already claimed by HR synchronisation.
A genuinely custom attribute was rejected outright: extending the schema is **irreversible**, as
an attribute can be deactivated but never deleted, it needs Schema Admins, and it replicates
forest-wide permanently. A module whose whole promise is that teardown removes everything it made
has no business leaving a permanent mark on your forest schema.

`description` is left alone and carries only what the seed CSV says, so it still reads like a
description.

#### The tag is load-bearing at teardown, not decorative

`Remove-ADEnvironment` does not delete an object because of where it sits. Being inside
`OU=Test` is what makes an object a *candidate*; carrying `ZZ-TEST-seed` in `adminDescription`
is what makes it a *target*. Anything in the seeded containers without the tag is left standing
and reported:

```
WARNING: The group 'Finance Payroll Admins' is inside the seeded container but does not carry
ZZ-TEST-seed in adminDescription, so this module cannot prove it created it. Leaving it alone.
```

This matters because a test OU is exactly the kind of place somebody parks a real object "just
for a minute". The module refuses to be the reason it disappears.

Two consequences follow from that rule:

- **`-RemoveOUs` will decline to remove an OU that still holds untagged objects.** Otherwise
  `Remove-ADOrganizationalUnit -Recursive` would delete the object the sweep had just spared,
  seconds after warning about it. The OU is reported as retained, with the reason.
- **Teardown also sweeps the whole domain**, not just the seeded OUs, using
  `(adminDescription=ZZ-TEST-seed)`. A tagged object that ended up outside the containment root
  is still this module's to clean up, and it is reported separately so you can see it happened.

The rule is deliberately asymmetric: **the tag can only ever spare an object or claim one the
module made.** It never causes something untagged to be deleted.

### RSAT is imported at connect time, never declared

`RequiredModules` is empty and a contract test keeps it that way. The old module declared
`ActiveDirectory`, which made importing it fail outright on any host without RSAT — including
every CI runner, and any machine that only wanted the Entra provider. The dependency is now
loaded at the moment it is genuinely needed, and its absence is reported as a sentence rather
than a binding error.

The unit tests run without RSAT at all, against the stubs in `Tests/Stubs`.

## 🔷 The Okta provider

The smallest of the three by object count and the most varied by object type. An Integrator Free
Plan org allows ten active users, so this provider proves breadth where the others prove volume:
group rules, custom user types, network zones, sign-on and password policies, trusted origins,
event hooks and linked objects — the cloud-IdP surface that has no on-premises equivalent.

```powershell
# First run: trade an API token for an app that can act on its own
$token = Read-Host 'SSWS token' -AsSecureString
Connect-TestEnvironment -Provider Okta -OrgUrl https://trial-123456.okta.com -ApiToken $token
New-TestServiceApp

# Every run afterwards
Connect-TestEnvironment -Provider Okta -OrgUrl https://trial-123456.okta.com -ServiceApp
New-TestEnvironment
Get-TestEnvironmentReport
```

| | Count |
|---|---|
| Users | 8 (of a 10-user ceiling, leaving room for a second admin) |
| Groups / group rules | 17 / 3 |
| Apps | 9, across three sign-on modes |
| Custom attributes | 18 across 2 user types |
| Network zones / policies | 2 / 3 |
| Trusted origins / event hooks / linked objects | 2 / 2 / 1 |

### The bootstrap runs the other way round from Entra's

Okta *does* have a long-lived personal API key, so the trade is real: paste an SSWS token once,
let the module register an OAuth service app with only the `okta.*` scopes it needs, and revoke
the token. Entra has no such key to trade, which is why its bootstrap signs a human in by device
code instead. Same destination, opposite starting point.

`okta.clients.manage` is deliberately withheld from the app, so rotating its key always needs a
token — keep one rather than revoking every time.

### Names dropped their `Test` infix

`New-OktaTestUser` became `New-OktaUser`, and so on, matching the Entra provider. Okta ships no
PowerShell cmdlets of its own, so there is nothing to collide with — which is exactly why the AD
provider's names could not do the same.

## 🏛️ Architecture

```
TestEnvironment/
├── Core/                 shared by every provider: SecretStore, certificates,
│                         password generation, secure strings, base64url,
│                         progress, credential paths
├── Providers/
│   ├── AD/               Private/ Public/ Data/
│   ├── Entra/            Private/ Public/ Data/ Tools/
│   └── Okta/             Private/ Public/ Data/ + Initialize.ps1
├── Public/               the provider-agnostic surface, which dispatches
└── Tests/Unit/           Core/, Providers/<name>/, and the module-wide contract
```

### Where each provider stamps the tag

The tag value is identical everywhere — `ZZ-TEST-seed`, derived from the prefix, because two
settings that must agree for teardown to work are one setting too many. Where it is *stored*
differs, because each directory offers a different native place to put it:

| Provider | Attribute | Note |
|---|---|---|
| `AD` | `adminDescription` | base schema, on `top`, nothing else writes it — **see the AD section above** |
| `Entra` | `description` | inside a sentence, so it still reads like a description in the portal |
| `Okta` | `labSeedTag` profile attribute, plus the tag appended to descriptions | a custom profile attribute the module defines |

**Three modules became one because of what they duplicated.** SecretStore handling, certificate
persistence and password generation had three implementations that were converging on the same
lessons separately — a locked vault detected by the error it throws, a private key that survives
only through a PFX round trip — and each one learned them at its own pace. Those now live in
`Core` and are learned once.

The AD merge is what that looks like in practice: its password generator, its secure-string
helper and its unbiased random-index helper all disappeared into `Core` equivalents that already
existed and were slightly better — Core's generator excludes ambiguous characters, and its
inline reject sampling made the separate index helper dead code.

**The provider split is about what genuinely differs.** An administrative unit is not an OU and a
Conditional Access policy is not an Okta sign-on policy, so the components keep their own names
(`New-EntraGroup`, `New-EntraConditionalAccessPolicy`) rather than hiding behind a shared noun
that would fit none of them. What *is* common — connect, seed, report, tear down — is shared:
`New-TestEnvironment` forwards to the active provider and mirrors its parameters, so you get tab
completion and binding errors from the real command rather than a pass-through that accepts
anything.

Providers are discovered from the `Providers` folder at import, not listed in code. A new one
appears by existing.

**`RequiredModules` is empty, and a contract test enforces it.** The providers do not share a
platform: Entra and Okta reach a REST API from any host, while AD needs RSAT's `ActiveDirectory`
and `GroupPolicy`. Declaring those here would impose a Windows-only, RSAT-only dependency on
somebody who only wanted to seed an Okta org from a container, so the AD provider will import
them lazily at connect time instead.

### The modules this one replaced

`ADTestEnvironment`, `EntraTestEnvironment` and `OktaTestEnvironment` survive as compatibility
shims in the repository this module was split from. Each forwards every name it used to export to
an installed copy of this module, so existing scripts keep working unchanged;
`Connect-EntraTestEnvironment` supplies `-Provider Entra` for you. New work should use the names
above.

## 📊 Module information

- **Version**: 1.0.0
- **Author**: Jeffrey Stuhr (EntraVantage LLC)
- **PowerShell**: 5.1+ (Desktop/Core compatible)
- **Dependencies**: none
- **Providers**: Entra, Active Directory, Okta
- **Module GUID**: c4e91b7d-5a63-4f28-9d10-8b2e6f3a71c5

## 📞 Support & contact

- **Author**: Jeffrey Stuhr
- **Company**: EntraVantage LLC
- **Blog**: https://www.techbyjeff.net
- **LinkedIn**: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/

For issues, feature requests, or contributions, please use the
[issue tracker](https://github.com/fadwen/TestEnvironment/issues).

## 🔗 Source

[github.com/fadwen/TestEnvironment](https://github.com/fadwen/TestEnvironment)

## 📄 License

Copyright (c) 2026 EntraVantage LLC. Released under the [MIT License](LICENSE). It comes with no
warranty, which is worth reading literally for a tool that creates and deletes directory objects:
point it only at a tenant, domain or org you can afford to reseed.
