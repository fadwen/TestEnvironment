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
        - Policies, notification rules and transports carry the prefix on the name, which is
          all those types can hold.

        The automation service account is a user with a reserved username and is excluded from
        Users unless -IncludeServiceAccount is passed, for the same reason the Entra provider
        excludes its bootstrapped app: deleting the credential mid-teardown strands everything
        after it.

    .PARAMETER Type
        Which objects to find.

    .PARAMETER IncludeServiceAccount
        For Users only: include the module's own automation account.

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
        [ValidateSet('Users', 'Groups', 'Applications', 'Providers', 'Policies', 'NotificationRules', 'NotificationTransports')]
        [string]$Type,

        [Parameter()]
        [switch]$IncludeServiceAccount,

        [Parameter()]
        [hashtable]$Connection
    )

    if (-not $Connection) { $Connection = Get-AuthentikConnection }
    $marker = Get-AuthentikSeedMarker -Connection $Connection
    $prefix = $marker.Prefix

    $hasTag = {
        param($object)
        $attributes = $object.attributes
        $attributes -and $attributes.PSObject.Properties[$marker.Attribute] -and
        ([string]$attributes.($marker.Attribute)) -eq $marker.Tag
    }

    $startsWithPrefix = {
        param($name)
        $name -and ([string]$name).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
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
                    $_.slug -and $_.slug.StartsWith("$($marker.SlugPrefix)-", [StringComparison]::OrdinalIgnoreCase) -and
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
    }
}
