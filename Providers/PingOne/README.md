# The PingOne provider

Part of [TestEnvironment](../../README.md).

Seeds the directory and application objects of **PingOne SSO** in one PingOne environment, reports
on them, and removes them again, proving ownership of each object before deleting it. It works
through the PingOne platform management API, authenticated as a worker application.

## ✅ What it creates, reports and removes

| Object | Count | Detail |
|---|---|---|
| Custom user attributes | 5 | STRING and JSON; one unique, one multivalued; one carries the seed tag |
| Populations | 4 | One deliberately empty; none is ever the environment's default |
| Users | 330 | 19 hand-designed + 311 generated; name, email, title, enabled state, MFA-enabled flag and the custom attributes above |
| Group memberships | 464 | Users added to static groups |
| Groups | 11 | Static, nested three deep, dynamic by filter, and population-scoped |
| Resources | 2 | Custom APIs, each with an audience and token lifetime |
| Resource scopes | 4 | Created on those resources |
| Applications | 6 | OIDC web, single-page and native clients, and SAML; one disabled |
| Application access | 5 | Applications restricted to seeded groups |
| Scope grants | 3 | Applications granted scopes on the seeded resources |

Every object in that table carries the seed prefix on its name and the seed tag, and nothing else in
the environment is created, changed or removed.

## ⛔ What it does not touch

Nothing outside the table above. In particular, the provider creates, edits and deletes none of:

- sign-on policies, password policies, identity providers or agreements;
- MFA device authentication policies, FIDO2 policies, Verify policies, risk predictors or flow
  policies;
- administrator role assignments, custom roles, certificates, keys or custom domains;
- notification settings and templates, themes, forms or branding;
- gateways, provisioning, or webhook subscriptions;
- the environment itself, or which population is its default;
- PingOne's own applications (admin console, application portal, self-service) or built-in
  resources (PingOne API, openid);
- any user, group, population or application it did not create, including a trial's sample data;
- the worker application it authenticates as, or that application's roles.

Two user states are not seeded because the management API cannot set them: `verifyStatus` is
`NOT_INITIATED` on every user it creates, and an account lock is a separate operation rather than a
field on the user.

## 📋 What it needs

- **A worker application** in the PingOne console: Applications, add, **Worker**, enabled.
- **Roles on the environment being seeded**, granted to that worker: **Identity Data Admin**,
  **Environment Admin** and **Client Application Developer**.
- **Windows PowerShell 5.1 or PowerShell 7**, and nothing else installed.

Verified against a North America trial sandbox environment, from both PowerShell editions. `-Region`
also accepts Europe, Canada, AsiaPacific and Australia, which have not been exercised.

```powershell
# -AuthEnvironmentId is the environment the worker LIVES in, which on a trial is usually
# Administrators rather than the sandbox being seeded.
$secret = Read-Host 'Worker secret' -AsSecureString
Connect-TestEnvironment -Provider PingOne -EnvironmentId <sandbox guid> `
    -ClientId <worker guid> -ClientSecret $secret `
    -AuthEnvironmentId <administrators guid> -SaveSecret

New-TestEnvironment -WhatIf          # list what it would create, creating nothing
New-TestEnvironment -ShowProgress    # create it
Get-TestEnvironmentReport            # report what it created
Remove-TestEnvironment -Force        # remove it all
```

## ⏱️ Seed: ~4 minutes. Teardown: ~1 minute. Report: ~10 seconds.

Measured for the full 330 users. `New-TestEnvironment -Tier Core` seeds every object type with only
the 19 hand-designed users, in about 25 seconds.

## 🔑 Connecting

**The token comes from the environment the worker lives in, not the one it manages.** A trial
opens the application list on the Administrators environment, so that is where most workers end
up. Asking the sandbox's token endpoint for a token with that worker is refused with
`invalid_client` — the same message a disabled application and a mistyped secret produce. Pass the
worker's home as `-AuthEnvironmentId`; it defaults to `-EnvironmentId`, which is right only when the
two are the same.

**The region is not derivable from an environment id.** Asking the wrong regional host returns a
404 that looks like a missing environment. `-Region` defaults to `NorthAmerica`; the console's own
hostname is the reliable way to tell.

`-SaveSecret` writes the secret to `~/.testenvironment/<environment>.pingone.secret` once the
connection has been proved, and `-UseStoredSecret` reads it back on later runs.

## 🛡️ Ownership

Nothing is deleted for matching a name.

**A population is the container teardown asks.** Every seeded user is in exactly one seeded
population, so teardown enumerates those populations and removes what is in them rather than
searching by name.

**A PingOne user has no description field**, so the seed tag cannot go on the user object itself.
A user carries account, address, email, enabled, identityProvider, lifecycle, mfaEnabled, name,
population, username and verifyStatus, and none of them is free text this provider could claim. The
seed therefore creates a custom attribute, `zzTestSeedTag`, and writes the tag into it on every user.
That still proves ownership of a seeded user moved out of a seeded population by hand.

For populations, groups, resources and applications, ownership needs **both** the tag in the
description **and** the prefix on the name. The tag alone could be pasted into a real object by
accident, and the prefix alone would be matching by name. PingOne's own applications and built-in
resources are refused by type whatever they say, so renaming one in the console cannot put it in
teardown's reach.

Custom attributes are claimed only when they are CUSTOM and named in this provider's data file.

## 🚫 What it never does, and has no parameter for

- **No seeded population is ever made the environment's default.** The default decides where
  every user created without a population lands.
- **No public client is created without PKCE.** A single-page or native application with no secret
  is created with S256 PKCE required.
- **No platform application or built-in resource is created, edited or deleted.**

Tests under `Tests/Unit/Providers/PingOne` assert each of these, so adding a `-Default` or a
`-DisablePkce` switch as a convenience is caught as the regression it would be.

## 🗑️ Teardown

Removes everything in the reverse of the seed order, each position forced by what PingOne will
delete: applications, resources, users, groups, populations, and custom attributes last, because
PingOne refuses to delete an attribute while any user still holds a value in it. Scopes, grants,
group access and memberships go with the objects they belong to.

The confirmation is asked once, in the body of the command, where a refusal genuinely stops it.
A session that cannot answer the prompt is treated as a refusal, so **an unattended teardown has
to pass `-Force`**. `-WhatIf` always wins: `-Force -WhatIf` removes nothing and prints a line for
every object it would have.

`-Keep Users` refuses to remove populations and attributes as well, since PingOne only deletes an
empty population and an unreferenced attribute. Running teardown again on an already-clean
environment removes nothing and reports no error.

## 📊 Test data inventory

### Users (330 = 19 core + 311 bulk)

Seeded users carry their real given and family names; only their usernames and emails take the
prefix. Emails are under `pingonelab.example.com` by default, a reserved domain that cannot receive
mail. The 311 bulk users are generated directory volume with titles, departments and population
placement.

The 19 core users carry:

- **A disabled user who still holds every group membership**, which membership reports routinely
  count as active.
- **The MFA-enabled flag off** where most of the directory has it on. The flag is set; no MFA device
  or policy is created.
- **A contractor flag stored as text.** PingOne refuses a custom attribute of any type but STRING
  or JSON, so the boolean is `"true"` or `"false"` — and the string `"false"` is not falsy in
  PowerShell, so anything casting it reads every contractor as one.
- **A unique badge attribute that PingOne really enforces**: a second user with the same value is
  refused with `INVALID_DATA`.
- **Writing systems beyond Latin** — Han with an ideographic space, a surname above the basic plane,
  Cyrillic, Greek, Arabic, Devanagari, a decomposed name, a Turkish dotless i and an eszett. Every
  username stays plain ASCII.

### Populations (4)

| Population | Why this one |
|---|---|
| Staff | Holds most users, and is the population the dynamic group filters on |
| Contractors | A second population, so anything that assumes one is wrong |
| Partners | A third population, and the one the population-scoped group is bound to |
| Offboarding Hold | Deliberately empty |

### Groups (11)

| Group | Kind | Why this one |
|---|---|---|
| All Staff → Engineering → Team Platform | Static, nested | Three deep, so membership has to resolve transitively |
| Sales | Static | A department holding a disabled user |
| Finance | Static | One member, and the only group the payroll application admits |
| Leadership | Static | Outside the chain, with a single member |
| Contractors | Static | Holds the contractors population, but the contractor attribute disagrees: 12 members are flagged false, and one partner flagged true is outside it |
| Partners | Population-scoped | A user outside the population cannot be added to it |
| Dynamic Staff | Dynamic | PingOne maintains it from a filter and it cannot be edited by hand |
| Dynamic Nobody | Dynamic | A valid filter matching nobody, which looks identical to a broken one |
| Offboarding Hold | Static | Deliberately empty |

**A dynamic group reports zero members immediately after a seed.** PingOne evaluates filters
asynchronously, so that is the state the row exists to capture rather than a failure.

**`memberOfGroups` on a group is transitive.** Team Platform, nested only in Engineering, reports
both Engineering and All Staff as parents.

### Resources (2)

| Resource | Scopes | Token lifetime |
|---|---|---|
| Orders API | orders.read, orders.write, orders.admin | 1 hour |
| Reports API | reports.read | 15 minutes |

### Applications (6)

| Application | Shape | Access and grants |
|---|---|---|
| Expenses Web | OIDC web, client secret | All Staff; orders.read |
| Payroll Console | OIDC web, client secret | Finance; reports.read |
| Partner Portal SPA | Single-page, no secret, PKCE required | Partners; orders.read |
| Field App | Native, custom-scheme redirect, refresh token | Sales |
| Wiki SAML | SAML | All Staff; no scopes, as it is issued no access tokens |
| Legacy Console | OIDC web, disabled | No group, no scopes |

Redirect and ACS URLs are written under the connection's email domain.

## 🧪 Found while building it

Recorded because each one looked like something else first.

- **A worker's token endpoint is its home environment's**, and the wrong one answers
  `invalid_client`, not "wrong environment".
- **PingOne refuses a BOOLEAN custom attribute** with `INVALID_DATA on type: must be STRING or
  JSON`, which is why the contractor flag is text.
- **A filter naming an attribute that is not in the schema** is refused with HTTP 400
  `REQUEST_FAILED`. The attribute is absent before the first seed and again after teardown removes
  it, so ownership discovery asks the schema before filtering by it; filtering blindly made a report
  on a fresh environment, and a second teardown, throw.
- **An ignored error returns `$null`, and `@($null)` is a one-element array.** Unguarded, that would
  have handed teardown a user with no id and a `DELETE users/` with nothing after the slash.
- **Windows PowerShell 5.1 corrupted every accented name** when the request body was sent as a
  string: a plain `é` was stored as U+FFFD, and a combining accent, a Han character and an astral
  pair as `?`. Bodies are now sent as UTF-8 bytes and responses decoded from raw bytes, and a seed
  from either edition stores every name byte for byte.
