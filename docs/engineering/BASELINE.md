# Development baseline

Prepared for Hirsh on 2026-10-10. The application stack is Ruby on Rails.
The Rails 8.1.4 application lives at the repository root and uses local SQLite.

- Ruby: 3.4.11, recorded in the root `.ruby-version`.
- Bundler: 2.4.19 for the existing PDF utility's lockfile.
- Rails: 8.1.4, pinned by Gemfile.lock.
- Complex implementation and decisions: Fable and GPT-6 Astra.
- Independent review: Claude Opus 5.5 (`claude-opus-5-5`).
- Fable currently requires account usage credits; Astra is the authorized available path.

`script/with-ruby` selects the pinned interpreter from the current environment
or a Homebrew Ruby 3.4 installation. It does not change the system Ruby or shell
profile. On another platform, install the version in `.ruby-version` with your
Ruby version manager first.

## Setup on macOS

```sh
brew install ruby@3.4
script/with-ruby gem install bundler -v 2.4.19 --no-document
script/with-ruby gem install rails -v 8.1.4 --no-document
script/setup
script/check
script/dev
```

Check the selected tools with `script/with-ruby ruby --version` and
`script/with-ruby rails --version`. If Homebrew has advanced to a newer patch,
install the pinned version through a version manager or agree on and test an
updated team baseline before changing `.ruby-version`.

## Parallel work

Read the latest bulletin after every pull. One coordinator owns Git operations
in each shared checkout. Pull before assigning work and before committing, and
check upstream at safe checkpoints every 5 to 10 minutes during longer work.
Reviewers work against a stated revision. Incoming changes require checking
whether their review is still applicable.

The reusable Claude agents are `rfq-implementer`, `rfq-reviewer`, and
`rfq-debugger` in `.claude/agents/`. Use an explicit task and owned paths for each
worker. Implementer/debugger profiles request Fable; the reviewer requests Opus
5.5. Use Astra through native delegation when Fable is unavailable. Keep API
keys out of prompts and committed files.

## Application status

The Rails shell, SQLite configuration, dependency lockfile and run scripts are
ready. The quote workspace supports saved intake, sample review, edits, approval
and CSV export against [the frontend contract](FRONTEND_CONTRACT.md). Real RFQ extraction, catalog
matching and pricing providers are separate team integrations. Saved uploads
must remain awaiting processing until those services return a valid result.

Local browser sessions isolate prototype workspaces. This is not production
user authentication. Configure persistent storage and authentication before
considering deployment.
