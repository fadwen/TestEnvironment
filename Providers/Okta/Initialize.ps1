# Okta provider initialisation.
#
# Module-scope constants the provider's functions read. Dot-sourced by the root module after the
# provider's Private and Public folders, which is what makes these available to them.
#
# This file exists because losing it broke something silently. The value below lived in the old
# OktaTestEnvironment root module, and the consolidation copied Private, Public and Data without
# it. Nothing failed at import: New-OktaApp went on running, and the -replace that substitutes
# the seed domain into an app URL simply matched an empty pattern - which inserts the replacement
# between every character rather than erroring - so the app was created with a mangled redirect
# URI. One unit test caught it. The provider convention is here so the next provider has an
# obvious place to put its constants instead of a root module that no longer belongs to it.

# The domain the seed URLs are written against, substituted for the connection's EmailDomain so
# one CSV serves any org.
$script:DefaultSeedDomain = 'oktalab.example.com'
