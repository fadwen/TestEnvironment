# Contributing

Thank you for looking. Issues and pull requests are welcome.

## Before you start

- **A bug or a question:** open an issue with the provider, the command, what you expected and
  what happened. For a live failure, the `-Verbose` output and the result object from `-PassThru`
  say more than the summary line.
- **A change:** open an issue first if it is more than a fix, so the shape can be agreed before
  the work. Each provider has a README that explains what it seeds and why the data looks the way
  it does; `CLAUDE.md` lists the invariants that look arbitrary until you know the reason.

## The conventions

General PowerShell conventions - module layout, comment-based help, Pester, error handling - are
mirrored into `.github/` from
[Powershell-Copilot-Standards](https://github.com/fadwen/Powershell-Copilot-Standards). Those
paths are overwritten on every sync, so a change to a convention belongs upstream.

Everything specific to this module is in `CLAUDE.md`. The ones most often tripped over:

- `RequiredModules` stays empty, and a contract test enforces it.
- Only exported functions carry `.EXTERNALHELP`; their help lives in `docs/` and is compiled to
  `en-US/TestEnvironment-Help.xml` by `Build/Build-Help.ps1`. Rebuild it in the same change as
  a docs edit; the help gate compares byte for byte.
- Windows PowerShell 5.1 and PowerShell 7 both have to work, so nothing 7-only in `Core/`,
  `Providers/` or `Public/`.
- `-WhatIf` beats `-Force` on every destructive command, and the Remove suites pin it.

## The checks

```powershell
Invoke-Pester ./Tests/Unit                                  # about a minute, no directory needed
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error, Warning
./Build/Build-Help.ps1                                      # after editing docs/
./Build/Publish-Module.ps1 -WhatIf                          # the full release rehearsal
```

The unit suite reaches no tenant, domain, org, instance or realm; every provider's seed suite
carries a backstop that fails if a call escapes the mocks. A change to a provider's behaviour
should also be run against a real one you own, and the pull request should say what you ran and
what it did - the provider READMEs record the timings and the shapes to expect.

## Pull requests

- One provider or one concern per pull request.
- Add or update the tests that pin the behaviour, and a line in `CHANGELOG.md` under
  `[Unreleased]`.
- The quality gates run on every pull request on Windows, Windows PowerShell 5.1 and Linux.
