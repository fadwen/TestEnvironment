# PingOne provider initialisation.
#
# Module-scope constants the provider's functions read. Dot-sourced by the root module after the
# provider's Private and Public folders, which is what makes these available to them.

# The regional API and auth hosts PingOne serves from. A tenant lives in exactly one region and
# the suffix is not derivable from the environment id, so the connection carries it and these
# are the values it validates against. North America is the default because it is what a trial
# lands on; the console's own hostname is the reliable way to tell, which is why
# Connect-PingOneEnvironment takes -Region rather than guessing.
$script:PingOneRegionHost = @{
    NorthAmerica = @{ Api = 'api.pingone.com'; Auth = 'auth.pingone.com'; Console = 'console.pingone.com' }
    Europe       = @{ Api = 'api.pingone.eu'; Auth = 'auth.pingone.eu'; Console = 'console.pingone.eu' }
    Canada       = @{ Api = 'api.pingone.ca'; Auth = 'auth.pingone.ca'; Console = 'console.pingone.ca' }
    AsiaPacific  = @{ Api = 'api.pingone.asia'; Auth = 'auth.pingone.asia'; Console = 'console.pingone.asia' }
    Australia    = @{ Api = 'api.pingone.com.au'; Auth = 'auth.pingone.com.au'; Console = 'console.pingone.com.au' }
}

# The domain seeded usernames and emails are written against, substituted for the connection's
# EmailDomain so one CSV serves any environment. Under example.com, which RFC 2606 reserves so
# that test data cannot deliver mail to a real recipient.
$script:PingOneDefaultSeedDomain = 'pingonelab.example.com'

# The custom user attribute this provider creates to carry the seed tag.
#
# It exists because a PingOne user has nowhere else to put one. A group, an application, a
# population and a resource all have a description field; a user has none, and no externalId
# that is safe to claim. Verified against a live environment: the user object carries account,
# address, email, enabled, identityProvider, lifecycle, mfaEnabled, name, population, username
# and verifyStatus, and not one of them is free text this module could own.
#
# So the attribute is part of the seed rather than a prerequisite: the seed creates it, every
# seeded user carries the tag in it, and teardown removes it last, after the users that
# reference it. The name is camel case because that is what PingOne accepts for a custom
# attribute, and it is deliberately unlike anything a person would add by hand.
$script:PingOneSeedAttributeName = 'zzTestSeedTag'

# PingOne's own applications, which exist in every environment and are not the seed's to touch.
# They are matched by type rather than by name, because a name can be edited in the console and
# the type cannot. Teardown refuses to delete any of them even if one somehow carried the tag.
$script:PingOnePlatformApplicationType = @(
    'PING_ONE_ADMIN_CONSOLE'
    'PING_ONE_PORTAL'
    'PING_ONE_SELF_SERVICE'
)

# The built-in resources every environment ships with, for the same reason.
$script:PingOnePlatformResourceType = @('PINGONE_API', 'OPENID_CONNECT')
