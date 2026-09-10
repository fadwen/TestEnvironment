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
| Applications / providers | 6 / 5, over OAuth2 and proxy providers; one with no provider, one hidden |
| Expression policies | 3, bound to applications; one binding disabled |
| Notification rules / transports | 2 / 2, webhooks that nothing answers |

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

An expression policy governs nothing until a binding attaches it to a target, and the target of
an application binding is the application's `pbm_uuid`, not its `pk`. Bind to the wrong one and
the policy is created, reported, and enforces nothing. The seed resolves the target from the
seeded applications by slug, so the CSV never sees a UUID.

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
