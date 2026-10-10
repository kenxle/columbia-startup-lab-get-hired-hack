# Development baseline

Prepared for Hirsh on 2026-10-10. The application stack is Ruby on Rails.
The Rails application has not been generated yet.

- Ruby: 3.4.11, recorded in the root `.ruby-version`.
- Bundler: 2.4.19 for the existing PDF utility's lockfile.
- Rails tooling: 8.1.4. Pin this in the application Gemfile when scaffolding.
- Claude Code agents: Claude Opus 5.5 (`claude-opus-5-5`).

`script/with-ruby` selects the pinned interpreter from the current environment
or a Homebrew Ruby 3.4 installation. It does not change the system Ruby or shell
profile. On another platform, install the version in `.ruby-version` with your
Ruby version manager first.

## Setup on macOS

```sh
brew install ruby@3.4
script/with-ruby gem install bundler -v 2.4.19 --no-document
script/with-ruby gem install rails -v 8.1.4 --no-document
(cd tools/pdf_text && ../../script/with-ruby bundle _2.4.19_ install)
script/check
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
worker. Opus 5.5 is pinned in each profile. Do not silently fall back to another
model. Keep API keys out of prompts and committed files.

## Next setup step

Agree on the app/pipeline result format and owned paths before scaffolding Rails.
The current test command runs the PDF utility only; it is not an end-to-end RFQ
test or evidence that the future application works.
