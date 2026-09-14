# Entra provider initialisation.

# Which seed step owns each check Test-EntraEnvironment judges, for Repair-TestEnvironment, and
# the steps that run alongside any repair: the units first, so a re-created object has a
# container, and containment last, so it lands in one. Memberships live on the groups step,
# which adds every member a group row lists.
$script:EntraRepairStep = @{
    Step   = @{
        'Users'              = 'Users'
        'User display names' = 'Users'
        'Guests'             = 'GuestUsers'
        'Groups'             = 'Groups'
        'Group memberships'  = 'Groups'
        'Devices'            = 'Devices'
        'Applications'       = 'Applications'
    }
    Always = @('AdministrativeUnits', 'Containment')
}
