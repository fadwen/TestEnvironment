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
| Users | 311 |
| Service accounts | 25 |
| Devices | 688 |
| Security groups | 90 (5,685 memberships) |
| Password policies | 3 fine-grained policies over seeded groups, at three precedences |
| DNS zones / records | 2 zones the seed owns, a forward zone under the domain and a reverse zone for 10.214.0.0/16 / an A and a PTR for all 688 devices, and 8 records around them |

### What the newer data is shaped to show

**Every device resolves.** Each of the 688 carries a unique address in 10.214.0.0/16, and the
seed writes an A record and its PTR for each into zones of its own - `ZZ-TEST-lab.<domain>` and
`214.10.in-addr.arpa`. Nothing is written into the domain's own zone: an A record for a machine
that does not exist, sitting in production DNS, would have only its name to say it was ours,
which is the rule this provider refuses everywhere else. Both zones are Active Directory
integrated, so each is a directory object carrying `adminDescription = ZZ-TEST-seed`, and
teardown removes a zone only when it does. Around the device records sit the shapes a review has
to notice: an alias whose target has no computer, an address record with no computer behind it,
one name with two addresses, and a reverse record whose forward name is missing.

**Some service accounts hold a principal name, most do not.** Eight of the twenty-five register
an SPN against a seeded server - `MSSQLSvc` on the SQL host at two ports, `HTTP` on the reporting
and mail hosts, `CIFS` and `HOST` on the file server - and one registers its SPN on a DNS alias
rather than on the host it points at, which is the shape that breaks Kerberos the day the alias
moves. One account delegates, constrained, from the web tier to the SQL SPN. **Unconstrained
delegation is never seeded and there is no switch that asks for it**: it is a live weakness
rather than inert test data, and a review should find the constrained one and nothing worse.

**Three fine-grained password policies, at three precedences.** The strictest sits at the lowest
number, so it wins for anyone who is also in a weaker group. One applies to a privileged group
and never expires a password and never locks the account out. One has complexity off and
reversible encryption on, the two settings a review should never find enabled. They live in the
Password Settings Container rather than under `OU=TestData`, so a recursive delete of the tree
cannot reach them, and like everything else they are claimed at teardown by the tag rather than
by their names.

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
