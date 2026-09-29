# The OneLogin provider

Part of [TestEnvironment](../../README.md).

Seeds users, roles, groups, apps, user mappings, security policies, API authorization servers, app
rules, a Smart Hook, a self-registration profile, MFA factors and custom user fields into one
**OneLogin** account, reports on them, and removes them again, proving ownership of each object
before deleting it. It works through the OneLogin API as an API credential. It is built to be safe in
an account real people sign in to, not only in a lab: nothing it creates can reach a real person, and
nothing real is ever pulled into what it creates.

## ✅ What it creates, reports and removes

| Object | Count | Detail |
|---|---|---|
| Custom user fields | 4 | Text; one carries the seed tag on every seeded person |
| Users | 321 | 21 hand-designed + 300 generated; every lifecycle status and state OneLogin keeps, one person locked, a manager for 317 of them, the custom fields above, and the directory identifiers a synchronised account carries |
| Licensed users | 10 | The Approved people. Everyone else is Unlicensed or Rejected on purpose, so a seed spends ten licences at most |
| Roles | 4 | 14 explicit memberships, and one more added by the enabled mapping |
| Groups | 5 | By office; 319 people placed in them |
| Security policies | 2 | Different password and lockout rules on three of the groups; the other two fall back to the default |
| Apps | 5 | OIDC web clients with Basic and Post authentication, a public client with PKCE, a native client, and SAML; 5 grants to roles |
| App rules | 2 | One enabled and one disabled, each setting a seeded app's groups claim by seeded role |
| API authorizations | 2 | 4 scopes (one granted to no app), 3 claims, and 3 seeded apps allowed to ask for them |
| Mappings | 2 | One enabled and one disabled, both gated so they can act on seeded people only |
| Smart Hooks | 1 | Pre-authentication, disabled, and gated on a seeded role |
| Self-registration profiles | 1 | Disabled, moderated, and open to the lab domain only |
| MFA factors | 3 | Email, pre-enrolled and verified, only where the account already offers it - a trial offers none, so none |

Every object in that table carries the seed prefix on its name, and nothing else in the account is
created, changed or removed.

## ⛔ What it does not touch

Nothing outside the table above. In particular, the provider creates, edits and deletes none of:

- the Default role or the default policy, or any role, group, app, policy, rule, hook, API server
  or profile it did not create;
- which policy any group but its own uses, which factors the account offers, or the account's risk
  rules;
- branding, privileges, directories or trusted identity providers;
- the account owner, any administrator, or any person it did not create - nobody who is not
  seeded is ever added to a role or group, given a manager, made one, or given a factor;
- the API credential it authenticates as.

Several things OneLogin offers are left out on purpose. **Devices**: OneLogin has no API to create
one; a device appears when an agent enrols it. **Risk rules**: a rule applies to everybody in the
account and cannot be scoped to seeded people. **Branding, privileges, trusted identity providers
and directories**: a trial refuses them, and each would change the whole account.

Two lifecycle values are not seeded because OneLogin does not keep them, each checked against a
live account: **Unactivated**, which read back as PasswordPending moments after creation, and the
**Unapproved** state, which read back as Approved. **Locked** does not hold when it is sent as a
status either, so the locked person is created Active and then locked for a year through OneLogin's
lock call, which holds on a licensed person; a re-run locks them again when less than a month is
left.

## 📋 What it needs

- **An API credential** in the OneLogin admin portal: Developers, API Credentials, New Credential,
  created by an account owner or super user, with the scope **Manage All**. Manage Users covers
  people only, and the seed also creates roles, apps, mappings, policies, hooks and custom fields.
- **Room on the account's plan** for four roles, five apps and ten licensed people. A trial has five
  roles (the Default role among them), five apps and twelve user licences (the owner among them).
- **No pre-authentication Smart Hook of the account's own.** OneLogin allows one hook of each type;
  in an account that has one, the seed reports the refusal, and `-Skip Hooks` leaves the step out.
- **Windows PowerShell 5.1 or PowerShell 7**, and nothing else installed.

Verified end to end against a OneLogin trial, from both PowerShell editions.

```powershell
$secret = Read-Host 'Client secret' -AsSecureString
Connect-TestEnvironment -Provider OneLogin -Subdomain contoso -ClientId <client id> -ClientSecret $secret -SaveSecret

New-TestEnvironment -WhatIf          # list what it would create, creating nothing
New-TestEnvironment -ShowProgress    # create it
Get-TestEnvironmentReport            # report what it created
Test-TestEnvironment                 # verify it against the seed data
Remove-TestEnvironment -Force        # remove it all

# Every run after the first
Connect-TestEnvironment -Provider OneLogin -Subdomain contoso -UseStoredCredential
```

## ⏱️ Seed: ~2 minutes, up to ~6. Teardown: ~2 minutes.

Measured for the full 321 people and every object type on a trial: a seed of 1 minute 47 seconds and
a teardown of 1 minute 42 on one run, and a seed of 5 minutes 49 seconds on another, the difference
being how long OneLogin took that day to show the role grants the users step waits for. The teardown
took 2 minutes 12 seconds on the slower run. `New-TestEnvironment -Tier Core` seeds every object
type with only the 21 hand-designed people. A seed and a teardown together stay far inside the
credential's five thousand API calls an hour.

## 🔑 Connecting

Every call goes to the account's own host, `https://<subdomain>.onelogin.com`, which serves the
token and the API whichever region the account lives in, so there is no region to name.
`-Subdomain` takes the bare name, the host or the portal URL.

`-SaveSecret` writes the client id and secret to `~/.testenvironment/<subdomain>.onelogin.json` once
the connection has been proved, with the secret protected by DPAPI on Windows, or in a SecretStore
vault with `-UseSecretStore`. `-UseStoredCredential` reads it back on later runs.
`Disconnect-TestEnvironment` revokes the token, which otherwise lives ten hours.

## 🛡️ Ownership

Nothing is deleted for matching a name, and this provider has to prove more than most, because a
OneLogin role, group or mapping has nothing but a name to prove anything with.

- **A person** needs the tag `ZZ-TEST-seed` in the custom field `zztest_seed_tag`, which the seed
  creates and nobody else writes, **and** the prefix on the username.
- **An app** needs the tag in its description **and** the prefix on its name. The description says
  "Seeded by TestEnvironment. Safe to delete." so an administrator who finds one knows what made it.
- **A role** needs the prefix, no administrators, at least one member, and every member a proved
  seeded person and every app a proved seeded app. A prefixed role holding one real person is
  refused. So is an empty one.
- **A group** needs the prefix, no administrators, at least one member, every member a proved
  seeded person, and no policy unless it is a prefixed one that is not the default.
- **A policy** needs the prefix, not to be the default, and to be used by proved seeded groups and
  nothing else.
- **A mapping** needs the prefix, match **all**, the seed-tag condition, and only add-role actions
  naming seeded roles.
- **An app rule** needs the prefix and to sit on a proved seeded app, naming seeded roles only.
- **A Smart Hook** needs the marker line `// Seeded by TestEnvironment. Safe to delete. [ZZ-TEST-seed]`
  first in its code, and conditions naming seeded roles only. A hook has no name or description.
- **An API authorization server** and **a self-registration profile** need the tag in their
  description or help text **and** the prefix on the name.
- **A custom field** needs to be declared by this provider's data **and** to start `zztest_`.

A mapping, rule or hook may also name a role that no longer exists, because teardown deletes the
roles and a re-run must still be able to prove what was left; it may never name a role that exists
and is somebody else's.

Teardown proves everything before it deletes anything, because a role is proved by the people and
apps in it, a policy by its groups, and a mapping, rule or hook by the roles it names. A prefixed
object that fails its proof is listed with the reason and left alone. `-Keep` keeps what the kept
type is proved by, and says so: keeping people keeps the field that proves them, keeping roles keeps
their people and apps, keeping policies keeps their groups, and keeping mappings or the hook keeps
the roles they name.

## 🚫 What it never does, and has no parameter for

- **No mapping is created without the seed-tag condition, with match all.** An enabled mapping acts
  on everybody who matches it; this one can only match seeded people. The condition is added by the
  code, not the data.
- **No role or group is created that nobody being seeded will hold**, because an empty one could
  never be proved and would be left behind.
- **No app's client secret is kept unless you ask.** OneLogin returns it on create and never again;
  by default the provider keeps the id and drops it. See [Saved app secrets](#-saved-app-secrets).
- **No real person is touched.** Every id the seed sends is one it created or proved.
- **No seeded identifier can match a real one.** Every sAMAccountName and external id starts with
  the prefix, every user principal name and distinguished name is in the lab domain, and every phone
  number is in the 555-0100 to 555-0199 range reserved for fiction, so a tool that joins on any of
  them finds the seed and nothing else.
- **No policy is made the default or attached to a group that holds anybody real.**
- **No API server lets an app outside the seed ask for its tokens,** and no seeded app is made a
  client of a server outside it.
- **No app rule sits on an app outside the seed or names a role outside it,** and its action is
  fixed: the groups claim, from `member_of`, which on a seeded person names seeded groups only.
- **The Smart Hook is always disabled and always gated on a seeded role**, and a re-run disables it
  again.
- **The self-registration profile is always disabled, moderated, open to the lab domain only and
  given no default role or group**, and a re-run puts that back.
- **No MFA factor is turned on for the account**, and a factor is enrolled on seeded people only and
  only as already verified, so nothing is sent anywhere.

## 🔐 Saved app secrets

`New-TestEnvironment -SaveAppSecret` keeps the client secrets of the two confidential apps it
creates - Expenses Web and Payroll Console - so a relying party can be pointed at them. The public
and native clients and the SAML app have no secret. Each is written through the same record writer
as the connection's own credential: DPAPI-protected in `~/.testenvironment/<subdomain>.onelogin-app.<id>.json`,
or in a SecretStore vault with `-UseSecretStore`.

```powershell
New-TestEnvironment -SaveAppSecret
Get-OneLoginAppCredential -Key expenses     # the client id and secret as a PSCredential
```

OneLogin shows a secret only in the answer to the create, so an app that already existed has none to
save; the seed names it and warns. `Remove-TestEnvironment` deletes each saved secret with its app,
and any saved secret whose app is no longer in the account, so they do not build up; `-WhatIf` lists
them and deletes nothing, and `-Keep Apps` leaves them alone. The report shows which apps have one.

The redirect URLs are under the lab email domain, so a test client has to be reachable there, or have
its own redirect URL added in the portal. The client credentials grant is not enabled on the seeded
apps, and a token request made with it is refused.

## 🧭 What OneLogin does without saying so

Each of these was found against a live trial, and the seed data and the provider are built around it.

| OneLogin behaviour | What the provider does |
|---|---|
| Approves a person only while a licence is free, and otherwise makes them Unlicensed - while the create answers as if it had approved them | Ten people are Approved; the users step reads them back and names anyone left unlicensed |
| Accepts a role grant for anyone, and keeps it only for an Approved person whose status is Active, Suspended, Locked, PasswordExpired or AwaitingPasswordReset | The data gives roles to those people only, and a test holds it to that |
| Keeps a Rejected person out of any group as well as any role | The rejected partner is in no group |
| Shows a role grant some seconds after answering it, once minutes, and sometimes never | The users step waits up to four minutes until every grant it sent is visible, sending again the ones that do not appear |
| Lists users without their custom fields, roles, manager or directory fields unless they are asked for by name | Every user listing names its fields |
| Runs an enabled mapping as each person is created | Mappings are created before people |
| Returns only enabled mappings and app rules unless asked for the disabled ones | Both are asked for |
| Lists Smart Hooks without their code, and groups without their administrators | Each is read in detail before it is proved |
| Undoes a Locked status sent on a create or update | The person is locked through the lock call instead |

## 🧪 Verification

`Test-TestEnvironment` reads the account through the same ownership proofs teardown uses and checks
every name by codepoint, every lifecycle status and state (a locked person locked for at least
another day), every manager, every directory identifier, every group placement, every policy on its
groups and every policy setting, every API scope, claim and client, every app rule, the hook, the
sign-up profile, and every role membership and app grant the data lists. Role memberships are judged
on what is missing only, because the enabled mapping adds a person the data never lists there. How
many people hold an MFA factor is counted and not judged, because the seed enrols one only where the
account offers it. `Repair-TestEnvironment` re-runs the steps that own any failed check.
`Compare-TestEnvironment` matches the seeded people against any other connected provider's.
