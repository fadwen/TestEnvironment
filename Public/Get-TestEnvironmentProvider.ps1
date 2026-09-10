function Get-TestEnvironmentProvider {
    <#
    .EXTERNALHELP TestEnvironment-Help.xml
    .SYNOPSIS
        Lists the identity providers this module can seed, and which one is active
    #>

    [CmdletBinding()]
    [OutputType('TestEnvironmentProviderInfo')]
    param()

    foreach ($name in ($script:TestEnvironmentProvider.Keys | Sort-Object)) {
        $provider = $script:TestEnvironmentProvider[$name]

        [PSCustomObject]@{
            PSTypeName = 'TestEnvironmentProviderInfo'
            Name       = $name
            Active     = ($script:ActiveProvider -eq $name)
            DataPath   = $provider.DataPath
            SeedFiles  = @(Get-ChildItem -Path $provider.DataPath -Filter *.csv -ErrorAction SilentlyContinue).Count
        }
    }
}
