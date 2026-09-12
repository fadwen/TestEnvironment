# The FreeIPA provider

Part of [TestEnvironment](../../README.md).

Built against a FreeIPA realm you run yourself, with no user cap to design around. FreeIPA is a
POSIX directory with Kerberos, so the things it manages are the things a fleet of Linux hosts
asks it about: who may log in where (HBAC), who may run what (sudo), which UID a person has on a
given machine (ID views), which NFS export mounts at `/home` (automount), and who administers
all of that (roles, privileges and permissions). The seed covers every one of those.

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

| | Count |
|---|---|
| Users | 333 = 12 core + 321 bulk, in every state FreeIPA has: active, disabled with every membership intact, staged and invisible to `user-find`, and preserved with every membership stripped. Three accented names, a contractor whose principal expired while the account stayed enabled, a user whose authentication type demands a token nobody enrolled, a user with no private group, a service account with no shell, two public keys on one user and certificate mapping data on another; the bulk carries titles, org units, employee numbers, phone and address, manager chains, 33 contractors and 25 service accounts |
| Groups | 102 = 12 core + 90 bulk. POSIX, non-POSIX and one external; the core nests three deep with a non-POSIX team inside a POSIX department; the bulk carries real nesting, some groups with more than one parent |
| Host groups | 30 = 8 core + 22 bulk, nested two deep, with one host a direct member of the root. FreeIPA creates a managed netgroup for each |
| Hosts | 413 = 8 core + 405 bulk, every one a record with no keytab, in the seed's own DNS zone with an address in the seed's subnet, except the one with nothing at all. The core carries an authentication indicator, a managed-by relationship, a host key and one host with nothing at all; the bulk carries operating system, hardware, office and MAC address |
| Netgroups | 4: one from a group and two host groups, one from direct members, one nested, one empty |
| HBAC services / rules | 3 custom services and 3 service groups, one mixing the stock `sshd` and `login` with a seeded service / 7 rules, one an allow-everything rule that is switched off, one bound to nothing, one still naming a disabled user |
| Sudo commands / rules | 8 commands and 4 command groups / 7 rules, one disabled, one empty, one that grants `vim` to contractors without a password, one that runs as a local account that is not an IPA user |
| Permissions / privileges / roles | 3 / 3 / 4; the write permission is scoped to the seed tag, a host holds a role, one role mixes a seeded privilege with a stock read-only one, and one role is held by nobody |
| Password policies | 3, on seeded groups only; one never expires a password and never locks out |
| Services | 4 Kerberos service principals on seeded hosts, none with a keytab; one custom type, one managed by another host, one with an authentication indicator |
| Service delegation | 1 rule and 2 targets, one of them empty |
| ID views / overrides | 2 / 4: a view applied to the legacy host that renames a user and a group and changes another user's shell alone, and a view applied nowhere |
| OTP tokens | 4: a TOTP that satisfies one user's OTP-only authentication type, an HOTP with vendor and model, a disabled one on the disabled account, and one that expired yesterday |
| Automember rules | 5, each agreeing with the memberships the data already lists, and one that can never match; the seeded users and hosts are rebuilt against them by name |
| Automount | 1 location, 2 indirect maps, 3 keys including a wildcard and a direct mount, every one pointing at the seeded NFS host |
| SELinux user maps | 3, one scoped by an HBAC rule, one by members, one disabled |
| Certificate mapping rules | 3: one matched by a seeded user's certificate data, one that maps the realm CA's own certificates back to their users, one disabled |
| DNS zones / records | 2 zones the seed owns, a forward zone under the realm's domain and a reverse zone for 10.213.0.0/16, each proved by its SOA contact / an A and a PTR for every addressed host, written by FreeIPA, and 11 records around them: aliases, a mail exchanger, a service record, a name with two addresses, an address with no host, an alias with no target, and a reverse record with no forward name |
| CA ACLs | 4: the rule the user certificates need, a paused pilot that is disabled, a scoped rule beside the stock one, and one granted to nobody |
| Certificates | 10 issued by the realm's own CA: six user, three service, one host; one revoked for key compromise beside its replacement, one on hold, one service one revoked as ceased, and a valid one on the disabled account |

⏱️ Seed: ~14 minutes. Teardown: ~7 minutes. Report: ~20 seconds.

### What the DNS is shaped to show

The seed never writes into the realm's zone. Its hosts live in a zone of their own,
`zz-test-lab.<domain>`, with a reverse zone for a private /16 nothing real should be using, and
both zones carry the seed's SOA contact, `hostmaster.zz-test-lab.<domain>.`, as the proof they are
the seed's. A zone of the seed's name with any other contact is refused, never adopted. Every
addressed host resolves both ways, so a review can reconcile the host list against DNS; the
records the data adds are the things that do not reconcile - an address with no host behind it,
an alias whose target does not exist, a reverse record with no forward name, one name with two
addresses - beside the ordinary aliases, mail exchanger and service record. A realm installed
without DNS gets a warning and hosts without addresses, as before.

### What the certificates are shaped to show

Every certificate is real, issued by the realm's CA against a request the module builds with a
throwaway key, and each is added to the entry it was issued to. So a user carries one in
`userCertificate`, the realm-CA mapping rule maps it back to them, and `ipa certmap-match`
answers with the right login; a service or host carries one with its name in the subject
alternative name; and the CA lists each with its serial, validity and status. The states are
the ones a review has to tell apart: a valid certificate on a disabled account, a revoked one
beside its replacement on the same user, one on certificate hold, and a service certificate
revoked as ceased while the service lives on. Only the seeded CA ACL lets the user
certificates be issued; the paused pilot rule is disabled and grants nothing.

A CA never forgets. Teardown revokes every seeded certificate that is still valid, and deleting
the entries revokes them too, but the serials stay in the CA's records as revoked. A realm that
has been seeded and torn down carries that history, the way any CA carries its own.

### What the identity detail is shaped to show

- **What a host sees.** An ID view gives the legacy host a different login, UID, shell and home
  for one user, a different shell alone for a second, and a different name and GID for a group.
  A second view holds an override and applies to nothing, so a report that lists overrides
  without asking where a view is applied counts one that never takes effect.
- **Second factors.** Two users demand a token by authentication type; one has a live one,
  the other has none and cannot log in. A disabled token sits on the disabled account, and an
  enabled eight-digit token expired yesterday. The realm mints the secrets and the seed never
  reads them back.
- **Rules that explain the directory.** The automember rules agree with every membership the
  data already lists, and the seeded users and hosts are rebuilt against them by name after
  they are created, which changes nothing and proves it. One rule's only condition excludes
  everyone.
- **Mounts and contexts.** An automount location whose keys all point at the seeded NFS host
  under the realm's own domain, including the direct map FreeIPA made with the location; SELinux
  maps that follow an HBAC rule or name their own members; and a certificate mapping that the
  one seeded user with certificate data satisfies, beside one the issued certificates satisfy.

### What the access layers are shaped to show

- **Access that does not add up.** One user is admitted to payroll twice, by name and through her
  group. A disabled user is still named in an HBAC rule and a sudo rule. An allow-everything HBAC
  rule exists and is off. A sudo rule grants an editor that escapes to a shell, to contractors,
  with no password. A rule of each kind is bound to nothing. Each is the finding the
  corresponding review exists to surface, and `ipa hbactest` and `ipa sudorule-show` answer
  for them the way a real realm would.
- **Reach.** A sudo rule with a host category of all and one command; a rule with a user
  category of all, an allow and a deny; a run-as of root without a password through a
  non-POSIX group three levels down the chain; a run-as of a local account FreeIPA can only
  store as external.
- **Delegation.** Roles reach privileges reach permissions, and the one permission that writes
  is scoped by the seed tag. A host holds a role, which FreeIPA allows and most reports forget. A
  seeded role carries a stock read-only privilege, which teardown leaves behind. One role has a
  privilege and no holder.
- **Policy.** Three password policies at three priorities; the lowest number wins for a user in
  more than one group, and the weakest never expires a password at all. They are created after
  the users, so the passwords the users step set were judged by the global policy alone.
- **Principals.** Services on seeded hosts with no keytab, one a custom type, one manageable
  from another host, one that only issues tickets with a second-factor indicator, and
  constrained delegation from the web service to the legacy LDAP service.

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
- **Authentication state.** Two users whose authentication type is OTP, one with a token and
  one without; a contractor whose Kerberos principal expired two weeks ago while the account
  stayed enabled; a host whose tickets need a second factor.
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

Sudo commands are named by their path and cannot be prefixed at all, so ownership of those rests
on the marker in the description, and a command that already exists without it is reused as it is
and left behind at teardown. A password policy is keyed by its group and is ours because the
group is; a service belongs to its host; permissions and delegation rules and targets have no
description and carry the prefix alone.

Nothing the seed does ever touches a rule the realm shipped with. `allow_all`,
`allow_systemd-user`, `global_policy`, the stock privileges, the `ipa-http-delegation` rule, the
Default Trust View, the default automount location and the automember default groups are never
created, modified, enabled or disabled, there is no switch to make them so, and the tests pin
that no request reaches one. A stock PAM service or a stock privilege may be a member of a seeded
rule, group or role, which changes nothing about it. An automember rebuild is always scoped to
the seeded users and hosts by name; a rebuild of the whole realm is never issued.

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
