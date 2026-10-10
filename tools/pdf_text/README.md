# pdf_text

Pulls the text out of a PDF, for example a resume. Pure Ruby on the [`pdf-reader`](https://github.com/yob/pdf-reader) gem. No Rails needed.

## Setup

```bash
cd tools/pdf_text
bundle install
```

## Use it

From the command line:

```bash
bin/pdf-to-text path/to/resume.pdf
```

From Ruby:

```ruby
require_relative 'tools/pdf_text/lib/pdf_text'

result = PdfText.extract(File.binread('resume.pdf'))
result.text   # the cleaned text, pages joined by a blank line
result.pages  # page count
```

Every failure raises a `PdfText::Error` subclass. Its `#reason` is a plain sentence you can show a user:

| Error | When |
|-------|------|
| `EmptyFileError` | zero bytes |
| `FileTooLargeError` | over 100 MB |
| `NotAPdfError` | no `%PDF-` header in the first 1024 bytes |
| `ProtectedFileError` | password protected |
| `CorruptedOrComplexError` | the parser chokes on it |
| `UnreadableTextError` | it parses but has no text layer (a scanned image). OCR would be needed. |
| `DocumentTooLargeError` | over 200,000 characters of text |

## Limits

- Scanned PDFs (images of text) have no text to pull, so they raise `UnreadableTextError`.
- Some PDF fonts drop the spaces between words ("KennethSt.Clair" instead of "Kenneth St. Clair"). An LLM reading the text usually copes; exact string matching will not.
- Multi-column layouts come out in the order `pdf-reader` sees them, which can interleave columns.

## Tests

```bash
bundle exec rspec
```

The PDFs in `spec/fixtures/` are tiny synthetic files with made-up content.

## Where it came from

Ported from the plan-document upload in Ken's Steady Thread app. The Rails-specific parts and the other file formats (docx, xlsx, csv, html) were left behind.
