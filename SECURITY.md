# Security

## Reporting a vulnerability

Please report a vulnerability privately through
[GitHub's private vulnerability reporting](https://github.com/fadwen/TestEnvironment/security/advisories/new)
rather than in a public issue. You will get an acknowledgement within a few days and a fix or a
mitigation as soon as one is ready; the report is credited in the release notes unless you ask
otherwise.

## What this module touches

TestEnvironment writes to a directory you point it at: an Entra ID tenant, an Active Directory
domain, an Okta org, an Authentik instance or a FreeIPA realm. Everything it creates carries the
`ZZ-TEST-` prefix and the `ZZ-TEST-seed` tag, and teardown proves ownership of each object before
deleting it. It never creates an enforcing Conditional Access policy, an active PIM assignment, a
default Authentik flow, or touches a rule a FreeIPA realm shipped with, and none of those states
is a parameter. If you find a path by which it could delete or change something it did not
create, that is a vulnerability: report it as one.

## Credentials

Credential records live under `~/.testenvironment`. On Windows a stored password or token is
DPAPI-protected; with `-UseSecretStore` it goes to the SecretManagement vault instead. A private
key is never written to the working tree: an Entra certificate lives in the certificate store,
and the keys behind the certificates the FreeIPA provider has a realm issue are discarded the
moment the request is signed. The secrets it generates for OTP tokens, RADIUS proxies and
identity providers are sent once and never kept or returned.

## Supported versions

Only the latest release on the PowerShell Gallery receives fixes.
