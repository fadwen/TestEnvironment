function Get-AuthentikSeededObject {
    <#
    .SYNOPSIS
        Finds the objects of one type that this module created, and nothing else

    .DESCRIPTION
        Teardown and the report both need the same answer: which of the objects in the
        instance are ours. Every type carries the seed prefix on its name, but a name is not
        proof - an administrator can name a group anything - so each type also has to satisfy
        the evidence the module wrote when it created the object:

        - Users are under the seed path AND carry the seed tag in their attributes. The
          path is what Authentik lets a listing filter on, and the tag is what proves the
          module put them there. Human user accounts carry no prefix, so this is the only
          evidence they have.
        - Groups carry the prefix on the name AND the seed tag in their attributes.
        - Applications carry the slug prefix AND the bracketed marker in their description,
          because applications have no attributes.
        - Providers carry the prefix on the name, and are either attached to a seeded
          application or attached to nothing. A provider with our prefix that is wired to
          someone else's application is left alone.
        - Entitlements belong to a seeded application AND carry the prefix AND the tag in
          their attributes. They are read per seeded application, which is the only filter
          the endpoint offers.
        - Tokens carry the slug prefix on the identifier AND belong to a user that is itself
          seeded: under the path and tagged. The automation service account's own token is
          excluded unless -IncludeServiceAccount is passed, because it is the credential the
          session is using.
        - Invitations carry the slug prefix on the name AND the tag in their fixed data.
        - Flows carry the slug prefix on the slug, which is what the instance routes by.
        - Roles, scope mappings, outposts, certificates, stages, policies, notification rules
          and transports carry the prefix on the name, which is all those types can hold. A
          scope mapping or an outpost is additionally required to be unmanaged, since a
          managed one belongs to Authentik itself.

        The automation service account is a user with a reserved username and is excluded from
        Users unless -IncludeServiceAccount is passed, for the same reason the Entra provider
        excludes its bootstrapped app: deleting the credential mid-teardown strands everything
        after it.

    .PARAMETER Type
        Which objects to find.

    .PARAMETER IncludeServiceAccount
        For Users and Tokens: include the module's own automation account, or its token.

    .PARAMETER Connection
        The connection to look through. Defaults to the active one.

    .OUTPUTS
        System.Object[]. The objects as Authentik returned them, or an empty array.

    .EXAMPLE
        PS> Get-AuthentikSeededObject -Type Users

        DESCRIPTION: Lists the seeded users
        OUTPUT: Every user under the seed path carrying the tag, minus the automation account
        USE CASE: Membership resolution in New-AuthentikGroup and the users step of teardown

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Users', 'Groups', 'Applications', 'Providers', 'Entitlements', 'ScopeMappings', 'Roles',
            'Outposts', 'Certificates', 'Flows', 'Stages', 'Policies', 'NotificationRules', 'NotificationTransports',
            'Tokens', 'Invitations')]
        [string]$Type,

        [Parameter()]
        [switch]$IncludeServiceAccount,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-AuthentikConnection }
    $marker = Get-AuthentikSeedMarker -Connection $Connection
    $prefix = $marker.Prefix
    $slugPrefix = '{0}-' -f $marker.SlugPrefix

    $hasTag = {
        param($object, $property)
        if (-not $property) { $property = 'attributes' }
        $attributes = $object.$property
        $attributes -and $attributes.PSObject.Properties[$marker.Attribute] -and
        ([string]$attributes.($marker.Attribute)) -eq $marker.Tag
    }

    $startsWithPrefix = {
        param($name)
        $name -and ([string]$name).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    }

    $startsWithSlugPrefix = {
        param($name)
        $name -and ([string]$name).StartsWith($slugPrefix, [StringComparison]::OrdinalIgnoreCase)
    }

    $isSeededUser = {
        param($user)
        $user -and ([string]$user.path) -eq $marker.UserPath -and (& $hasTag $user)
    }

    switch ($Type) {
        'Users' {
            $serviceAccount = Get-AuthentikServiceAccountName -Marker $marker
            $users = @(Invoke-AuthentikRequest -Method GET -Path '/core/users/' `
                    -Query @{ path = $marker.UserPath } -Connection $Connection -Paginate)
            return @($users | Where-Object {
                    (& $hasTag $_) -and
                    ($IncludeServiceAccount -or $_.username -ne $serviceAccount)
                })
        }
        'Groups' {
            $groups = @(Invoke-AuthentikRequest -Method GET -Path '/core/groups/' `
                    -Query @{ search = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($groups | Where-Object { (& $startsWithPrefix $_.name) -and (& $hasTag $_) })
        }
        'Applications' {
            $applications = @(Invoke-AuthentikRequest -Method GET -Path '/core/applications/' `
                    -Query @{ search = $marker.SlugPrefix; superuser_full_list = 'true' } -Connection $Connection -Paginate)
            return @($applications | Where-Object {
                    (& $startsWithSlugPrefix $_.slug) -and
                    $_.meta_description -and $_.meta_description.Contains($marker.Marker)
                })
        }
        'Providers' {
            $ownedSlugs = @((Get-AuthentikSeededObject -Type Applications -Connection $Connection).slug)
            $providers = @(Invoke-AuthentikRequest -Method GET -Path '/providers/all/' `
                    -Query @{ search = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($providers | Where-Object {
                    (& $startsWithPrefix $_.name) -and
                    (-not $_.assigned_application_slug -or $ownedSlugs -contains $_.assigned_application_slug)
                })
        }
        'Entitlements' {
            $applications = @(Get-AuthentikSeededObject -Type Applications -Connection $Connection)
            $entitlements = foreach ($application in $applications) {
                @(Invoke-AuthentikRequest -Method GET -Path '/core/application_entitlements/' `
                        -Query @{ app = [string]$application.pk } -Connection $Connection -Paginate) |
                    Where-Object { (& $startsWithPrefix $_.name) -and (& $hasTag $_) } |
                    ForEach-Object {
                        # The application slug is what the CSV and the report speak in.
                        Add-Member -InputObject $_ -NotePropertyName 'app_slug' -NotePropertyValue $application.slug -Force -PassThru
                    }
            }
            return @($entitlements)
        }
        'ScopeMappings' {
            $mappings = @(Invoke-AuthentikRequest -Method GET -Path '/propertymappings/provider/scope/' `
                    -Query @{ managed__isnull = 'true' } -Connection $Connection -Paginate)
            return @($mappings | Where-Object { (& $startsWithPrefix $_.name) -and -not $_.managed })
        }
        'Roles' {
            $roles = @(Invoke-AuthentikRequest -Method GET -Path '/rbac/roles/' -Connection $Connection -Paginate)
            return @($roles | Where-Object { & $startsWithPrefix $_.name })
        }
        'Outposts' {
            $outposts = @(Invoke-AuthentikRequest -Method GET -Path '/outposts/instances/' `
                    -Query @{ name__icontains = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($outposts | Where-Object { (& $startsWithPrefix $_.name) -and -not $_.managed })
        }
        'Flows' {
            $flows = @(Invoke-AuthentikRequest -Method GET -Path '/flows/instances/' `
                    -Query @{ search = $marker.SlugPrefix } -Connection $Connection -Paginate)
            return @($flows | Where-Object { & $startsWithSlugPrefix $_.slug })
        }
        'Stages' {
            $stages = @(Invoke-AuthentikRequest -Method GET -Path '/stages/all/' `
                    -Query @{ search = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($stages | Where-Object { & $startsWithPrefix $_.name })
        }
        'Certificates' {
            $keypairs = @(Invoke-AuthentikRequest -Method GET -Path '/crypto/certificatekeypairs/' `
                    -Query @{ search = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($keypairs | Where-Object { (& $startsWithPrefix $_.name) -and -not $_.managed })
        }
        'Policies' {
            $policies = @(Invoke-AuthentikRequest -Method GET -Path '/policies/all/' `
                    -Query @{ search = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($policies | Where-Object { & $startsWithPrefix $_.name })
        }
        'NotificationRules' {
            $rules = @(Invoke-AuthentikRequest -Method GET -Path '/events/rules/' `
                    -Query @{ search = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($rules | Where-Object { & $startsWithPrefix $_.name })
        }
        'NotificationTransports' {
            $transports = @(Invoke-AuthentikRequest -Method GET -Path '/events/transports/' `
                    -Query @{ search = $prefix.TrimEnd('-') } -Connection $Connection -Paginate)
            return @($transports | Where-Object { & $startsWithPrefix $_.name })
        }
        'Tokens' {
            $serviceAccount = Get-AuthentikServiceAccountName -Marker $marker
            $tokens = @(Invoke-AuthentikRequest -Method GET -Path '/core/tokens/' `
                    -Query @{ search = $marker.SlugPrefix } -Connection $Connection -Paginate)
            return @($tokens | Where-Object {
                    (& $startsWithSlugPrefix $_.identifier) -and (& $isSeededUser $_.user_obj) -and
                    ($IncludeServiceAccount -or $_.user_obj.username -ne $serviceAccount)
                })
        }
        'Invitations' {
            $invitations = @(Invoke-AuthentikRequest -Method GET -Path '/stages/invitation/invitations/' `
                    -Query @{ search = $marker.SlugPrefix } -Connection $Connection -Paginate)
            return @($invitations | Where-Object { (& $startsWithSlugPrefix $_.name) -and (& $hasTag $_ 'fixed_data') })
        }
    }
}
