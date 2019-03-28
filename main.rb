require 'optparse'
require 'moostodon'
require 'twitter'

mastodon_url = ''
mastodon_token = ''

twit_client = Twitter::REST::Client.new do |config|
  OptionParser.new do |parser|

    # catch the twitter tokens we need
    parser.on('-k', '--consumer-key=KEY') do |ck|
      config.consumer_key = ck
    end
    parser.on('-s', '--consumer-secret=SECRET') do |cs|
      config.consumer_secret = cs
    end
    parser.on('-a', '--access-token=ACCESS') do |at|
      config.access_token = at
    end
    parser.on('-e', '--access-secret=SECRET') do |as|
      config.access_token_secret = as
    end

    # get our mastodon user's url
    parser.on('-u', '--mastodon-url=URL') do |mu|
      mastodon_url = mu
    end

    parser.on('-t', '--mastodon-token=TOKEN') do |mt|
      mastodon_token = mt
    end
  end.parse!
end

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
