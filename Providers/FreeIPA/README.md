# The FreeIPA provider

Part of [TestEnvironment](../../README.md).

Built against a FreeIPA realm you run yourself, with no user cap to design around. FreeIPA is a
POSIX directory with Kerberos, so the things it manages are the things a fleet of Linux hosts
asks it about: who may log in where (HBAC), who may run what (sudo), which UID a person has on a
given machine (ID views), which NFS export mounts at `/home` (automount), and who administers
all of that (roles, privileges and permissions). The seed data covers every one of those; the
commands so far seed the directory layer beneath them, and the access layers follow.

```powershell
# First run: trade an administrator's credential for a service account that can act on its own.
# The realm's CA is at /etc/ipa/ca.crt on any enrolled host.
Connect-TestEnvironment -Provider FreeIPA -BaseUrl https://ipa.example.com -Credential (Get-Credential admin) -CertificateAuthorityPath .\ca.crt
New-TestServiceApp

# Every run afterwards
Connect-TestEnvironment -Provider FreeIPA -BaseUrl https://ipa.example.com -ServiceAccount
New-TestEnvironment
Get-TestEnvironmentReport
Remove-TestEnvironment -WhatIf
```

⏱️ Seed: ~11 minutes. Teardown: ~6 minutes. Report: ~5 seconds.

| | Count |
|---|---|
| Users | 333 = 12 core + 321 bulk, in every state FreeIPA has: active, disabled with every membership intact, staged and invisible to `user-find`, and preserved with every membership stripped. Three accented names, a contractor whose principal expired while the account stayed enabled, a user whose authentication type demands a token nobody enrolled, a user with no private group, a service account with no shell, two public keys on one user and certificate mapping data on another; the bulk carries titles, org units, employee numbers, phone and address, manager chains, 33 contractors and 25 service accounts |
| Groups | 102 = 12 core + 90 bulk. POSIX, non-POSIX and one external; the core nests three deep with a non-POSIX team inside a POSIX department; the bulk carries real nesting, some groups with more than one parent |
| Host groups | 30 = 8 core + 22 bulk, nested two deep, with one host a direct member of the root. FreeIPA creates a managed netgroup for each |
| Hosts | 413 = 8 core + 405 bulk, every one a record with no keytab. The core carries an authentication indicator, a managed-by relationship, a host key and one host with nothing at all; the bulk carries operating system, hardware, office and MAC address |

The seed data also holds netgroups, HBAC services and rules, sudo commands and rules,
permissions, privileges and roles, password policies, service principals, ID views and overrides,
OTP tokens, automember rules, an automount location, SELinux user maps, certificate mapping rules
and service delegation, about sixty objects designed around the directory above. Those steps are
next.

### How it connects

FreeIPA's API is JSON-RPC behind a session cookie that a password login sets. The bootstrap
credential is any administrator; `New-TestServiceApp` then creates `zz-test-automation`, a user
with no shell in the admins group, and writes the record `Connect-TestEnvironment -ServiceAccount`
reads from `~/.testenvironment/`. The password in it is DPAPI-protected on Windows, or goes to the
SecretStore with `-UseSecretStore`.

Two things FreeIPA does to passwords are handled rather than left to surprise. Every password an
administrator sets is expired the moment it is set, so the bootstrap changes the service account's
password as the user immediately, and a fresh administrator credential that has never logged in
needs `-NewPassword` on the connect to do the same. And the realm's password policy expires the
service account's password on its own schedule, so the bootstrap pushes its expiry ten years out,
and a connect that meets an expired one anyway rotates it and rewrites the record with a warning.

A FreeIPA server presents a certificate from the realm's own CA. Pass that CA's PEM with
`-CertificateAuthorityPath` and the connection trusts exactly it and nothing else, without
installing anything on the machine; the bootstrap writes it into the record so the service account
connect needs no path. Without either, the operating system's trust store decides.

### What the seeded directory is shaped to show

- **Lifecycle.** FreeIPA has four states an account can be in and the seed has one of each. A
  report that reads only `user-find` misses two of them.
- **Passwords as FreeIPA sees them.** With `-AccountPassword`, a user whose row says `MustChange`
  has the password an administrator set, which FreeIPA marks expired on the spot; a user whose row
  says `Current` had a temporary one changed as the user, which is the only way to a password that
  is not. The strictest seeded policy will apply to some of them, so the password should be twenty
  characters of four classes.
- **Authentication state.** A user whose authentication type is OTP and, until the token step
  lands, no token to satisfy it; a contractor whose Kerberos principal expired two weeks ago while
  the account stayed enabled; a host whose tickets need a second factor.
- **POSIX detail.** A non-POSIX group nested in a POSIX one, so membership resolves and no GID
  does. An external group that can hold only trusted-domain SIDs, wrapped in the POSIX group a
  trust would grant a GID through. A user with no private group whose primary GID is a shared
  group. A user with a shell and a home that are not the defaults, and two public keys.
- **Records that are not machines.** Every seeded host is added with force, so the realm's DNS is
  never consulted or written, and none ever enrols. An inventory has to tell a machine from a
  record, and `has_keytab` is how; one record has no description, no operating system, no group
  and no rule.

### Two tiers

The users, groups, hosts and host groups have two halves. `Core` is the hand-designed rows,
chosen to be awkward in ways that break scripts. `Bulk` is the volume: the AD provider's people,
service accounts, groups and devices mapped across, so the same person and the same machine
exist in this lab as in the others. Phones and printers do not enrol in an identity domain and
stay behind; workstations and servers cross, each joining a host group for its kind and one for
its office. `-Tier Core` on any seed command builds the designed rows alone, in seconds.

`Tools\New-FreeIPATestSeedData.ps1` regenerates the four generated files. It is deterministic,
so a rebuild produces byte-identical output and a diff shows real changes rather than churn, and
a test regenerates the files and fails if the committed copies have drifted. The other eighteen
seed files are written by hand.

### Names, the prefix and the tag

FreeIPA lower-cases a login and requires a group, host group or netgroup name to match
`[a-zA-Z0-9_.][a-zA-Z0-9_.-]*`, so the prefix is applied in its lower-case form, `zz-test-`, and
the seed files hold bare keys: `all-staff` becomes `zz-test-all-staff`, `web01` becomes
`zz-test-web01.<domain>` under the domain the realm reports at connect time. Human logins carry no
prefix; the tag in `userclass` is what marks them, beside the class their row names, and
`user-find --class` and `host-find --class` filter on it server-side. Groups and host groups carry
the tag as a bracketed marker at the end of their description. Teardown deletes only what carries
that evidence, and asks for staged and preserved users separately because `user-find` lists
neither.

Sudo commands are named by their path and cannot be prefixed at all, so ownership of those will
rest on the tag in the description, and a command that already exists without it is reused and
left behind at teardown.

The seed files never hold the prefix or the tag as a literal. Where one is needed inside a value,
an automount key pointing at the seeded NFS host or a permission filter, it is written as
`{prefix}` or `{tag}` and substituted at creation time. Host names that appear inside values are
written against `ipalab.example.com`, held in `Initialize.ps1`, and substituted for the
connected realm's domain.

A row may reference an object FreeIPA created at install only through a `builtin:` marker, and
only where attaching to it changes nothing about it: the stock PAM service names in an HBAC rule
or service group, and one read-only privilege in a role. The seed data tests list exactly which
names are allowed and refuse every other reference to a stock object, because a row that named
`admins`, `allow_all` or `global_policy` would have the seed write to it.

### Deliberately absent

- **Subordinate ID ranges.** FreeIPA can generate one per user, and by design it can never
  delete one. Seeding them would leave the realm changed after teardown.
- **Vaults.** They need a KRA, which a realm may not have installed.
- **DNS records.** A host is added with `--force` so the realm's DNS is never written to.
- **Trust members.** The external group exists, and holds nothing, because its members are SIDs
  from a trusted domain the lab does not have.
- **Enrolment.** No seeded host ever has a keytab. The seed makes records, not machines.
