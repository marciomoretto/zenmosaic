# frozen_string_literal: true

module Zenmosaic
  class Configuration
    attr_accessor :enabled, :label_prefix, :images_root

    def initialize
      @enabled = true
      @label_prefix = "Zen"
      @images_root = nil
    end
  end
end
