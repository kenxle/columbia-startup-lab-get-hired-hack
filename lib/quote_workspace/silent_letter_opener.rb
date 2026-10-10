require "letter_opener"
require "securerandom"

module QuoteWorkspace
  # Reuse Letter Opener's local files and attachment rendering, without its
  # Launchy call. Nothing in this transport opens a browser or a network socket.
  class SilentLetterOpener < LetterOpener::DeliveryMethod
    def deliver!(mail)
      validate_mail!(mail)
      recipients = Array(mail.smtp_envelope_to)
      unless recipients.all? { |address| address.to_s.match?(/\A[^\s@]+@(?:[a-z0-9-]+\.)*invalid\z/i) }
        raise ArgumentError, "Local previews require .invalid placeholder recipients"
      end

      id = SecureRandom.uuid
      location = File.join(settings.fetch(:location).to_s, id)
      FileUtils.mkdir_p(location)
      File.binwrite(File.join(location, "message.eml"), mail.encoded)
      messages = LetterOpener::Message.rendered_messages(mail, location: location,
        message_template: settings.fetch(:message_template))
      mail["X-Local-Preview-ID"] = id
      messages
    end
  end
end
