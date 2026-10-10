# frozen_string_literal: true

require_relative '../lib/pdf_text'

RSpec.describe PdfText do
  def fixture(name)
    File.binread(File.join(__dir__, 'fixtures', name))
  end

  describe '.extract' do
    it 'extracts a single page and reports pages: 1' do
      result = described_class.extract(fixture('sample.pdf'))
      expect(result.text).to include('Client: Sam Rivera')
      expect(result.pages).to eq(1)
    end

    it 'joins multiple pages with a blank-line separator' do
      result = described_class.extract(fixture('multi_page.pdf'))
      expect(result.text).to eq("Week 1 plan: Monday Squat, Wednesday Bench, Friday Deadlift.\n\n" \
                                'Week 2 plan: progress each lift by five pounds.')
      expect(result.pages).to eq(2)
    end
  end

  describe 'validation' do
    it 'raises EmptyFileError on zero bytes' do
      expect { described_class.extract('') }.to raise_error(PdfText::EmptyFileError)
    end

    it 'raises NotAPdfError when there is no %PDF- header' do
      expect { described_class.extract('just some text') }.to raise_error(PdfText::NotAPdfError)
    end

    it 'raises FileTooLargeError above MAX_BYTES' do
      stub_const('PdfText::MAX_BYTES', 10)
      expect { described_class.extract('%PDF-1.4 more than ten bytes') }
        .to raise_error(PdfText::FileTooLargeError)
    end
  end

  describe 'error mapping' do
    it 'raises UnreadableTextError when every page is blank (scanned/image-only)' do
      expect { described_class.extract(fixture('scanned.pdf')) }
        .to raise_error(PdfText::UnreadableTextError)
    end

    it 'raises CorruptedOrComplexError on a file with a header but no PDF body' do
      expect { described_class.extract(fixture('fake.pdf')) }
        .to raise_error(PdfText::CorruptedOrComplexError)
    end

    it 'maps PDF::Reader::EncryptedPDFError to ProtectedFileError' do
      allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::EncryptedPDFError, 'locked')
      expect { described_class.extract('%PDF-1.4 whatever') }
        .to raise_error(PdfText::ProtectedFileError)
    end

    it 'maps PDF::Reader::MalformedPDFError to CorruptedOrComplexError' do
      allow(PDF::Reader).to receive(:new).and_raise(PDF::Reader::MalformedPDFError, 'boom')
      expect { described_class.extract('%PDF-1.4 whatever') }
        .to raise_error(PdfText::CorruptedOrComplexError)
    end

    it 'maps an unexpected low-level error to CorruptedOrComplexError' do
      allow(PDF::Reader).to receive(:new).and_raise(ArgumentError, 'unexpected')
      expect { described_class.extract('%PDF-1.4 whatever') }
        .to raise_error(PdfText::CorruptedOrComplexError)
    end

    it 'gives every error a plain reason string' do
      expect { described_class.extract('') }
        .to raise_error(PdfText::Error) { |error| expect(error.reason).to eq('this file is empty') }
    end
  end

  describe '.clean' do
    it 'normalizes line endings, strips trailing spaces, and collapses blank runs' do
      expect(described_class.clean("a  \r\n\r\n\r\n\rb\n")).to eq("a\n\nb")
    end
  end
end
