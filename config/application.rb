require_relative 'boot'

# require File.expand_path('../boot', __FILE__)
require 'csv'
require 'rails/all'


# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Vagrant
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
    # YAML::ENGINE.yamler = 'syck'
    config.time_zone = 'Rome'
    config.i18n.default_locale = :it
    config.autoload_paths += %W(#{config.root}/lib)
  end
end
