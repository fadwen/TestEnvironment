# Active Directory provider initialisation.
#
# Module-scope constants the provider's functions read. Dot-sourced by the root module after the
# provider's Private and Public folders.

# The container every seeded object lives in, prefixed like everything else this module creates.
# Sixty-nine places build a distinguished name from it, so it is a variable rather than a literal
# repeated in each of them - and Connect-ADEnvironment overwrites it when given a -Prefix, which
# is what keeps the tree, the groups and the computers all carrying the same identifier.
$script:ADTestRootName = '{0}TestData' -f $script:TestEnvironmentDefaultPrefix

# The private range the seed's own DNS zones cover. The FreeIPA provider uses 10.213 for the
# same purpose and the two are kept apart, so a hybrid estate can seed both without one
# provider's reverse zone answering for the other's addresses. See Get-ADTestSeedZone.
$script:ADTestSeedSubnet = '10.214'
