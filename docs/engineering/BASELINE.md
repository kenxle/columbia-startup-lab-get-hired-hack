# Development baseline

Prepared for Hirsh on 2026-10-10. The application stack is Ruby on Rails.
The Rails 8.1.4 application lives at the repository root and uses local SQLite.

- Ruby: 3.4.11, recorded in the root `.ruby-version`.
- Bundler: 2.4.19 for the existing PDF utility's lockfile.
- Rails: 8.1.4, pinned by Gemfile.lock.
- Complex implementation and decisions: Fable and GPT-6 Astra.
- Independent review: Claude Opus 5 (`claude-opus-5`).
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

The Rails shell supports saved intake, background rules-based extraction,
RudCo/metals catalog matching, source-backed review, edits, approval, PDF/CSV
export and local email previews. See [the frontend contract](FRONTEND_CONTRACT.md).
Pasted text, PDF and CSV can run through the processor. Excel files must be saved
as CSV first; raw `.eml` files require pasting the body or uploading attachments.

Run `script/setup` after pulling migrations or dependencies, then `script/dev`.
The development async job adapter runs in the Rails process. Refresh the quote
while a run is queued. This adapter is not durable across server restarts; after
five minutes an explicit retry can replace a stuck run. Production needs a durable
job adapter and worker configuration.

Copy `.env.example` to the ignored `.env` only when adding local credentials.
`dotenv-rails` loads it in development/test. Never commit a key or paste one onto
the public bulletin. The root bundle includes csv, pdf-reader and anthropic;
Yuval owns provider implementation and activation. A missing provider/key must
not be represented as an LLM run. Rules-based processing works without a key.

Email preview uses letter_opener in development and fixed `.invalid` addresses.
Open an approved quote's **Prepare email and PDF** screen, then preview locally.
PDF and CSV attachments are generated from the same approved revision. No real
mailbox is configured, and production mail delivery is disabled.

Local browser sessions isolate prototype workspaces. This is not production
user authentication. Configure persistent storage and authentication before
considering deployment.

## Sponsor gateway

Hirsh requires Opus 5 for all Claude processes. Local sponsor configuration uses
`NICRRON_API_KEY`, `NICRRON_BASE_URL=https://api.nicrron.ai/v1` and
`NICRRON_MODEL=anthropic/claude-opus-5`. The key goes only in ignored `.env`.
Nicrron uses the OpenAI-compatible protocol; its key is not an Anthropic key.
Yuval owns the gateway provider adapter. The app remains rules-based until that
adapter is connected. A local Opus 5 smoke request returned HTTP 502 on
2026-10-10; provider availability is not yet verified.
