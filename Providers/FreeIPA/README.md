# The FreeIPA provider

Part of [TestEnvironment](../../README.md).

Built against a FreeIPA realm you run yourself, with no user cap to design around. FreeIPA is a
POSIX directory with Kerberos, so the things it manages are the things a fleet of Linux hosts
asks it about: who may log in where (HBAC), who may run what (sudo), which UID a person has on a
given machine (ID views), which NFS export mounts at `/home` (automount), and who administers
all of that (roles, privileges and permissions). The seed covers every one of those.

**What is here today is the seed data and the tool that generates it.** Connecting, seeding,
reporting and teardown follow; until they land, `Connect-TestEnvironment -Provider FreeIPA`
reports that the provider does not implement its connect command.

| | Count |
|---|---|
| Users | 333 = 12 core + 321 bulk. The core is active, disabled, staged and preserved, three accented names, a contractor whose principal expired but whose account was never disabled, a user whose authentication type demands a token nobody enrolled, and a user with no private group; the bulk carries titles, org units, employee numbers, phone and address, manager chains, 33 contractors and 25 service accounts with no shell |
| Groups | 102 = 12 core + 90 bulk. POSIX, non-POSIX and one external; the core nests three deep with a non-POSIX team inside a POSIX department; the bulk carries real nesting, some groups with more than one parent |
| Hosts | 413 = 8 core + 405 bulk, every one a record with no keytab. The core carries an authentication indicator, a managed-by relationship, a host key and one host with nothing at all; the bulk carries operating system, hardware, office and MAC address |
| Host groups | 30 = 8 core + 22 bulk, nested two deep, with one host a direct member of the root |
| Netgroups | 4: one from a group and two host groups, one from direct members, one nested, one empty |
| HBAC services / rules | 3 custom services and 3 service groups / 7 rules, one an allow-everything rule that is switched off, one bound to nothing, one still naming a disabled user |
| Sudo commands / rules | 8 commands and 4 command groups / 7 rules, one disabled, one empty, one that grants `vim` without a password |
| Permissions / privileges / roles | 3 / 3 / 4; the write permission is scoped to the seed tag, a host holds a role, and one role is held by nobody |
| Password policies | 3, on seeded groups only; one never expires a password and never locks out |
| Services | 4 Kerberos service principals on seeded hosts; one custom type, one with an authentication indicator |
| ID views / overrides | 2 / 4: a view applied to the legacy host that renames a user and a group, and a view applied nowhere |
| OTP tokens | 4: a TOTP, an HOTP with vendor and model, a disabled one on the disabled account, and one that expired yesterday |
| Automember rules | 5, each agreeing with the membership the data already lists, and one that can never match |
| Automount | 1 location, 2 indirect maps, 3 keys including a wildcard and a direct mount |
| SELinux user maps | 3, one scoped by an HBAC rule, one by members, one disabled |
| Certificate mapping rules | 2, one enabled and matched by a seeded user's certificate data, one disabled |
| Service delegation | 1 rule and 2 targets, one of them empty |

### What the data is shaped to show

- **Lifecycle.** FreeIPA has four states an account can be in and the seed has one of each:
  active, disabled with every membership intact, staged and therefore invisible to `user-find`,
  and preserved after deletion with every membership stripped. A report that reads only the
  active tree misses two of them.
- **Access that does not add up.** One user is admitted to payroll twice, by name and through her
  group. A disabled user is still named in an HBAC rule and a sudo rule. An allow-everything
  HBAC rule exists and is off. A sudo rule grants an editor that escapes to a shell, to
  contractors, with no password. Each is the finding the corresponding review exists to surface.
- **Authentication state.** A user whose authentication type is OTP and who holds a token; a
  user with the same type and no token, who therefore cannot log in; a token that expired
  yesterday; a host and a service that only issue tickets carrying a second-factor indicator; a
  contractor whose Kerberos principal expired two weeks ago while the account stayed enabled.
- **POSIX detail.** A non-POSIX group nested in a POSIX one, so membership resolves and no GID
  does. An external group that can hold only trusted-domain SIDs, wrapped in the POSIX group a
  trust would grant a GID through. A user with no private group whose primary GID is a shared
  group. A user with a shell and a home that are not the defaults, and two public keys.
- **Views.** An ID view that gives one user a different login, UID, shell and home on the legacy
  host, gives a second only a different shell, and renames a group; and a view holding an
  override that is applied to no host, so it never takes effect.
- **Administration.** Roles reach privileges reach permissions, and the one permission that
  writes is scoped by the seed tag. A host holds a role, which FreeIPA allows and most reports
  forget. One role has a privilege and no holder.
- **Records that are not machines.** Every seeded host is an entry with no keytab. An inventory
  has to tell an enrolled machine from a record of one, and one record has no description, no
  operating system, no group and no rule.

### Two tiers

The users, groups, hosts and host groups have two halves. `Core` is the hand-designed rows,
chosen to be awkward in ways that break scripts. `Bulk` is the volume: the AD provider's people,
service accounts, groups and devices mapped across, so the same person and the same machine
exist in this lab as in the others. Phones and printers do not enrol in an identity domain and
stay behind; workstations and servers cross, each joining a host group for its kind and one for
its office.

`Tools\New-FreeIPATestSeedData.ps1` regenerates the four generated files. It is deterministic,
so a rebuild produces byte-identical output and a diff shows real changes rather than churn, and
a test regenerates the files and fails if the committed copies have drifted. The other eighteen
seed files are written by hand.

### Names, the prefix and the tag

FreeIPA lower-cases a login and requires a group, host group or netgroup name to match
`[a-zA-Z0-9_.][a-zA-Z0-9_.-]*`, so the prefix is applied in its lower-case form, `zz-test-`, and
the seed files hold bare keys: `all-staff` becomes `zz-test-all-staff`, `web01` becomes
`zz-test-web01.<domain>`. Human logins carry no prefix; the tag in `userclass` is what marks them.
Sudo commands are named by their path and cannot be prefixed at all, so ownership of those rests
on the tag in the description, and a command that already exists without it is reused and left
behind at teardown.

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
