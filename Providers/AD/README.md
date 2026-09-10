# The Active Directory provider

Part of [TestEnvironment](../../README.md).

Seeds a domain: volume, held in one container, with ownership proved before anything is deleted.
`OU=TestData` is the container.

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

### The commands carry a `Test` infix

`New-ADUser`, `New-ADGroup`, `New-ADComputer` and `Get-ADDomain` are real cmdlets from the module
this provider imports, and a function of the same name would be found ahead of the cmdlet by
everything else in the session. So the components are `New-ADTestUser`, `New-ADTestGroupPolicy`
and so on, and a contract test enforces that no function shadows a cmdlet.

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

The manifest does not declare `ActiveDirectory` or `GroupPolicy`, so the module still imports on
a host without RSAT. The provider imports them at the moment they are genuinely needed, and their
absence is reported as a sentence rather than a binding error.

The unit tests run without RSAT at all, against the stubs in `Tests/Stubs`.
