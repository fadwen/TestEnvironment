# The Authentik provider

Part of [TestEnvironment](../../README.md).

The newest of the four, and the one built against an instance you run yourself rather than a
tenant somebody rents you. Authentik has no fixed profile schema and no organizational units; it
has free-form attributes on every user and group, a `path` on every user, and applications that
are thin objects over providers. The seed uses each of those as the shape it is: the lab
attributes go into `attributes`, the seed tag with them, and every seeded user sits under a path
of the module's own, which is what a listing can filter on and what teardown enumerates.

```powershell
# First run: trade an API token for a service account that can act on its own
$token = Read-Host 'API token' -AsSecureString
Connect-TestEnvironment -Provider Authentik -BaseUrl https://auth.example.com -ApiToken $token
New-TestServiceApp

# Every run afterwards
Connect-TestEnvironment -Provider Authentik -BaseUrl https://auth.example.com -ServiceAccount
New-TestEnvironment
Get-TestEnvironmentReport
```

| | Count |
|---|---|
| Groups | 98 = 9 core + 89 bulk. The core nests three deep, one with an accented name, one empty; the bulk brings AD's own nesting, some groups with more than one parent |
| Users | 306 = 10 core + 296 bulk. The core is internal, external and a service account, one disabled, three accented names; the bulk is AD's people, 33 of them contractors |
| Roles | 3, RBAC roles with view and password-reset permissions, assigned through groups; one held by nobody |
| Applications / providers | 9 / 8, over OAuth2, proxy, SAML, LDAP and RADIUS providers; one with no provider, three hidden |
| Outposts / certificate | 3 / 1: a proxy, an LDAP and a RADIUS outpost, none deployed, and the self-signed keypair the SAML provider signs with |
| Scope mappings | 3, custom claims built from the lab attributes and attached to the OAuth2 providers; one with no consent description |
| Application entitlements | 6, across four applications; one granted to nobody |
| Policies | 7 of five types: three expression policies bound to applications, a password policy bound to nothing, reputation and GeoIP policies on the intranet, and an event matcher bound to a notification rule |
| Bindings | 11: groups and a user bound straight to applications, groups and users bound to entitlements, a disabled user still holding one, and the policy that makes the alert rule fire |
| Tokens | 3: a non-expiring API key on the service account, an app password with twenty minutes to run, an app password on the disabled account that expired a day ago |
| Invitations | 3: one live and single-use, one reusable, one with a year to run and no hire left to use it |
| Notification rules / transports | 2 / 2, webhooks that nothing answers |

### What the demo can show now

The directory is only the floor. The layers above it are what an identity demo is usually about,
and each one is seeded in the state a report has to survive rather than the state that looks tidy:

- **Assignments.** Access is granted three ways on purpose: by expression policy, by a group bound
  straight to the application, and by a user bound directly. Contractors are admitted to the wiki
  by group and refused payroll by policy, so a report that reads only one mechanism is wrong about
  them. Entitlements are Authentik's per-application roles; one is held by a disabled user and one
  by nobody.
- **Roles.** Authentik's own RBAC, granted through groups the way the product intends. One role is
  reached through a team three levels down the nesting chain, and one has no holder.
- **Claims.** Every custom claim in Authentik is an expression over attributes, and the seed makes
  three: a nested object, a list, and a scope the consent screen never mentions.
- **Credentials and lifecycle.** A token that never expires, one that already has, a reusable
  invitation, and one with a year to run whose hire fell through months ago.
- **Controls of every type.** Password, reputation, GeoIP and event-matcher policies alongside the
  expression ones, one of them bound to nothing, which is the finding an audit exists to surface.
- **Every kind of integration.** A SAML service provider with signed responses, an LDAP provider
  for the appliances that speak nothing else, a RADIUS provider with MFA support on, and the
  outposts that would serve them, created with no service connection so nothing is deployed and
  an inventory has to tell a record from a running one.

Authenticator devices are the one layer deliberately absent. The admin endpoints for TOTP, static
and WebAuthn devices create them for the caller only; the owner is read-only, so there is no way to
seed MFA state onto a seeded user through the API.

### Two tiers, and `-Tier` for a fast rebuild

The users and groups have two halves, the same split the Entra provider makes. `Core` is the
hand-designed rows, chosen to be awkward in ways that break scripts. `Bulk` is the AD provider's
directory mapped across: the same 296 people with their titles, departments, offices and manager
chains, and the same 89 groups with the nesting AD gives them. The same person then exists in the
AD, Entra and Authentik labs, so anything matching identities across a hybrid boundary has three
directories that genuinely correspond. Okta's seed stays small because a developer org caps its
users; an instance you host has no such limit, and Authentik gets the full estate.

```powershell
# The designed edge cases only. Seconds rather than minutes.
New-AuthentikGroup -Tier Core
New-AuthentikUser -Tier Core
```

Volume does not make any of the designed cases more likely to be found, so when the thing under
test is behaviour rather than scale, `-Tier Core` is the faster loop. Authentik has no batch
endpoint, so every object is one call, and a small self-hosted instance answers a create in a
second or two: the full seed is a ten-to-fifteen-minute run, and so is the teardown.
`New-TestEnvironment -ShowProgress` draws a bar through the two long steps. Nothing in the bulk touches
the core policy targets: no bulk user joins `Department Finance`, so the payroll policy still admits
exactly one person, and every bulk contractor sits in `Contractors` and outside `All Staff`, where
the deny policy expects them.

Membership in the bulk is derived from what the AD data says rather than sampled: a person's
department group, the employment-type groups for their `EmployeeType`, the management-level groups
their title implies, and the office group for their `Office`. Groups nothing in the data can decide,
the resource and application access groups, take a stable sample of the population, so none is
empty by accident and none is everybody. Authentik users carry their own group list, so a member
costs nothing beyond the call that creates the user, and a group of 265 members is as cheap to
seed as a group of three.

### The service account is a superuser, and that is the point

`New-TestServiceApp` creates a `service_account` user, replaces the app-password token the
creation call hands back with a non-expiring api-intent token, since only the latter is accepted
as a bearer credential, adds the account to the instance's superuser group, proves the token by calling the API with it, and
writes the record `Connect-TestEnvironment -ServiceAccount` reads. It is a seeded user in every
respect but one: teardown keeps it unless you pass `-RemoveServiceAccount`, because it is the
credential doing the tearing down. Authentik's RBAC could scope it more narrowly; a lab account
that creates and deletes users, groups, applications, providers and policies needs most of the
instance anyway, and a superuser is the honest description of that.

### Ownership needs two pieces of evidence

A name carrying the prefix is not proof. Users have to be under the seed path *and* carry the
tag; groups the prefix *and* the tag; applications the slug prefix *and* the bracketed marker in
their description, since applications have no attributes; a provider the prefix *and* either no
application or a seeded one. Policies, notification rules and transports can carry only a name,
so the prefix is all they have, and they are the types least likely to collide with anything
real.

### Policies bind to a UUID that is not the application's primary key

A policy governs nothing until a binding attaches it to a target, and the target of an
application binding is the application's `pbm_uuid`, not its `pk`. Bind to the wrong one and the
policy is created, reported, and enforces nothing. The seed resolves the target from the seeded
applications by slug, so the CSV never sees a UUID. Entitlements have a `pbm_uuid` of their own,
and a notification rule *is* a policy-binding model, so its `pk` is its target; `New-AuthentikBinding`
resolves all three from the seeded objects by the keys their own CSVs use.

A binding carries exactly one subject: a policy, a group or a user. The seeded applications use
policy engine mode `any`, so a group binding admits its members alongside whatever the expression
policies decide, which is why the rows are chosen to disagree.

### Typed policies carry their settings in one cell

A password policy has a minimum length and a GeoIP policy has a country list, and a CSV with a
column for each would be mostly empty. `AuthentikPolicies.csv` carries a `Type` and a `Settings`
cell of `key=value` pairs separated by semicolons, with `|` separating the items of a list. Each
value is sent typed: `TRUE` and `FALSE` as booleans, whole numbers as integers, so a reputation
threshold of `-5` is a number and not a string the API rejects. A comma is not a separator, so an
error message can contain one. Each type has its own create and update endpoint and one shared
listing, and a re-run refuses to turn an existing policy into a different type.

### Providers that serve through an outpost, and a certificate the seed owns

An LDAP or RADIUS provider, and a proxy provider, does nothing until an outpost runs it, and an
outpost with no service connection is a record with nothing behind it. The seed creates exactly
that: three outposts carrying the three providers, undeployed, because asking the instance to
start containers is not a test tool's business and because the undeployed state is one an
inventory genuinely has to show. A provider of the wrong kind for an outpost is reported and left
off rather than sent.

The SAML provider signs its responses, and a signature needs a keypair. Borrowing the instance's
would sign lab assertions with a real key and leave teardown nothing it could remove, so the seed
asks Authentik to generate a self-signed one named with the prefix and reuses it on every run. The
private key never leaves the instance. The RADIUS shared secret is generated at creation and
appears nowhere in the repository.

### A token's expiry is mostly the server's decision

An instance caps an app password at its default token duration, thirty minutes out of the box, and
refuses a longer one outright; an API token's expiry is assigned by the server whatever the request
says. So the seed's expiring tokens are app passwords, their `ExpiresInMinutes` stays under thirty,
and the already-expired one is an app password with a negative value, which the API accepts as
written. A `PATCH` to a token that omits `user` reassigns the token to the caller, so the seed
always sends the owner when it updates one.

Invitations go the other way: Authentik hides an expired invitation from every listing and purges
it, so one seeded already expired is invisible to the report and to teardown alike. The stale
invitation in the seed is stale by being too long-lived instead.

### Authentik makes a hidden role for some users, and deleting the user does not delete it

Every outpost gets a service account of its own, named `ak-outpost-<uuid>`, and Authentik gives
that user a hidden role named `ak-managed-role--user-<pk>` to carry its object permissions.
Deleting the outpost deletes the user and leaves the role behind, unmanaged and unnamed by anything
else, and a teardown that only removed what it created by name left three of them on the instance
for every run. Teardown finds each seeded outpost's service user by the name its uuid dictates and
removes the hidden role before the outpost, and does the same for every seeded user and for the
service account, before the account, because by then the account is the credential the session is
running on.

### A token's secret is never read

`New-AuthentikToken` creates tokens and discards the response. Authentik hands the secret out only
through its own `view_key` endpoint, nothing in the seed needs it, and the result object carries the
identifier, owner, intent and expiry and nothing else. The one token the module does read a key for
is the service account's own, once, at bootstrap.

### Regenerating the seed data

`Tools\New-AuthentikTestSeedData.ps1` rebuilds `AuthentikUsers.csv` and `AuthentikGroups.csv`
from the AD provider's data in this repository. It is an authoring tool: the module never calls it.

```powershell
.\Tools\New-AuthentikTestSeedData.ps1 -Verbose
```

The hand-designed core rows are written into the tool and preserved verbatim; only the bulk is
generated. Everything derived, clearance level and risk score, comes from a stable SHA-256 hash of
the object's own key rather than `Get-Random`, so regenerating produces **byte-identical files** and
a diff shows real changes rather than churn. A test under `Tests\Unit\Providers\Authentik`
regenerates the files into a temporary folder and fails if the committed ones differ, so a hand
edit to the bulk, or a tool change committed without its output, is caught before it ships.
