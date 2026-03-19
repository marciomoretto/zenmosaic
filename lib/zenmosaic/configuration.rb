# frozen_string_literal: true

require_relative "default_profiles"

module Zenmosaic
  class Configuration
    attr_accessor :enabled, :label_prefix, :profiles, :default_profile, :images_root

    def initialize
      @enabled = true
      @label_prefix = "Zen"
      @profiles = DefaultProfiles.all
      @default_profile = "air3s_wide_70m_rj"
      @images_root = nil
    end
  end
end
