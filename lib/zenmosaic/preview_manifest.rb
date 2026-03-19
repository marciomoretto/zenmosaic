# frozen_string_literal: true

require "json"
require "pathname"
require "fileutils"

module Zenmosaic
  module PreviewManifest
    DEFAULT_MAX_IMAGES_TO_PLOT = 12
    DEFAULT_DOWNSAMPLE = 6
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .tif .tiff].freeze

    module_function

    def build_hourly(footprints_result:, images_base_dir:, max_images_to_plot: DEFAULT_MAX_IMAGES_TO_PLOT,
                     downsample: DEFAULT_DOWNSAMPLE, output_dir: nil, export_manifest: false)
      folders = Array(fetch_hash_value(footprints_result, :folders, "folders"))
      profile_name = fetch_hash_value(footprints_result, :profile_name, "profile_name")

      folder_results = folders.map do |folder|
        build_folder_preview(
          folder: symbolize_keys(folder),
          images_base_dir: images_base_dir,
          max_images_to_plot: Integer(max_images_to_plot),
          downsample: Integer(downsample),
          profile_name: profile_name,
          output_dir: output_dir,
          export_manifest: export_manifest
        )
      end

      {
        profile_name: profile_name,
        max_images_to_plot: Integer(max_images_to_plot),
        downsample: Integer(downsample),
        folders: folder_results
      }
    end

    def build_folder_preview(folder:, images_base_dir:, max_images_to_plot:, downsample:, profile_name:, output_dir:, export_manifest:)
      folder_name = safe_string(fetch_hash_value(folder, :folder, "folder"))
      folder_rows = Array(fetch_hash_value(folder, :rows, "rows"))

      folder_result = {
        folder: folder_name,
        images_dir: File.expand_path(File.join(images_base_dir.to_s, folder_name)),
        attempted: 0,
        plotted: 0,
        failed: 0,
        skipped: 0,
        bounds: nil,
        items: [],
        warnings: [],
        manifest_path: nil
      }

      images_dir = folder_result[:images_dir]
      unless Dir.exist?(images_dir)
        folder_result[:warnings] << "Pasta de imagens nao encontrada: #{images_dir}"
        return folder_result
      end

      selected_rows = folder_rows.first(max_images_to_plot)
      folder_result[:attempted] = selected_rows.length

      plot_points_x = []
      plot_points_y = []

      selected_rows.each do |row_raw|
        row = symbolize_keys(row_raw)
        filename = safe_string(fetch_hash_value(row, :filename, "filename", :file_name, "file_name"))

        if filename.empty?
          folder_result[:failed] += 1
          folder_result[:warnings] << "Linha sem filename"
          next
        end

        filename_only = File.basename(filename)
        image_path = resolve_image_path(images_dir, filename_only)
        image_path ||= resolve_image_path(images_dir, filename)

        if image_path.nil?
          folder_result[:failed] += 1
          folder_result[:warnings] << "Nao encontrei arquivo para: #{filename}"
          next
        end

        geometry = fetch_hash_value(row, :geometry, "geometry")
        coordinates = polygon_coordinates(geometry)

        if coordinates.empty?
          folder_result[:skipped] += 1
          next
        end

        x_values = coordinates.map { |point| point[0] }
        y_values = coordinates.map { |point| point[1] }
        plot_points_x.concat(x_values)
        plot_points_y.concat(y_values)

        folder_result[:items] << {
          filename: filename,
          filename_only: filename_only,
          image_path: image_path,
          downsample: downsample,
          transform: {
            x0: to_float_or_nil(fetch_hash_value(row, :x0, "x0")),
            y0: to_float_or_nil(fetch_hash_value(row, :y0, "y0")),
            half_w: to_float_or_nil(fetch_hash_value(row, :half_w, "half_w")),
            half_h: to_float_or_nil(fetch_hash_value(row, :half_h, "half_h")),
            rotation_deg: to_float_or_nil(fetch_hash_value(row, :rotation_deg, "rotation_deg"))
          },
          geometry: geometry
        }
      end

      folder_result[:plotted] = folder_result[:items].length
      folder_result[:bounds] = compute_bounds(plot_points_x, plot_points_y)

      if export_manifest
        folder_result[:manifest_path] = export_folder_manifest(
          folder_result: folder_result,
          profile_name: profile_name,
          output_dir: output_dir
        )
      end

      folder_result
    end

    def resolve_image_path(images_dir, filename)
      images_dir_path = Pathname.new(images_dir.to_s)
      raw = filename.to_s.strip
      return nil if raw.empty?

      candidate = images_dir_path.join(raw)
      return candidate.expand_path.to_s if candidate.exist?

      stem = Pathname.new(raw).sub_ext("").to_s
      suffix = Pathname.new(raw).extname

      unless suffix.empty?
        [suffix.downcase, suffix.upcase, capitalize_extension(suffix)].each do |ext|
          candidate = images_dir_path.join("#{stem}#{ext}")
          return candidate.expand_path.to_s if candidate.exist?
        end
      end

      IMAGE_EXTENSIONS.each do |ext|
        [ext, ext.upcase].each do |variant|
          candidate = images_dir_path.join("#{stem}#{variant}")
          return candidate.expand_path.to_s if candidate.exist?
        end
      end

      nil
    end

    def polygon_coordinates(geometry)
      geom = symbolize_keys(geometry || {})
      geom_type = safe_string(fetch_hash_value(geom, :type, "type"))
      coords = fetch_hash_value(geom, :coordinates, "coordinates")

      if geom_type == "Polygon"
        return normalize_ring(Array(coords).first)
      end

      if geom_type == "MultiPolygon"
        all_polygons = Array(coords)
        biggest = all_polygons.max_by do |poly|
          ring = normalize_ring(Array(poly).first)
          polygon_area(ring)
        end
        return normalize_ring(Array(biggest).first)
      end

      []
    end

    def normalize_ring(ring)
      Array(ring).map do |point|
        next unless point.is_a?(Array) && point.length >= 2

        x = to_float_or_nil(point[0])
        y = to_float_or_nil(point[1])
        next if x.nil? || y.nil?

        [x, y]
      end.compact
    end

    def polygon_area(ring)
      return 0.0 if ring.length < 3

      area2 = 0.0
      ring.each_with_index do |(x1, y1), idx|
        x2, y2 = ring[(idx + 1) % ring.length]
        area2 += (x1 * y2) - (x2 * y1)
      end

      area2.abs / 2.0
    end

    def compute_bounds(xs, ys)
      return nil if xs.empty? || ys.empty?

      [xs.min, ys.min, xs.max, ys.max]
    end

    def export_folder_manifest(folder_result:, profile_name:, output_dir:)
      destination_dir = safe_string(output_dir)
      destination_dir = folder_result[:images_dir] if destination_dir.empty?
      destination_dir = File.expand_path(destination_dir)

      FileUtils.mkdir_p(destination_dir)

      safe_profile = safe_file_fragment(profile_name)
      safe_folder = safe_file_fragment(folder_result[:folder])
      path = File.join(destination_dir, "drone_preview_#{safe_profile}_#{safe_folder}.json")

      File.write(path, JSON.pretty_generate(folder_result))
      path
    end

    def capitalize_extension(ext)
      ext.to_s.downcase.sub(/\A\./, ".")
    end

    def safe_file_fragment(value)
      text = safe_string(value)
      text = "output" if text.empty?
      text.gsub(/[^a-zA-Z0-9._-]/, "_").gsub(".", "_")
    end

    def safe_string(value)
      value.to_s.strip
    end

    def fetch_hash_value(hash, *keys)
      keys.each do |key|
        return hash[key] if hash.respond_to?(:key?) && hash.key?(key)

        key_s = key.to_s
        return hash[key_s] if hash.respond_to?(:key?) && hash.key?(key_s)

        key_sym = key.to_sym
        return hash[key_sym] if hash.respond_to?(:key?) && hash.key?(key_sym)
      end

      nil
    end

    def symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), copy|
          symbol_key = key.is_a?(Symbol) ? key : key.to_s.to_sym
          copy[symbol_key] = symbolize_keys(val)
        end
      when Array
        value.map { |item| symbolize_keys(item) }
      else
        value
      end
    end

    def to_float_or_nil(value)
      return nil if value.nil?

      if value.is_a?(String)
        trimmed = value.strip
        return nil if trimmed.empty?
      end

      Float(value)
    rescue StandardError
      nil
    end
  end
end
