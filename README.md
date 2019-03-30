# A Mastodon to Twitter crossposter

## Features

- automatically adds content warnings from mastodon posts
- creates a twitter thread when it detects a mastodon thread
- splits up long post from mastodon into a twitter thread

## Quickstart

Install dependencies

`$ bundle install`

Copy the example config and edit it to have your tokens for Twitter and Mastodon

`$ cp example.yml config.yml`

Run the script!

`$ bundle ruby main.rb`

## TODO

- add way to specify a filter for crossposting
- specify privacy level for mastodon posts
