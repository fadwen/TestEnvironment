# Active Directory provider initialisation.
#
# Module-scope constants the provider's functions read. Dot-sourced by the root module after the
# provider's Private and Public folders.

# The container every seeded object lives in, prefixed like everything else this module creates.
# Sixty-nine places build a distinguished name from it, so it is a variable rather than a literal
# repeated in each of them - and Connect-ADEnvironment overwrites it when given a -Prefix, which
# is what keeps the tree, the groups and the computers all carrying the same identifier.
$script:ADTestRootName = '{0}TestData' -f $script:TestEnvironmentDefaultPrefix