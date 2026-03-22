# frozen_string_literal: true

require "pathname"

module Zenmosaic
  class ProcessingRequest
    attr_reader :profile_name, :paths, :profile

    def initialize(profile_name:, paths:, profile:, images_root: nil)
      @profile_name = profile_name.to_s.strip
      @paths = Array(paths)
      @profile = profile
      @images_root = images_root

      validate!
      @paths = resolve_paths
    end

    def to_h
      {
        profile_name: profile_name,
        input_paths: paths,
        profile: profile
      }
    end

    private

    def validate!
      raise Error, "profile deve ser informado" if profile_name.empty?
      raise Error, "paths deve ser um Array" unless @paths.is_a?(Array)
      raise Error, "paths deve conter ao menos um arquivo" if @paths.empty?
      raise Error, "profile_data deve ser um Hash" unless @profile.is_a?(Hash)
    end

    def resolve_paths
      base_root = @images_root.to_s.strip

      @paths.map do |raw_path|
        clean_path = raw_path.to_s.strip
        next if clean_path.empty?

        pathname = Pathname.new(clean_path)
        resolved = if pathname.absolute? || base_root.empty?
                     pathname
                   else
                     Pathname.new(base_root).join(pathname)
                   end

        resolved.expand_path.to_s
      end.compact.uniq
    end
  end
end
