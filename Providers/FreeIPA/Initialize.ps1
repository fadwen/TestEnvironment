# Module-scope constants for the FreeIPA provider. Dot-sourced after Private/ and Public/, and
# read by the functions there; a contract test proves every $script: variable a provider reads
# is assigned somewhere, because the Okta provider once lost its seed domain in a move and the
# -replace that used it matched an empty pattern rather than failing.

# The domain the seed's host references are written against: the automount keys that point at
# the NFS host and the certificate mapping rule that matches on an email domain. Substituted
# for the connected instance's domain at creation time, so one CSV serves any realm.
$script:FreeIPADefaultSeedDomain = 'ipalab.example.com'
