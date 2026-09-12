# TestEnvironment — instructions for coding agents

**The instructions for this repository are in [CLAUDE.md](CLAUDE.md). Read it before changing
anything.** It is the single copy, kept current; this file deliberately holds no rules of its own.

It covers the invariants that look wrong or arbitrary until you know why and are cheap to break by
accident: why `RequiredModules` is empty, why the AD commands carry a `Test` infix and the others
do not, why help is compiled and stale help is a hard failure, which safety properties have no
parameter on purpose, and what teardown has to prove before it deletes anything. It also lists the
four checks to run and the compatibility both editions of PowerShell are held to.

General PowerShell conventions - module structure, comment-based help, Pester, error handling -
are not there. They come from
[Powershell-Copilot-Standards](https://github.com/fadwen/Powershell-Copilot-Standards) and are
mirrored into `.github/copilot-instructions.md`, `.github/instructions/` and `.github/prompts/`.
Those three paths are overwritten wholesale on every sync, so a local edit to them is silently
reverted; a change to a convention belongs upstream.

## Why this file is a pointer

It used to be a copy of `CLAUDE.md`, and the copy drifted: two providers were added to the module
while this file still described three, and its safety section still named only the two Entra
properties, so an agent reading it would not have known that a rule a FreeIPA realm shipped with
must never be touched. Instructions that are duplicated are instructions that go stale in the copy
nobody is looking at, and stale safety rules are worse than none. If you are tempted to restore
the detail here, put it in `CLAUDE.md` instead.
