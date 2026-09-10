function Get-ADTestPolicySetting {
    <#
    .SYNOPSIS
        Returns the definition of the test environment's companion Group Policy object.

    .DESCRIPTION
        Single source of truth for the GPO that New-ADTestGroupPolicy creates and
        Remove-ADEnvironment deletes. Both read it from here rather than repeating the
        name, so the two halves cannot drift apart - which is exactly how the -GlobalVault
        switch on the vault teardown ended up doing nothing.

        The deny-logon rights this describes are LSA account rights, not directory
        attributes: New-ADUser cannot express them. They are granted per machine, so the
        domain-wide equivalent is a GPO that names the accounts and is linked where the
        machines live.

        Note that this is Computer Configuration policy. It is deliberately linked to the
        test DEVICES OU and not to the ServiceAccounts OU: user rights assignment applies
        to the computers processing the policy, so linking it over user objects would have
        no effect at all.

    .PARAMETER DomainDN
        Distinguished name of the domain, used to build the link target.

    .EXAMPLE
        $policy = Get-ADTestPolicySetting -DomainDN 'DC=contoso,DC=com'
        Get-GPO -Name $policy.Name

    .OUTPUTS
        PSCustomObject describing the policy: Name, Comment, LinkTarget and Right.

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DomainDN
    )

    # The marker is written into the GPO comment and checked again before deletion, so a
    # teardown can never remove a policy this module did not create - a name collision with
    # something real would otherwise be destructive.
    $marker = 'ADTestEnvironment test data. Safe to delete with the test environment.'

    [PSCustomObject]@{
        # Prefixed like everything else this module creates. One literal, read by both the
        # function that creates the policy and the one that removes it, so they cannot disagree.
        Name       = '{0}Deny Service Account Logon' -f (Get-ADTestSeedMarker).Prefix
        Marker     = $marker
        Comment    = "$marker Denies interactive, remote interactive and network logon " +
                     'to the generated service accounts. Linked to the test Devices OU only.'
        LinkTarget = "OU=Devices,OU=$($script:ADTestRootName),$DomainDN"
        AccountOU  = "OU=ServiceAccounts,OU=$($script:ADTestRootName),$DomainDN"

        # The three rights the service account creation path documents but cannot apply
        # itself. Order is kept stable so a regenerated GptTmpl.inf diffs cleanly.
        Right      = @(
            'SeDenyInteractiveLogonRight'
            'SeDenyRemoteInteractiveLogonRight'
            'SeDenyNetworkLogonRight'
        )
    }
}
