function Get-TestProviderParameter {
    <#
    .SYNOPSIS
        Builds a dynamic parameter set mirroring a provider command's own parameters

    .DESCRIPTION
        The shared dispatch functions - New-TestEnvironment, Remove-TestEnvironment and the
        rest - forward to whichever provider the session is connected through. They need to
        accept whatever that provider accepts, and the alternatives are all worse:

        - Restating each provider's parameters by hand means every provider change needs a
          matching edit here, and the one that gets forgotten fails by silently not forwarding.
        - ValueFromRemainingArguments accepts anything and binds nothing, so a typo becomes a
          runtime surprise instead of a binding error, and tab completion stops working.

        So the target command's real parameters are reflected over and re-declared. That gives
        tab completion, Get-Help, mandatory enforcement and type checking on the dispatcher,
        all sourced from the provider rather than duplicated from it.

        Common parameters are excluded, because PowerShell adds those itself and re-declaring
        one is an error rather than a no-op.

    .PARAMETER CommandName
        The provider command whose parameters should be mirrored. A name that does not resolve
        returns an empty dictionary rather than throwing, because dynamicparam runs during
        binding - before the dispatcher has had a chance to report that nothing is connected.

    .PARAMETER Exclude
        Parameters the caller declares itself. Re-declaring one is not an override but an
        error - "a parameter with the name 'PassThru' was defined multiple times" - so a
        dispatcher that keeps a parameter of its own has to name it here.

    .OUTPUTS
        System.Management.Automation.RuntimeDefinedParameterDictionary

    .EXAMPLE
        PS> Get-TestProviderParameter -CommandName 'New-EntraEnvironment'

        DESCRIPTION: Mirrors the Entra provider's parameters onto the caller
        OUTPUT: A dictionary the dynamicparam block returns
        USE CASE: Called from every shared dispatch function

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [CmdletBinding()]
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CommandName,

        [Parameter()]
        [string[]]$Exclude = @()
    )

    $dictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    if ([string]::IsNullOrWhiteSpace($CommandName)) { return $dictionary }

    $command = Get-Command -Name $CommandName -ErrorAction SilentlyContinue
    if (-not $command) { return $dictionary }

    # PowerShell supplies these itself; re-declaring one throws rather than being ignored.
    $common = [System.Management.Automation.PSCmdlet]::CommonParameters +
        [System.Management.Automation.PSCmdlet]::OptionalCommonParameters

    foreach ($entry in $command.Parameters.GetEnumerator()) {
        if ($common -contains $entry.Key) { continue }
        if ($Exclude -contains $entry.Key) { continue }

        $attributes = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        # Parameter attributes are copied rather than recreated, so mandatory-ness, parameter
        # sets and pipeline binding all survive. Validation attributes come with them, which is
        # what keeps a bad value failing at the dispatcher rather than inside the provider.
        foreach ($attribute in $entry.Value.Attributes) {
            $attributes.Add($attribute)
        }

        $dictionary.Add($entry.Key,
            [System.Management.Automation.RuntimeDefinedParameter]::new(
                $entry.Key, $entry.Value.ParameterType, $attributes))
    }

    return $dictionary
}
