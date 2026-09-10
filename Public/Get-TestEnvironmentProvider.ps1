function Get-TestEnvironmentProvider {
    <#
    .SYNOPSIS
        Lists the identity providers this module can seed, and which one is active

    .DESCRIPTION
        Answers two questions that are easy to get wrong from the outside: what can this module
        drive, and what is it pointed at right now.

        The second matters more than it sounds. Every command after Connect-TestEnvironment
        acts on the active provider without naming it, which is deliberate - restating the
        provider on every call is how a script seeds one directory and tears down another - but
        it does mean the answer is worth being able to ask for plainly, especially before
        anything destructive.

        Providers are discovered from the Providers folder at import rather than listed in
        code, so a new one appears here by existing.

    .OUTPUTS
        TestEnvironmentProviderInfo[]

    .EXAMPLE
        PS> Get-TestEnvironmentProvider

        DESCRIPTION: Lists every loaded provider and flags the active one
        OUTPUT: Name, Active, DataPath
        USE CASE: Confirming what a session is pointed at before tearing anything down

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
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
