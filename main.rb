require 'yaml'
require 'moostodon'
require 'twitter'

app_conf = YAML.load(ARGV.first || 'config.yml')
last_post = { masto: '', twit: '' }

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

def too_long? post
  content.length > 270
end

def should_thread? post
  last_post[:twit] if last_post[:masto] == post.in_reply_to_id
end

def make_post(content, options = {})
  twit_client.update(content,
                     in_reply_to_status_id: options[:reply_id])
end

def trim_post content
  line = ''
  counter = 1
  words = content.split

  # we break before 280 just in case we go over
  while too_long? line
    line += " #{words[counter]}"
    counter += 1
  end

  return line.strip, words.join(' ')
end


Masto.user do |post|
  next unless post.kind_of? Mastodon::Status
  next unless post.account.acct == mastodon_user
  next unless post.visibility =~ /public|unlisted/

  tweet = nil
  content = post.content
              .gsub(/<\/p><p>/, "\n")
              .gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')
              .gsub('&gt;', '>')
              .gsub('&lt;', '<')
              .gsub('&apos;', '\'')

  content = "cw: #{post.spoiler_text}

  #{content}"
  
  loop do
    trimmed, content = trim_post content

    last_post[:twit] = should_thread?(post)
    
    tweet = make_post(trimmed, reply_id: last_post[:twit])
      
    last_post[:masto] = post.id
    last_post[:twit] = tweet.id

    break if content.empty?
  end
end
