module SourceDocumentHelper
  def source_document_phrases(line)
    return [] unless line

    evidence = line.evidence.is_a?(Hash) ? line.evidence.values : []
    [line.original_text, *evidence.filter_map { |entry| entry["text"] if entry.is_a?(Hash) },
      *Array(line.compliance).filter_map { |entry| entry["evidence"] if entry.is_a?(Hash) }].compact
  end
end
