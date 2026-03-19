# frozen_string_literal: true

require "find"

module Zenmosaic
  module MetadataInventory
    module_function

    def process_subfolders(image_dir:, subfolders:)
      raise Error, "image_dir deve ser informado" if image_dir.to_s.strip.empty?
      raise Error, "subfolders deve ser um Array" unless subfolders.is_a?(Array)

      expanded_image_dir = File.expand_path(image_dir)
      raise Error, "pasta '#{expanded_image_dir}' nao existe" unless Dir.exist?(expanded_image_dir)

      subfolders.map do |subfolder_name|
        process_single_subfolder(
          image_dir: expanded_image_dir,
          subfolder_name: subfolder_name
        )
      end
    end

    def process_single_subfolder(image_dir:, subfolder_name:)
      folder_name = subfolder_name.to_s.strip
      raise Error, "nome da subpasta deve ser informado" if folder_name.empty?

      sub_dir = File.join(image_dir, folder_name)
      rows = collect_rows_for_subfolder(sub_dir, folder_name: folder_name, image_dir: image_dir)

      {
        folder: folder_name,
        folder_path: sub_dir,
        images_count: rows.length,
        rows: rows
      }
    end

    def collect_rows_for_subfolder(sub_dir, folder_name:, image_dir:)
      return [] unless Dir.exist?(sub_dir)

      rows = []
      Find.find(sub_dir) do |path|
        next unless File.file?(path)
        next unless MetadataExtractor::IMAGE_EXTENSIONS.include?(File.extname(path).downcase)

        row = {
          filename: relative_path(path, image_dir),
          folder: folder_name
        }

        row.merge!(MetadataExtractor.extract_image_metadata(path))
        rows << row
      end

      rows
    end

    def relative_path(path, base)
      path.sub(%r{^#{Regexp.escape(File.expand_path(base))}/?}, "")
    end
  end
end
