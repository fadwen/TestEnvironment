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
| Groups | 9, nested three deep, one with an accented name, one empty |
| Users | 10: internal, external and a service account; one disabled; three accented names |
| Applications / providers | 6 / 5, over OAuth2 and proxy providers; one with no provider, one hidden |
| Expression policies | 3, bound to applications; one binding disabled |
| Notification rules / transports | 2 / 2, webhooks that nothing answers |

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
