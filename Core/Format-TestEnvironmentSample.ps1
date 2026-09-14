function Format-TestEnvironmentSample {
    <#
    .SYNOPSIS
        Renders the first few names of a list for a console line
    .DESCRIPTION
        A failed check can name hundreds of objects. The console line shows the first few and
        says how many more there are; the full list stays on the result object.
    .PARAMETER Item
        The names
    .PARAMETER Limit
        How many to show before summarising the rest
    .OUTPUTS
        System.String
    .EXAMPLE
        PS> Format-TestEnvironmentSample -Item $check.Missing

        "a, b, c, d, e and 12 more"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Item,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Limit = 5
    )

    $items = @($Item | Where-Object { $null -ne $_ })
    if ($items.Count -eq 0) { return '' }
    $shown = @($items | Select-Object -First $Limit) -join ', '
    if ($items.Count -le $Limit) { return $shown }
    return '{0} and {1} more' -f $shown, ($items.Count - $Limit)
}
