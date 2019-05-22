# coding: utf-8
require 'yaml'
require 'moostodon'
require 'twitter'
require 'htmlentities'
require 'net/http'


class CrossPoster
  Levels = ['public', 'unlisted', 'private', 'direct']
  Decoder = HTMLEntities.new
  MaxRetries = 10
  MaxTweetLength = 250
  ValidMediaTypes = [ '.png', '.gif', '.mp4', '.jpg', '.jpeg' ]

  attr :filter,
       :privacy,
       :ids,
       :twitter,
       :mastodon,
       :masto_user,
       :max_ids,
       :crosspost_mentions

  def initialize
    raise 'No config file found' unless File.exists?(ARGV.first || 'config.yml')
    app_conf = YAML.load_file(ARGV.first || 'config.yml')
    
    @filter = nil
    @filter = /(#{app_conf[:filter].join('|')})/ if not app_conf[:filter].nil?

    level  = Levels.index(app_conf[:privacy_level]) || 0
    @privacy = /#{Levels[0..level].join('|')}/

    @max_ids = app_conf[:max_ids] || 200
    
    @crosspost_mentions = app_conf[:crosspost_mentions] || false
    
    @ids = (File.exists?('id_store.yml') ? YAML.load_file('id_store.yml') : {})
    @ids = {} if @ids.nil?

    # set up the twitter client
    @twitter = Twitter::REST::Client.new do |config|
      config.consumer_key = app_conf[:twitter_consumer_key]
      config.consumer_secret = app_conf[:twitter_consumer_secret]
      config.access_token = app_conf[:twitter_access_token]
      config.access_token_secret = app_conf[:twitter_token_secret]
    end
    
    mastodon_url = app_conf[:mastodon_url]
    mastodon_url.chop! if mastodon_url.end_with? '/'
    mastodon_token = app_conf[:mastodon_token]

    # use the mastodon rest client to get some data about our user
    rest = Mastodon::REST::Client.new(bearer_token: mastodon_token,
                                      base_url: mastodon_url)
    # get our authed account
    @masto_user = rest.verify_credentials

    # make sure we have the correct url for the streaming interface
    streaming_url = rest.instance
                      .attributes['urls']['streaming_api']
                      .gsub(/^wss?/, 'https')
    @mastodon = Mastodon::Streaming::Client.new(bearer_token: mastodon_token,
                                                base_url: streaming_url)
  end

  # Checks if the post content is too long
  # @param content [String]
  # @return [Boolean]
  def too_long? content
    content.length > MaxTweetLength
  end
  
  # downloads all media attachments from a mastodon post
  # @param post [Mastodon::Status]
  # @return [Array<String>]
  def download_media post
    files = []
    post.media_attachments.each_with_index do |img, i|
      extension = File.extname(img.url).split('?').first
      if ValidMediaTypes.include? extension
        files << "#{i}#{extension}"
        File.write(files[i], Net::HTTP.get(URI.parse(img.url)))
      end
    end
    files
  end

  # saves the id hash
  def save_ids
    File.write('id_store.yml', @ids.to_yaml)
  end

  # keeps the most recent 200 ids
  def cull_old_ids
    saved_ids = @ids.keys.reverse.take(@max_ids)
    @ids.select! do |k, v|
      saved_ids.include? k
    end
  end

  # Trims the post content down
  #  returns the current post along with the rest of the supplied words
  # @param content [String]
  # @return [Array<String, Array<String>>] 
  def trim_post content
    line = ''
    counter = 1
    words = content.split(/ /)
    
    # we break before 280 (@250) just in case we go over
    while not words.empty? and not too_long?(line)
      line += " #{words.shift}"
    end
    
    return line.strip, words.join(' ')
  end

  # posts a mastodon status to twitter
  # @param toot [Mastodon::Status]
  def crosspost toot
    content = Decoder.decode(toot.content
                               .gsub(/(<\/p><p>|<br\s*\/?>)/, "\n")
                               .gsub(/<("[^"]*"|'[^']*'|[^'">])*>/, '')
                               .gsub('*', '＊'))
    
    # replaces any mention in the post with the account's URL
    unless toot.mentions.size.zero?
      toot.mentions.each do |ment|
        content.gsub!("@#{ment.acct.split('@').first}", ment.url)
      end
    end
    
    return if not @filter.nil? and content =~ @filter
    return if content.empty? and toot.media_attachments.size.zero?
    
    content = "cw: #{toot.spoiler_text}\n\n#{content}" unless toot.spoiler_text.empty?
    
    uploaded_media = false
    
    @retries = 0
    thread_ids = []
    while not content.empty? or
         (not toot.media_attachments.size.zero? and not uploaded_media)
      trimmed, content = trim_post(content)
      tweet = nil
      reply_id = thread_ids.last || @ids[toot.in_reply_to_id]
      
      while @retries < MaxRetries and tweet.nil?
        begin
          if toot.media_attachments.size.zero? or uploaded_media
            tweet = @twitter.update(trimmed,
                                    in_reply_to_status_id: reply_id)
          else
            media = download_media(toot).collect do |file|
              file.end_with?('.mp4') ?
                               File.open(file, 'r') :
                               file
            end
            tweet = @twitter.update_with_media(trimmed,
                                               media,
                                               in_reply_to_status_id: reply_id)

            uploaded_media = true
          end
        rescue Twitter::Error::UnprocessableEntity,
               Twitter::Error::RequestEntityTooLarge,
               Twitter::Error::BadRequest => err
          # if we're at the last try to upload media
          #  we see if we have room to add the link to the
          #  media, otherwise we tack the links onto the end
          #  of 'content' so it'll get threaded onto the op
          # if we're not on the last try we just add 1 and
          #  print the error out like normal
          if @retries + 1 >= MaxRetries
            toot.media_attachments.each do |media|
              if trimmed.length + media.url.length <= MaxTweetLength
                trimmed << " #{media.url}"
              else
                content << media.url
              end
            end
            
            # this skips trying to upload the media anymore
            uploaded_media = true
          else
            @retries += 1
            pp err
          end
        rescue Twitter::Error => err
          @retries += 1
          pp err
        rescue StandardError => err
          pp err
        ensure
          # make sure we clean up any downloaded files
          unless media.nil? or media.empty?
            media.each do |file|
              file.close if File.basename(file).end_with? '.mp4'
              File.delete(file)
            end
          end
        end
      end
      
      break if @retries >= MaxRetries or tweet.nil?

      thread_ids << tweet.id
      @ids[toot.id] = tweet.id 
      cull_old_ids
      save_ids
    end
  end

  # Run the crossposter
  def run
    # TODO: put this in a separate thread?
    # TODO: implement a simple queue system
    loop do
      begin
        @mastodon.user do |post|
          case post
          when Mastodon::Streaming::DeletedStatus
            id = post.id.to_s
            if @ids.has_key? id
              @twitter.destroy_status @ids.delete id
            end
            save_ids

          when Mastodon::Status
            next unless post.account.acct == @masto_user.acct
            next unless post.visibility =~ @privacy
            next unless (post.in_reply_to_account_id.nil? or
                         post.in_reply_to_account_id == @masto_user.id)
            next if (not post.mentions.size.zero?) and
              @crosspost_mentions

            if post.attributes['reblog'].nil?
              crosspost post
            elsif post.reblog.account.acct == @masto_user.acct and
                 @ids.has_key?(post.reblog.id)
              @twitter.retweet @ids[post.reblog.id]
            end
          end
        end
      rescue StandardError => err
        pp err
      end
    end
  end
end
