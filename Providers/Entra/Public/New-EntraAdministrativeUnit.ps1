function New-EntraAdministrativeUnit {
    <#
    .SYNOPSIS
        Creates the administrative units that contain the seeded environment

    .DESCRIPTION
        Administrative units are Entra's nearest equivalent to an Active Directory OU, and
        they are what makes this environment contained rather than merely named.

        ADTestEnvironment puts everything under OU=TestData and can therefore say exactly what
        it created by asking the directory. Without a container, an Entra seeder can only ask
        "what is called ENTRALAB-something", which is a guess that happens to be usually right.
        With one, teardown asks the container for its members and gets an authoritative answer.

        Four units are created, one per object class, because **administrative units cannot
        nest** - verified against a live tenant, where adding one AU to another is refused with
        "The reference target ... of type 'AdministrativeUnit' is invalid for the 'members'
        reference". So AD's sub-OU tree flattens into four siblings rather than a hierarchy.

        Two properties of an AU shape how teardown uses it, and both differ from an OU:

        - **An AU is a container, not a parent.** Deleting it does not delete its members -
          verified live, all three test members survived. So the units are deleted last, after
          their contents, and they exist to identify what to delete rather than to do it.
        - **Membership is not exclusive.** An object can belong to several AUs, or to none, and
          it still lives in the tenant root regardless. Membership is therefore proof that this
          module created something, not proof of where it lives.

        Restricted management units are deliberately not used. They would stop anything outside
        the unit's own scoped administrators from modifying the members, including the
        credential this module authenticates with, which turns a lab environment into one that
        cannot tear itself down.

    .PARAMETER UnitKey
        Creates only the named units. Defaults to all four.

    .PARAMETER ShowProgress
        Draws a progress bar

    .PARAMETER PassThru
        Returns the created units

    .OUTPUTS
        EntraAdministrativeUnit[] when -PassThru is supplied

    .EXAMPLE
        PS> New-EntraAdministrativeUnit

        DESCRIPTION: Creates the four containers, before anything that goes in them
        OUTPUT: None
        USE CASE: The first step of New-EntraEnvironment

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('EntraAdministrativeUnit')]
    param(
        [Parameter()]
        [ValidateSet('Users', 'Groups', 'Devices', 'Applications')]
        [string[]]$UnitKey,

        [Parameter()]
        [switch]$ShowProgress,

        [Parameter()]
        [switch]$PassThru
    )

    $connection = Get-EntraConnection
    $marker = Get-EntraSeedMarker -Connection $connection

    $definitions = @(
        [PSCustomObject]@{ Key = 'Users'; Suffix = 'Users'; Description = 'Seeded user accounts' }
        [PSCustomObject]@{ Key = 'Groups'; Suffix = 'Groups'; Description = 'Seeded groups' }
        [PSCustomObject]@{ Key = 'Devices'; Suffix = 'Devices'; Description = 'Seeded device objects' }
        [PSCustomObject]@{ Key = 'Applications'; Suffix = 'Applications'; Description = 'Seeded application registrations' }
    )

    if ($UnitKey) {
        $definitions = @($definitions | Where-Object { $UnitKey -contains $_.Key })
    }

    $created = [System.Collections.Generic.List[object]]::new()
    $existing = @(Get-EntraSeededObject -Type AdministrativeUnits -Connection $connection)
    $index = 0

    foreach ($definition in $definitions) {
        $index++
        $displayName = '{0}{1}' -f $marker.Prefix, $definition.Suffix

        Write-TestProgress -Activity 'Seeding administrative units' -Status $displayName `
            -PercentComplete ([int](100 * $index / [Math]::Max(1, $definitions.Count))) -ShowProgress:$ShowProgress

        # Re-running over an existing environment must not create a second container with the
        # same name, because teardown would then find members split across both.
        $already = $existing | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1
        if ($already) {
            Write-Verbose "Administrative unit '$displayName' already exists ($($already.id))"
            $created.Add([PSCustomObject]@{
                    PSTypeName  = 'EntraAdministrativeUnit'
                    Key         = $definition.Key
                    Id          = $already.id
                    DisplayName = $displayName
                    Created     = $false
                })
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($displayName, 'Create administrative unit')) { continue }

        try {
            $unit = Invoke-EntraRequest -Method POST -Path '/directory/administrativeUnits' -Body @{
                displayName = $displayName
                # The seed tag goes in the description, as it does for groups, so a unit is
                # identifiable even if somebody renames it.
                description = "$($definition.Description). $($marker.Description)"
                visibility  = 'Public'
            }
        }
        catch {
            Write-Error "Failed to create administrative unit '${displayName}': $($_.Exception.Message)"
            continue
        }

        $created.Add([PSCustomObject]@{
                PSTypeName  = 'EntraAdministrativeUnit'
                Key         = $definition.Key
                Id          = $unit.id
                DisplayName = $displayName
                Created     = $true
            })

        Write-Verbose "Created administrative unit '$displayName' ($($unit.id))"
    }

    Write-TestProgress -Activity 'Seeding administrative units' -Completed -ShowProgress:$ShowProgress

    if ($PassThru) { return $created.ToArray() }
}
