# OneLogin provider initialisation.
#
# Module-scope constants the provider's functions read. Dot-sourced by the root module after the
# provider's Private and Public folders, which is what makes these available to them.

# The domain seeded usernames and emails are written against, substituted for the connection's
# EmailDomain so one CSV serves any account. Under example.com, which RFC 2606 reserves so that test
# data cannot deliver mail to a real recipient.
$script:OneLoginDefaultSeedDomain = 'onelogin-lab.example.com'

# The custom user field that carries the seed tag on every seeded user.
#
# A OneLogin user has no description and nothing else that is free text nobody writes: comment,
# company, department and title are all things an administrator fills in. So the seed creates a
# field of its own, writes the tag into it on every user it makes, and teardown removes it last.
# Verified live: a shortname may hold letters, digits and underscores and must be unique, a dash is
# refused as "Shortname is invalid", and the users endpoint filters on it server-side as
# custom_attributes.<shortname>=<value>.
$script:OneLoginSeedAttribute = 'zztest_seed_tag'

# Every custom field this provider declares starts with this. Teardown removes a field only when the
# data declares it AND its shortname carries this prefix, because a field has no description to hold
# a tag and the shortname is the only thing about it the seed controls.
$script:OneLoginAttributePrefix = 'zztest_'

# The connectors seeded apps are built from. OneLogin makes every app an instance of a connector, and
# these two are the generic ones: OpenId Connect (OIDC) and SAML Custom Connector (Advanced). The ids
# are global across OneLogin accounts, verified by name against /api/2/connectors.
$script:OneLoginConnector = @{
    OIDC = 108419
    SAML = 110016
}

# OneLogin's numeric user status and state, by name. Every value is here so a report can name what it
# reads; the seed data uses only the ones that stay put, and SeedData.Tests.ps1 holds it to that.
# Three do not, all verified against a live account: Locked, because OneLogin sets locked_until
# fifteen minutes out and unlocks the account itself; Unactivated, which read back as
# PasswordPending moments after creation; and the Unapproved state, which read back as Approved.
$script:OneLoginUserStatus = [ordered]@{
    Unactivated           = 0
    Active                = 1
    Suspended             = 2
    Locked                = 3
    PasswordExpired       = 4
    AwaitingPasswordReset = 5
    PasswordPending       = 7
}
$script:OneLoginUserState = [ordered]@{
    Unapproved = 0
    Approved   = 1
    Rejected   = 2
    Unlicensed = 3
}

# OIDC token endpoint authentication, by the names the seed data uses. None is the public client, and
# on OneLogin choosing it is choosing PKCE: the connector offers no public client without it.
$script:OneLoginTokenAuth = @{
    Basic = 0
    Post  = 1
    None  = 2
}

# What a person may be for a role to hold them. Verified live: OneLogin accepts a role grant for anyone
# and answers 200, then keeps it only for an approved person whose status is one of these. A grant to
# someone Rejected, Unlicensed or still PasswordPending is dropped without a word, so the data gives
# roles only to people who can hold them and the seed says so when OneLogin disagrees. Locked is one:
# a locked person keeps the roles they hold.
$script:OneLoginRoleHolderStatus = @(1, 2, 3, 4, 5)

# How long a seeded Locked person stays locked, in minutes. Locked is not a status the seed can set -
# a status of 3 unlocks itself fifteen minutes later - but the version 1 lock call takes a duration,
# verified live for a year. Only a licensed person can be locked; an unlicensed one is refused. A
# repair locks again, so a seed older than a year is put back rather than left unlocked.
$script:OneLoginLockMinutes = 525600

# The fields a user listing has to ask for. OneLogin's list leaves out custom_attributes, role_ids and
# the manager unless they are named, and without custom_attributes no seeded user can be proved ours.
$script:OneLoginUserFields = 'id,username,email,firstname,lastname,title,department,company,status,state,group_id,manager_user_id,role_ids,custom_attributes,' +
    'samaccountname,userprincipalname,distinguished_name,member_of,external_id,phone,comment,preferred_locale_code,locked_until'

# The marker a seeded Smart Hook carries in its own code. A hook has no name and no description, so the
# comment on its first line is the only place a tag can go; teardown decodes the function and looks for
# it. The seed writes this line; nothing else does.
$script:OneLoginHookMarker = '// {0}'

# What each object type's ownership proof reads, for teardown's -Keep. Keeping a type means keeping
# everything its proof depends on, or the next teardown could never claim it: a role is proved by the
# people and apps in it, a group by its people, a policy by the groups using it, a mapping and a hook by
# the roles they name, an app rule by its app and the roles it names, a person by the tag field.
$script:OneLoginProofDependency = @{
    Users             = @('Attributes')
    Roles             = @('Users', 'Apps')
    Groups            = @('Users')
    Policies          = @('Groups')
    Mappings          = @('Roles')
    Hooks             = @('Roles')
    AppRules          = @('Apps', 'Roles')
    Apps              = @()
    ApiAuthorizations = @()
    SelfRegistration  = @()
    Attributes        = @()
}

# The page size every list request asks for. OneLogin's v2 endpoints take limit and page and answer the
# page count in a Total-Pages header.
$script:OneLoginPageSize = 100

# Which seed step owns each check Test-OneLoginEnvironment judges, for Repair-TestEnvironment. The
# users step converges a reused user's names, lifecycle, group, manager and roles, so everything about
# a person is put back by it.
$script:OneLoginRepairStep = @{
    Step   = @{
        'Attributes'       = 'Attributes'
        'Roles'            = 'Roles'
        'Groups'           = 'Groups'
        'Apps'             = 'Apps'
        'App assignments'  = 'Apps'
        'Mappings'         = 'Mappings'
        'Users'            = 'Users'
        'User names'       = 'Users'
        'User lifecycle'   = 'Users'
        'Managers'         = 'Users'
        'Group membership' = 'Users'
        'Role memberships' = 'Users'
        'Directory fields' = 'Users'
        'Policies'         = 'Policies'
        'Group policies'   = 'Policies'
        'Policy settings'  = 'Policies'
        'API authorizations' = 'ApiAuthorizations'
        'API scopes'       = 'ApiAuthorizations'
        'API claims'       = 'ApiAuthorizations'
        'API clients'      = 'ApiAuthorizations'
        'App rules'        = 'AppRules'
        'Smart hooks'      = 'Hooks'
        'Self-registration' = 'SelfRegistration'
    }
    Always = @()
}
