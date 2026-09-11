function New-FreeIPAHttpClient {
    <#
    .SYNOPSIS
        Builds the HTTP client a FreeIPA connection sends every request through

    .DESCRIPTION
        FreeIPA authenticates a browser-style session: a form login sets a cookie, and every
        JSON-RPC call after it carries that cookie and a Referer header naming the server. One
        HttpClient per connection holds both, in both PowerShell editions, which is why this is
        not Invoke-WebRequest: a session variable would do the cookie, but nothing in
        Invoke-WebRequest pins a certificate authority on Windows PowerShell.

        A FreeIPA server almost always presents a certificate from the realm's own CA, which
        the machine running this module does not trust. Rather than turning certificate
        validation off, the CA is pinned: given its PEM, the handler accepts a server
        certificate only if it chains to exactly that CA, and refuses anything else including
        a certificate the operating system would have trusted. The validation runs inside a
        small compiled class, because a PowerShell script block handed to HttpClient as a
        callback runs on a thread with no runspace and fails there. Without a PEM the operating
        system's trust store decides, as it would for any other HTTPS call.

    .PARAMETER BaseUrl
        The server URL, for the Referer header.

    .PARAMETER CaCertificate
        The PEM text of the certificate authority to pin, or nothing to use the OS trust store.

    .OUTPUTS
        PSCustomObject with Client, the HttpClient with cookies enabled and the Referer header
        set, and Cookies, the container the session cookie lands in.

    .EXAMPLE
        PS> $http = New-FreeIPAHttpClient -BaseUrl https://ipa.example.com -CaCertificate $pem

        DESCRIPTION: Builds a client that trusts only the realm's CA
        OUTPUT: The client and its cookie container
        USE CASE: Connect-FreeIPAEnvironment, and the bootstrap's handover check

    .NOTES
        Author: Jeffrey Stuhr
        Blog: https://www.techbyjeff.net
        LinkedIn: https://www.linkedin.com/in/jeffrey-stuhr-034214aa/
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in-memory client and changes nothing outside the process.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter()]
        [string]$CaCertificate
    )

    # Windows PowerShell defaults to TLS 1.0. Only ever add to the enabled set: clearing it
    # would change behaviour for everything else in the session.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $tls12 = [System.Net.SecurityProtocolType]::Tls12
        if (([System.Net.ServicePointManager]::SecurityProtocol -band $tls12) -ne $tls12) {
            [System.Net.ServicePointManager]::SecurityProtocol =
                [System.Net.ServicePointManager]::SecurityProtocol -bor $tls12
        }
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    }

    $handler = $null
    if (-not [string]::IsNullOrWhiteSpace($CaCertificate)) {
        if (-not ('TestEnvironment.FreeIPA.PinnedCaHandler' -as [type])) {
            # Compiled once per session. The chain is built with the pinned CA offered as an
            # extra store and unknown authorities allowed, and then the root the chain ended
            # on has to be the pinned CA itself; that is the check, not the chain status.
            $source = @'
using System;
using System.Net.Http;
using System.Security.Cryptography.X509Certificates;

namespace TestEnvironment.FreeIPA
{
    public static class PinnedCaHandler
    {
        public static HttpClientHandler Create(X509Certificate2 ca)
        {
            var handler = new HttpClientHandler();
            handler.UseCookies = true;
            handler.CookieContainer = new System.Net.CookieContainer();
            handler.ServerCertificateCustomValidationCallback = (request, cert, chain, errors) =>
            {
                if (cert == null) { return false; }
                var check = new X509Chain();
                check.ChainPolicy.ExtraStore.Add(ca);
                check.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                check.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;
                if (!check.Build(cert)) { return false; }
                var root = check.ChainElements[check.ChainElements.Count - 1].Certificate;
                return string.Equals(root.Thumbprint, ca.Thumbprint, StringComparison.OrdinalIgnoreCase);
            };
            return handler;
        }
    }
}
'@
            $addTypeArgs = @{ TypeDefinition = $source; ErrorAction = 'Stop' }
            if ($PSVersionTable.PSEdition -eq 'Desktop') { $addTypeArgs['ReferencedAssemblies'] = @('System.Net.Http') }
            Add-Type @addTypeArgs
        }

        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            [System.Text.Encoding]::ASCII.GetBytes($CaCertificate))
        $handler = [TestEnvironment.FreeIPA.PinnedCaHandler]::Create($certificate)
    }
    else {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.UseCookies = $true
        $handler.CookieContainer = [System.Net.CookieContainer]::new()
    }

    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(5)
    $client.DefaultRequestHeaders.Referrer = [uri]('{0}/ipa' -f $BaseUrl.TrimEnd('/'))

    return [PSCustomObject]@{
        Client  = $client
        Cookies = $handler.CookieContainer
    }
}
