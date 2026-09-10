# The Okta provider

Part of [TestEnvironment](../../README.md).

An Integrator Free Plan org allows ten active users, so this provider seeds breadth rather than
volume: group rules, custom user types, network zones, sign-on and password policies, trusted
origins, event hooks and linked objects.

```powershell
# First run: trade an API token for an app that can act on its own
$token = Read-Host 'SSWS token' -AsSecureString
Connect-TestEnvironment -Provider Okta -OrgUrl https://trial-123456.okta.com -ApiToken $token
New-TestServiceApp

# Every run afterwards
Connect-TestEnvironment -Provider Okta -OrgUrl https://trial-123456.okta.com -ServiceApp
New-TestEnvironment
Get-TestEnvironmentReport
```

| | Count |
|---|---|
| Users | 8 (of a 10-user ceiling, leaving room for a second admin) |
| Groups / group rules | 17 / 3 |
| Apps | 9, across three sign-on modes |
| Custom attributes | 18 across 2 user types |
| Network zones / policies | 2 / 3 |
| Trusted origins / event hooks / linked objects | 2 / 2 / 1 |

### Bootstrapping trades the API token for a service app

Paste an SSWS token once, let the module register an OAuth service app with only the `okta.*`
scopes it needs, and revoke the token. Every run afterwards authenticates as the app.

`okta.clients.manage` is deliberately withheld from the app, so rotating its key always needs a
token — keep one rather than revoking every time.
