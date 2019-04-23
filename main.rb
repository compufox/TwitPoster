require 'yaml'
require 'moostodon'
require 'twitter'
require 'htmlentities'
require 'net/http'

Levels = ['public', 'unlisted', 'private', 'direct']
Decoder = HTMLEntities.new
filter = /[^\w\W]/

app_conf = YAML.load(File.read(ARGV.first || 'config.yml'))
filter = /(#{app_conf[:filter].join('|')})/ if not app_conf[:filter].nil?
level  = Levels.index(app_conf[:privacy_level]) || 0
privacy = /#{Levels[0..level].join('|')}/

$last_post = { masto: '', twit: '' }

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
  post.length > 270
end

def should_thread? post
  $last_post[:twit] if $last_post[:masto] == post.in_reply_to_id
end

# downloads all media attachments from a mastodon post
# @param post [Mastodon::Status]
# @return [Array<String>]
def download_media post
  files = []
  post.media_attachments.each_with_index do |img, i|
    files << "#{i}#{File.extname(img.url).split('?').first}"
    File.write(files[i], Net::HTTP.get(URI.parse(img.url)))
  end
  files
end

def trim_post content
  line = ''
  counter = 1
  words = content.split

  # we break before 280 just in case we go over
  while not words.empty? and not too_long?(line)
    line += " #{words.shift}"
  end

  return line.strip, words.join(' ')
end


Masto.user do |post|
  next unless post.kind_of? Mastodon::Status
  next unless post.account.acct == mastodon_user
  next unless post.visibility =~ privacy
  next unless post.attributes['reblog'].nil?
  next if not post.mentions.size.zero?

  content = Decoder.decode(post.content
                             .gsub(/(<\/p><p>|^<br\s*\/?>$)/, "\n")
                             .gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, ''))
  
  content = "cw: #{post.spoiler_text}

  #{content}" if not post.spoiler_text.empty?

  next if content =~ filter
  
  $last_post[:twit] = should_thread?(post)

  uploaded_media = false
  while not content.empty?
    trimmed, content = trim_post content

    if post.media_attachments.size.zero? and not uploaded_media
      tweet = twit_client.update(trimmed,
                                 in_reply_to_status_id: $last_post[:twit])
    else
      media = download_media post
      tweet = twit_client.update_with_media(trimmed,
                                            media,
                                            in_reply_to_status_id: $last_post[:twit])

      media.each do |file|
        File.delete(file)
      end
      uploaded_media = true
    end
      
    $last_post[:masto] = post.id
    $last_post[:twit] = tweet.id
  end
end
