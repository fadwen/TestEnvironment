# The Okta provider

Part of [TestEnvironment](../../README.md).

The smallest of the four by object count and the most varied by object type. An Integrator Free
Plan org allows ten active users, so this provider proves breadth where the others prove volume:
group rules, custom user types, network zones, sign-on and password policies, trusted origins,
event hooks and linked objects — the cloud-IdP surface that has no on-premises equivalent.

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

### The bootstrap runs the other way round from Entra's

Okta *does* have a long-lived personal API key, so the trade is real: paste an SSWS token once,
let the module register an OAuth service app with only the `okta.*` scopes it needs, and revoke
the token. Entra has no such key to trade, which is why its bootstrap signs a human in by device
code instead. Same destination, opposite starting point.

`okta.clients.manage` is deliberately withheld from the app, so rotating its key always needs a
token — keep one rather than revoking every time.

### Names dropped their `Test` infix

`New-OktaTestUser` became `New-OktaUser`, and so on, matching the Entra provider. Okta ships no
PowerShell cmdlets of its own, so there is nothing to collide with — which is exactly why the AD
provider's names could not do the same.
