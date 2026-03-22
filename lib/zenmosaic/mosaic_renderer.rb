# frozen_string_literal: true

require "fileutils"
require "open3"
require "shellwords"
require "tmpdir"

module Zenmosaic
  module MosaicRenderer
    DEFAULT_DOWNSAMPLE_NATIVE = 1
    DEFAULT_COMPRESSED_SCALE = 0.35
    DEFAULT_COMPRESSED_QUALITY = 88

    module_function

    def render_hourly(preview_result:, profile_name:, output_dir:, downsample_native: DEFAULT_DOWNSAMPLE_NATIVE,
                      compressed_scale: DEFAULT_COMPRESSED_SCALE, compressed_quality: DEFAULT_COMPRESSED_QUALITY)
      ensure_imagemagick_available!

      collections = Array(fetch_hash_value(preview_result, :collections, "collections"))
      destination = File.expand_path(output_dir.to_s.strip.empty? ? "." : output_dir.to_s)
      FileUtils.mkdir_p(destination)

      collection_results = collections.map do |collection|
        render_collection(
          collection: symbolize_keys(collection),
          profile_name: profile_name,
          output_dir: destination,
          downsample_native: Integer(downsample_native),
          compressed_scale: Float(compressed_scale),
          compressed_quality: Integer(compressed_quality)
        )
      end

      {
        profile_name: profile_name,
        output_dir: destination,
        collections: collection_results
      }
    end

    def render_collection(collection:, profile_name:, output_dir:, downsample_native:, compressed_scale:, compressed_quality:)
      collection_name = safe_string(fetch_hash_value(collection, :collection, "collection"))
      items = Array(fetch_hash_value(collection, :items, "items")).map { |item| symbolize_keys(item) }

      result = {
        collection: collection_name,
        attempted: items.length,
        plotted: 0,
        failed: 0,
        principal_angle_deg: 0.0,
        global_rotation_deg: 0.0,
        pixels_per_unit: nil,
        canvas_width_px: nil,
        canvas_height_px: nil,
        output_path_native: nil,
        output_path_compressed: nil,
        warnings: []
      }

      result[:discarded_paths] = []

      if items.empty?
        result[:warnings] << "Nenhum item de preview para renderizar"
        return result
      end

      center_x, center_y, principal_angle_deg, global_rotation_deg = compute_global_rotation(items)
      result[:principal_angle_deg] = principal_angle_deg
      result[:global_rotation_deg] = global_rotation_deg

      minx, miny, maxx, maxy = rotated_bounds_from_items(items, center_x: center_x, center_y: center_y, rotation_deg: global_rotation_deg)
      world_width = maxx - minx
      world_height = maxy - miny

      if world_width <= 0 || world_height <= 0
        result[:warnings] << "Bounds invalidos para renderizacao"
        return result
      end

      px_per_unit = estimate_pixels_per_unit(items)
      if px_per_unit.nil? || px_per_unit <= 0
        result[:warnings] << "Nao foi possivel estimar resolucao espacial"
        return result
      end

      scale = px_per_unit / [downsample_native, 1].max
      canvas_width_px = [1, (world_width * scale).round].max
      canvas_height_px = [1, (world_height * scale).round].max

      result[:pixels_per_unit] = px_per_unit
      result[:canvas_width_px] = canvas_width_px
      result[:canvas_height_px] = canvas_height_px

      safe_profile = safe_file_fragment(profile_name)
      safe_collection = safe_file_fragment(collection_name)
      native_path = File.join(output_dir, "mosaico_resolucao_nativa_#{safe_profile}_#{safe_collection}.png")
      compressed_path = File.join(output_dir, "mosaico_comprimido_#{safe_profile}_#{safe_collection}.jpg")

      Dir.mktmpdir("zenmosaic-render-") do |tmpdir|
        canvas_path = File.join(tmpdir, "canvas.png")
        run_command!(%W[convert -size #{canvas_width_px}x#{canvas_height_px} xc:none #{canvas_path}])

        # Processar em ordem reversa da lista para manter prioridade visual das primeiras imagens.
        items.reverse_each.with_index do |item, index|
          begin
            image_path = safe_string(fetch_hash_value(item, :image_path, "image_path"))
            unless File.exist?(image_path)
              result[:failed] += 1
              result[:warnings] << "Arquivo de imagem nao encontrado: #{image_path}"
              result[:discarded_paths] << image_path || item[:filename]
              next
            end

            transform = symbolize_keys(fetch_hash_value(item, :transform, "transform") || {})
            x0 = to_float_or_nil(fetch_hash_value(transform, :x0, "x0"))
            y0 = to_float_or_nil(fetch_hash_value(transform, :y0, "y0"))
            half_w = to_float_or_nil(fetch_hash_value(transform, :half_w, "half_w"))
            half_h = to_float_or_nil(fetch_hash_value(transform, :half_h, "half_h"))
            rotation_deg = to_float_or_nil(fetch_hash_value(transform, :rotation_deg, "rotation_deg")) || 0.0

            if [x0, y0, half_w, half_h].any?(&:nil?) || half_w <= 0 || half_h <= 0
              result[:failed] += 1
              result[:warnings] << "Transform invalido para item #{index}"
              result[:discarded_paths] << image_path || item[:filename]
              next
            end

            world_w = half_w * 2.0
            world_h = half_h * 2.0

            target_w_px = [1, (world_w * scale).round].max
            target_h_px = [1, (world_h * scale).round].max

            rotated_x, rotated_y = rotate_point(
              x0,
              y0,
              center_x: center_x,
              center_y: center_y,
              rotation_deg: global_rotation_deg
            )

            center_px_x = (rotated_x - minx) * scale
            center_px_y = (maxy - rotated_y) * scale

            combined_rotation_deg = -(rotation_deg + global_rotation_deg)

            layer_path = File.join(tmpdir, "layer_#{index}.png")

            run_command!(
              [
                "convert",
                image_path,
                "-auto-orient",
                "-alpha", "set",
                "-background", "none",
                "-filter", "Lanczos",
                "-resize", "#{target_w_px}x#{target_h_px}!",
                "-rotate", format("%.6f", combined_rotation_deg),
                layer_path
              ]
            )

            layer_w, layer_h = identify_dimensions(layer_path)

            offset_x = (center_px_x - (layer_w / 2.0)).round
            offset_y = (center_px_y - (layer_h / 2.0)).round

            run_command!(
              [
                "composite",
                "-compose", "over",
                "-geometry", format("%+d%+d", offset_x, offset_y),
                layer_path,
                canvas_path,
                canvas_path
              ]
            )

            result[:plotted] += 1
          rescue StandardError => error
            result[:failed] += 1
            result[:warnings] << "Falha ao renderizar item #{index}: #{error.message}"
            result[:discarded_paths] << image_path || item[:filename]
          end
        end

        FileUtils.cp(canvas_path, native_path)
      end

      save_compressed_copy(
        source_path: native_path,
        output_path: compressed_path,
        scale: compressed_scale,
        quality: compressed_quality
      )

      result[:output_path_native] = native_path
      result[:output_path_compressed] = compressed_path
      result[:discarded_paths] = result[:discarded_paths].compact.uniq
      result
    end

    def compute_global_rotation(items)
      centers = items.map do |item|
        transform = symbolize_keys(fetch_hash_value(item, :transform, "transform") || {})
        x = to_float_or_nil(fetch_hash_value(transform, :x0, "x0"))
        y = to_float_or_nil(fetch_hash_value(transform, :y0, "y0"))
        next if x.nil? || y.nil?

        [x, y]
      end.compact

      return [0.0, 0.0, 0.0, 0.0] if centers.empty?

      center_x = centers.sum { |pt| pt[0] } / centers.length
      center_y = centers.sum { |pt| pt[1] } / centers.length

      return [center_x, center_y, 0.0, 0.0] if centers.length < 2

      sxx = 0.0
      syy = 0.0
      sxy = 0.0

      centers.each do |x, y|
        dx = x - center_x
        dy = y - center_y
        sxx += dx * dx
        syy += dy * dy
        sxy += dx * dy
      end

      sxx /= centers.length
      syy /= centers.length
      sxy /= centers.length

      principal_angle_rad = 0.5 * Math.atan2(2.0 * sxy, sxx - syy)
      principal_angle_deg = principal_angle_rad * 180.0 / Math::PI
      global_rotation_deg = -principal_angle_deg

      [center_x, center_y, principal_angle_deg, global_rotation_deg]
    end

    def rotated_bounds_from_items(items, center_x:, center_y:, rotation_deg:)
      points = items.flat_map do |item|
        geometry = fetch_hash_value(item, :geometry, "geometry")
        polygon_coordinates(geometry).map do |x, y|
          rotate_point(x, y, center_x: center_x, center_y: center_y, rotation_deg: rotation_deg)
        end
      end

      raise Error, "Nao foi possivel calcular bounds rotacionados" if points.empty?

      xs = points.map { |pt| pt[0] }
      ys = points.map { |pt| pt[1] }
      [xs.min, ys.min, xs.max, ys.max]
    end

    def estimate_pixels_per_unit(items)
      values = items.map do |item|
        image_path = safe_string(fetch_hash_value(item, :image_path, "image_path"))
        next unless File.exist?(image_path)

        transform = symbolize_keys(fetch_hash_value(item, :transform, "transform") || {})
        half_w = to_float_or_nil(fetch_hash_value(transform, :half_w, "half_w"))
        half_h = to_float_or_nil(fetch_hash_value(transform, :half_h, "half_h"))
        next if half_w.nil? || half_h.nil? || half_w <= 0 || half_h <= 0

        width_px, height_px = identify_dimensions(image_path)

        world_w = half_w * 2.0
        world_h = half_h * 2.0
        next if world_w <= 0 || world_h <= 0

        px_per_unit_x = width_px / world_w
        px_per_unit_y = height_px / world_h
        (px_per_unit_x + px_per_unit_y) / 2.0
      end.compact

      return nil if values.empty?

      median(values)
    end

    def save_compressed_copy(source_path:, output_path:, scale:, quality:)
      pct = (Float(scale) * 100.0)
      pct = 1.0 if pct <= 0

      run_command!(
        [
          "convert",
          source_path,
          "-filter", "Lanczos",
          "-resize", format("%.2f%%", pct),
          "-quality", Integer(quality).to_s,
          "-strip",
          output_path
        ]
      )
    end

    def identify_dimensions(path)
      stdout, = run_command!(%W[identify -format %w,%h #{path}])
      width_text, height_text = stdout.strip.split(",", 2)
      [Integer(width_text), Integer(height_text)]
    end

    def polygon_coordinates(geometry)
      geom = symbolize_keys(geometry || {})
      geom_type = safe_string(fetch_hash_value(geom, :type, "type"))
      coords = fetch_hash_value(geom, :coordinates, "coordinates")

      if geom_type == "Polygon"
        return normalize_ring(Array(coords).first)
      end

      if geom_type == "MultiPolygon"
        polygons = Array(coords)
        largest = polygons.max_by do |poly|
          ring = normalize_ring(Array(poly).first)
          polygon_area(ring)
        end
        return normalize_ring(Array(largest).first)
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

    def rotate_point(x, y, center_x:, center_y:, rotation_deg:)
      theta = Float(rotation_deg) * Math::PI / 180.0
      cos_t = Math.cos(theta)
      sin_t = Math.sin(theta)

      dx = Float(x) - center_x
      dy = Float(y) - center_y

      [
        center_x + (dx * cos_t - dy * sin_t),
        center_y + (dx * sin_t + dy * cos_t)
      ]
    end

    def median(values)
      sorted = values.sort
      mid = sorted.length / 2
      if sorted.length.odd?
        sorted[mid]
      else
        (sorted[mid - 1] + sorted[mid]) / 2.0
      end
    end

    def run_command!(args)
      stdout, stderr, status = Open3.capture3(*args)
      return [stdout, stderr] if status.success?

      raise Error, "Comando falhou (#{args.join(' ')}): #{stderr.to_s.strip}"
    end

    def ensure_imagemagick_available!
      return if command_available?("convert") && command_available?("identify") && command_available?("composite")

      raise Error, "ImageMagick nao disponivel (convert/identify/composite)"
    end

    def command_available?(cmd)
      path_dirs = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
      path_dirs.any? do |dir|
        candidate = File.join(dir, cmd)
        File.file?(candidate) && File.executable?(candidate)
      end
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

    def safe_string(value)
      value.to_s.strip
    end

    def safe_file_fragment(value)
      text = safe_string(value)
      text = "output" if text.empty?
      text.gsub(/[^a-zA-Z0-9._-]/, "_").gsub(".", "_")
    end
  end
end
