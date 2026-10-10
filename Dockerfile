# Hosted hackathon demo image (Railway). Runs the app in development mode so the
# demo behaves exactly as it does locally: per-session seeded demo workspace,
# in-app local email inbox (letter_opener), in-process jobs, model gateway off.
FROM ruby:3.4.11-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libyaml-dev pkg-config git && \
    apt-get clean

WORKDIR /app

ENV RAILS_ENV=development \
    BUNDLE_WITHOUT="" \
    BUNDLE_JOBS=4 \
    HOSTED_DEMO=1 \
    RFQ_LIVE_MODELS=0

RUN gem install bundler -v 2.4.19 --no-document

COPY Gemfile Gemfile.lock ./
# The committed lockfile lists only macOS and Windows platforms; add Linux in the image.
RUN bundle _2.4.19_ lock --add-platform x86_64-linux aarch64-linux && \
    bundle _2.4.19_ install

COPY . .

# Keep the development secret on the persistent volume with the SQLite database,
# so sessions survive restarts. Local email previews stay in tmp/letter_opener:
# the inbox refuses symlinked paths, so they reset when the container restarts.
RUN mkdir -p storage tmp log && ln -sfn /app/storage/local_secret.txt /app/tmp/local_secret.txt

EXPOSE 3000
CMD ["script/railway-start"]
