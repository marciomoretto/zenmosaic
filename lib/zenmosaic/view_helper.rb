# frozen_string_literal: true

module Zenmosaic
  module ViewHelper
    def zenmosaic_badge(label = "ready")
      return "" unless Zenmosaic.configuration.enabled

      content_tag(:span, "#{Zenmosaic.configuration.label_prefix}: #{label}", class: "zenmosaic-badge")
    end
  end
end
