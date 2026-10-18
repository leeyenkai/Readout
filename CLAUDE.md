# CLAUDE.md

**Read [`AGENTS.md`](AGENTS.md) first — it is the working agreement for this repo and applies
in full to Claude Code.** This file only adds Claude-specific notes; everything about the
project, toolchain, architecture, privacy rules and conventions lives there.

## Start here

| What you need | Where it is |
| --- | --- |
| Working agreement, build commands, architecture rules | [`AGENTS.md`](AGENTS.md) |
| What the app is meant to do, requirement IDs `R-nn` | [`docs/SPEC.md`](docs/SPEC.md) |
| What has shipped, what is unreleased | [`CHANGELOG.md`](CHANGELOG.md) |

## Claude-specific notes

- **Verify before reporting.** This is a sensor app with no network and little testable surface
  from the shell. Build it, and when a change is visible, run it in the Simulator and look at a
  screenshot before saying it works. Real sensor behaviour cannot be confirmed without a
  physical iPhone — say so rather than implying it was tested.
- **Don't hand-edit `project.pbxproj`.** The target uses file-system-synchronized groups, so new
  files under `Readout/` and `ReadoutTests/` are compiled automatically.
- **Two files move together with code:** `CHANGELOG.md` (entry under `## [Unreleased]`) and
  `docs/SPEC.md` (requirement status). A change that touches behaviour and leaves both
  untouched is incomplete.
- **Scope discipline.** `docs/SPEC.md` §2.2 lists what v1 deliberately excludes and §12 lists
  the milestones. Work outside the current milestone belongs in a proposal, not in the commit.
- Prefer the iOS Simulator tooling over describing the UI in prose, and open the live panel
  before building so changes can be watched.
