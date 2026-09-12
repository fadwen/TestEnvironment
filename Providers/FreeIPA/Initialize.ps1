# Module-scope constants for the FreeIPA provider. Dot-sourced after Private/ and Public/, and
# read by the functions there; a contract test proves every $script: variable a provider reads
# is assigned somewhere, because the Okta provider once lost its seed domain in a move and the
# -replace that used it matched an empty pattern rather than failing.

# The domain the seed's host references are written against: the automount keys that point at
# the NFS host and the certificate mapping rule that matches on an email domain. Substituted
# at creation time - for the seed's forward zone where it names a host, for the connected
# realm's domain where it names an email address - so one CSV serves any realm.
$script:FreeIPADefaultSeedDomain = 'ipalab.example.com'

# The seed's own DNS. The forward zone is '<prefix>lab.<realm domain>' and every seeded host
# lives in it, so nothing is ever written into the realm's zone; the reverse zone covers a /16
# of private space nothing real should be using. Both are proved by their SOA contact, which
# is derived from the forward zone's name. See Get-FreeIPASeedZone.
$script:FreeIPASeedZoneLabel = 'lab'
$script:FreeIPASeedSubnet = '10.213'

# The sections of Get-FreeIPAEnvironmentReport, in the order they are rendered and the order
# the CSV files are written. One list, so the console, CSV and HTML formats cannot drift.
$script:FreeIPAReportSections = @(
    'Users', 'Groups', 'Hostgroups', 'Hosts', 'Netgroups', 'HbacRules', 'SudoRules', 'Roles', 'PasswordPolicies',
    'Services', 'ServiceDelegation', 'IdViews', 'IdOverrides', 'OtpTokens', 'AutomemberRules', 'Automount', 'SelinuxUserMaps',
    'CertMapRules', 'CaAcls', 'Certificates', 'DnsZones', 'DnsRecords'
)
