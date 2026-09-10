# Module-scope constants for the Authentik provider. Dot-sourced after Private/ and Public/,
# and read by the functions there; a contract test proves every $script: variable a provider
# reads is assigned somewhere, because the Okta provider once lost its seed domain in a move
# and the -replace that used it matched an empty pattern rather than failing.

# The domain the seed launch URLs, external hosts and redirect URIs are written against in
# AuthentikApplications.csv. Substituted for the connection's EmailDomain at creation time, so
# one CSV serves any instance.
$script:AuthentikDefaultSeedDomain = 'authentiklab.example.com'
