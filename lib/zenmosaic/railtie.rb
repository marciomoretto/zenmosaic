# frozen_string_literal: true

require "active_support"
require "active_support/ordered_options"
require_relative "view_helper"

module Zenmosaic
  class Railtie < Rails::Railtie
    config.zenmosaic = ActiveSupport::OrderedOptions.new
    config.zenmosaic.enabled = true
    config.zenmosaic.label_prefix = "Zen"
    config.zenmosaic.profiles = Zenmosaic::DefaultProfiles.all
    config.zenmosaic.default_profile = "air3s_wide_70m_rj"
    config.zenmosaic.images_root = nil

    initializer "zenmosaic.configure" do |app|
      Zenmosaic.configure do |config|
        config.enabled = app.config.zenmosaic.enabled
        config.label_prefix = app.config.zenmosaic.label_prefix
        config.profiles = app.config.zenmosaic.profiles
        config.default_profile = app.config.zenmosaic.default_profile
        config.images_root = app.config.zenmosaic.images_root
      end
    end

    initializer "zenmosaic.view_helper" do
      ActiveSupport.on_load(:action_view) do
        include Zenmosaic::ViewHelper
      end
    end
  end
end
