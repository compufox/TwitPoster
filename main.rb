require 'yaml'
require 'moostodon'
require 'twitter'

app_conf = YAML.load(ARGV.first || 'config.yml')

twit_client = Twitter::REST::Client.new do |config|
  config.consumer_key = app_conf[:twitter_consumer_key]
  config.consumer_secret = app_conf[:twitter_consumer_secret]
  config.access_token = app_conf[:twitter_access_token]
  config.access_token_secret = app_conf[:twitter_token_secret]
end

mastodon_url = app_conf[:mastodon_url]
mastodon_token = app_conf[:mastodon_token]

Masto = Mastodon::Streaming::Client.new(bearer_token: mastodon_token,
                                        base_url: mastodon_url)
rest = Mastodon::REST::Client.new(bearer_token: mastodon_token,
                                  base_url: mastodon_url)
mastodon_user = rest.verify_credentials.acct

Masto.user do |post|
  next unless post.kind_of? Mastodon::Status
  next unless post.account.acct == mastodon_user
  next unless post.visibility =~ /public|unlisted/

  twit_client.update(post.content
                       .gsub(/<\/p><p>/, "\n")
                       .gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')
                       .gsub('&gt;', '>')
                       .gsub('&lt;', '<')
                       .gsub('&apos;', '\''))
end
