# A Mastodon to Twitter crossposter

## Features

- automatically adds content warnings from mastodon posts
- creates a twitter thread when it detects a mastodon thread
- splits up long post from mastodon into a twitter thread
- optional filter to selectively crosspost 
- specify lowest level of privacy to crosspost (see config.yml.example for more detail)

## Quickstart

Install dependencies

`$ bundle install`

Copy the example config and edit it to have your tokens for Twitter and Mastodon

`$ cp config.yml.example config.yml`

Run the script!

`$ bundle ruby main.rb`

