module ApplicationHelper
  def local_email_preview_available?
    (Rails.env.development? && ActionMailer::Base.delivery_method == :letter_opener) ||
      (Rails.env.test? && ActionMailer::Base.delivery_method == :test)
  end
end
