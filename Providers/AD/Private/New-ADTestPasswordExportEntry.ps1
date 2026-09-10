function New-ADTestPasswordExportEntry {
    <#
    .SYNOPSIS
        Creates a standardized password export entry object

    .DESCRIPTION
        Helper function to create a consistent password export entry object
        that can be used with Export-ADTestPasswordDocumentation.

    .PARAMETER ServiceAccountName
        Name of the service account

    .PARAMETER Password
        Generated password for the account

    .PARAMETER CreatedDate
        Date when the account/password was created. Defaults to current date.

    .PARAMETER Description
        Optional description for the service account

    .PARAMETER Department
        Optional department information

    .PARAMETER ExpirationDate
        Optional password expiration date

    .EXAMPLE
        $entry = New-ADTestPasswordExportEntry -ServiceAccountName "svc-app1" -Password "SecurePass123!"
        Creates a basic password export entry

    .EXAMPLE
        $entry = New-ADTestPasswordExportEntry -ServiceAccountName "svc-db1" -Password "DatabasePass456@" -Description "Database service account" -Department "IT"
        Creates a detailed password export entry

    .OUTPUTS
        PSCustomObject containing standardized password export entry

    .NOTES
        Author: Jeffrey Stuhr
        Version: 1.0.0
        Last Updated: 2025-08-03
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds and returns an object. Nothing is created, written or changed, so there is nothing for ShouldProcess to guard.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password',
        Justification = 'This function exists to put the generated service account passwords into the CSV and HTML documentation a person reads afterwards. A SecureString here would be converted straight back one line later, which hides the handling without changing it.')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountName,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password,
        
        [Parameter()]
        [DateTime]$CreatedDate = (Get-Date),
        
        [Parameter()]
        [string]$Description,
        
        [Parameter()]
        [string]$Department,
        
        [Parameter()]
        [DateTime]$ExpirationDate
    )

    $entry = [PSCustomObject]@{
        ServiceAccountName = $ServiceAccountName
        Password = $Password
        CreatedDate = $CreatedDate
    }
    
    # Add optional properties if provided
    if ($Description) {
        $entry | Add-Member -NotePropertyName 'Description' -NotePropertyValue $Description
    }
    if ($Department) {
        $entry | Add-Member -NotePropertyName 'Department' -NotePropertyValue $Department
    }
    if ($ExpirationDate) {
        $entry | Add-Member -NotePropertyName 'ExpirationDate' -NotePropertyValue $ExpirationDate
    }
    
    return $entry
}
