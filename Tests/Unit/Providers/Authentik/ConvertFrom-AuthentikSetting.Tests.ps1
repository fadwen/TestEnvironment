#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.1.0' }

<#
    Typed policies and invitations carry their settings in one CSV cell, and the API is strict
    about types: a GeoIP policy wants a list of country codes, a reputation policy an integer
    threshold that can be negative, a password policy booleans. A cell parsed as strings is
    accepted by the mock and rejected by the instance, so the typing is pinned here, along
    with the one separator choice that matters: a comma is not one, so an error message can
    contain it.
#>

BeforeAll {
    $script:ModuleRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))))
    Import-Module (Join-Path $script:ModuleRoot 'TestEnvironment.psd1') -Force
}

AfterAll {
    Remove-Module TestEnvironment -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-AuthentikSetting' -Tag 'Unit', 'Private' {

    It 'types booleans, integers and strings' {
        InModuleScope TestEnvironment {
            $s = ConvertFrom-AuthentikSetting -Text 'check_ip=TRUE;check_username=FALSE;threshold=-5;error_message=Too short'
            $s.check_ip | Should-BeTrue
            $s.check_username | Should-BeFalse
            $s.threshold | Should-Be -5
            ($s.threshold -is [int]) | Should-BeTrue
            $s.error_message | Should-Be 'Too short'
        }
    }

    It 'splits a pipe-separated value into a typed array' {
        InModuleScope TestEnvironment {
            $s = ConvertFrom-AuthentikSetting -Text 'countries=US|GB|DE;asns=13335|15169'
            @($s.countries) | Should-BeCollection @('US', 'GB', 'DE')
            @($s.asns) | Should-BeCollection @(13335, 15169)
        }
    }

    It 'keeps a comma inside a value' {
        InModuleScope TestEnvironment {
            $s = ConvertFrom-AuthentikSetting -Text 'error_message=Twelve characters with upper, lower and a digit;length_min=12'
            $s.error_message | Should-Be 'Twelve characters with upper, lower and a digit'
            $s.length_min | Should-Be 12
        }
    }

    It 'returns an empty table for an empty cell' {
        InModuleScope TestEnvironment {
            (ConvertFrom-AuthentikSetting -Text '').Count | Should-Be 0
            (ConvertFrom-AuthentikSetting -Text $null).Count | Should-Be 0
        }
    }

    It 'refuses a pair with no key' {
        InModuleScope TestEnvironment {
            { ConvertFrom-AuthentikSetting -Text 'length_min=12;=oops' } | Should-Throw -ExceptionMessage '*key=value*'
        }
    }
}
