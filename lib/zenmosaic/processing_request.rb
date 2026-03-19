# frozen_string_literal: true

require "pathname"

module Zenmosaic
  class ProcessingRequest
    attr_reader :profile_name, :folder_name, :folder_path, :profile

    def initialize(profile_name:, folder_name:, profiles:, images_root: nil)
      @profile_name = profile_name.to_s.strip
      @folder_name = folder_name.to_s.strip
      @profiles = profiles || {}
      @images_root = images_root

      validate!
      @profile = @profiles.fetch(@profile_name)
      @folder_path = resolve_folder_path
    end

    def to_h
      {
        profile_name: profile_name,
        folder_name: folder_name,
        folder_path: folder_path,
        profile: profile
      }
    end

    private

    def validate!
      raise Error, "profile deve ser informado" if profile_name.empty?
      raise Error, "pasta deve ser informada" if folder_name.empty?
      raise Error, "profiles deve ser um Hash" unless @profiles.is_a?(Hash)
      raise Error, "profile '#{profile_name}' nao existe" unless @profiles.key?(profile_name)
    end

    def resolve_folder_path
      folder = Pathname.new(folder_name)
      return folder.expand_path.to_s if folder.absolute?
      return folder_name if @images_root.nil? || @images_root.to_s.strip.empty?

      Pathname.new(@images_root.to_s).join(folder).expand_path.to_s
    end
  end
end
