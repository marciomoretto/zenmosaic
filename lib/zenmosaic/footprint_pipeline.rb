# frozen_string_literal: true

require "json"
require "fileutils"

module Zenmosaic
  module FootprintPipeline
    FILENAME_CANDIDATES = %w[filename file_name image_name].freeze
    CAMERA_MODEL_CANDIDATES = %w[camera_model camera_model_name model].freeze
    LATITUDE_CANDIDATES = %w[dji_gps_latitude dji_gpslatitude gps_latitude].freeze
    LONGITUDE_CANDIDATES = %w[dji_gps_longitude dji_gpslongitude gps_longitude].freeze
    GIMBAL_YAW_CANDIDATES = %w[dji_gimbal_yaw_degree dji_gimbalyawdegree dji_gimbal_yaw dji_gimbalyaw GimbalYawDegree].freeze
    FLIGHT_YAW_CANDIDATES = %w[dji_flight_yaw_degree dji_flightyawdegree flightyawdegree FlightYawDegree].freeze
    GIMBAL_PITCH_CANDIDATES = %w[dji_gimbal_pitch_degree dji_gimbalpitchdegree dji_gimbal_pitch dji_gimbalpitch GimbalPitchDegree].freeze
    REL_ALTITUDE_CANDIDATES = %w[dji_relative_altitude dji_relativealtitude relative_altitude].freeze

    module_function

    def build_hourly(profile_name:, profile:, folders:, export_geojson: false, output_dir: nil,
                     pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      normalized_profile = normalize_profile(profile)
      fov = compute_fov(
        fov_diag_deg: normalized_profile[:fov_diag_deg],
        aspect_ratio: normalized_profile[:aspect_ratio]
      )

      projector = CoordinateTransformer.build(normalized_profile[:target_crs])

      folder_results = Array(folders).map do |folder_data|
        process_folder(
          folder_data: folder_data,
          profile_name: profile_name,
          profile: normalized_profile,
          projector: projector,
          fov_width_rad: fov[:fov_width_rad],
          fov_height_rad: fov[:fov_height_rad],
          export_geojson: export_geojson,
          output_dir: output_dir,
          pitch_tolerance_deg: Float(pitch_tolerance_deg),
          default_height_agl_m: Float(default_height_agl_m)
        )
      end

      {
        profile_name: profile_name,
        target_crs: normalized_profile[:target_crs],
        fov_diag_deg: normalized_profile[:fov_diag_deg],
        fov_width_rad: fov[:fov_width_rad],
        fov_height_rad: fov[:fov_height_rad],
        folders: folder_results
      }
    end

    def process_folder(folder_data:, profile_name:, profile:, projector:, fov_width_rad:, fov_height_rad:,
                       export_geojson:, output_dir:, pitch_tolerance_deg:, default_height_agl_m:)
      folder_name = safe_string(fetch_hash_value(folder_data, :folder, "folder"))
      folder_path = fetch_hash_value(folder_data, :folder_path, "folder_path")
      input_rows = Array(fetch_hash_value(folder_data, :rows, "rows")).map { |row| symbolize_keys(row) }

      result = base_folder_result(folder_name: folder_name, folder_path: folder_path, input_count: input_rows.length)

      if input_rows.empty?
        result[:warnings] << "Nenhuma imagem encontrada nesta pasta"
        return result
      end

      working_rows = enrich_filename(input_rows)

      camera_model_col = find_first_column(working_rows, CAMERA_MODEL_CANDIDATES, required: false)
      if camera_model_col
        result[:camera_models] = working_rows.map { |row| safe_string(row[camera_model_col]) }.reject(&:empty?).uniq
      end

      working_rows.each do |row|
        row[:fov_width_rad] = fov_width_rad
        row[:fov_height_rad] = fov_height_rad
        row[:horario] = folder_name
      end

      lat_col = find_first_column(working_rows, LATITUDE_CANDIDATES, required: true)
      lon_col = find_first_column(working_rows, LONGITUDE_CANDIDATES, required: true)
      result[:used_columns][:latitude] = lat_col.to_s
      result[:used_columns][:longitude] = lon_col.to_s

      working_rows.each do |row|
        row[:gps_latitude] = to_float_or_nil(row[lat_col])
        row[:gps_longitude] = to_float_or_nil(row[lon_col])
      end

      working_rows, dropped_invalid_gps = partition_rows(working_rows) do |row|
        row[:gps_latitude] && row[:gps_longitude]
      end
      result[:dropped_counts][:invalid_gps] = dropped_invalid_gps

      if working_rows.empty?
        result[:warnings] << "Nenhuma linha com GPS valido"
        return result
      end

      gimbal_pitch_col = find_first_column(working_rows, GIMBAL_PITCH_CANDIDATES, required: true)
      result[:used_columns][:gimbal_pitch] = gimbal_pitch_col.to_s

      working_rows.each do |row|
        row[:gimbal_pitch_deg] = to_float_or_nil(row[gimbal_pitch_col])
      end

      working_rows, dropped_non_zenital = partition_rows(working_rows) do |row|
        pitch = row[:gimbal_pitch_deg]
        pitch && ((pitch.abs - 90.0).abs <= pitch_tolerance_deg)
      end
      result[:dropped_counts][:non_zenital] = dropped_non_zenital

      if working_rows.empty?
        result[:warnings] << "Nenhuma foto zenital restante neste horario"
        return result
      end

      gimbal_yaw_col = find_first_column(working_rows, GIMBAL_YAW_CANDIDATES, required: true)
      flight_yaw_col = find_first_column(working_rows, FLIGHT_YAW_CANDIDATES, required: true)
      result[:used_columns][:gimbal_yaw] = gimbal_yaw_col.to_s
      result[:used_columns][:flight_yaw] = flight_yaw_col.to_s

      working_rows.each do |row|
        row[:gimbal_yaw_deg] = to_float_or_nil(row[gimbal_yaw_col])
        row[:flight_yaw_deg] = to_float_or_nil(row[flight_yaw_col])
      end

      working_rows, dropped_missing_yaw = partition_rows(working_rows) do |row|
        row[:gimbal_yaw_deg] && row[:flight_yaw_deg]
      end
      result[:dropped_counts][:missing_yaw] = dropped_missing_yaw

      if working_rows.empty?
        result[:warnings] << "Nenhuma foto restante com yaw valido"
        return result
      end

      working_rows.each do |row|
        row[:rotation_offset_deg] = row[:gimbal_yaw_deg] - row[:flight_yaw_deg]
        row[:rotation_deg] = row[:rotation_offset_deg] - row[:gimbal_yaw_deg]
      end

      rel_alt_col = find_first_column(working_rows, REL_ALTITUDE_CANDIDATES, required: false)
      result[:used_columns][:relative_altitude] = rel_alt_col.to_s if rel_alt_col

      if rel_alt_col
        working_rows.each do |row|
          row[:relative_altitude_m] = to_float_or_nil(row[rel_alt_col])
          row[:height_agl_m] = row[:relative_altitude_m] && (row[:relative_altitude_m] + profile[:agl_offset_m])
        end

        working_rows, dropped_missing_height = partition_rows(working_rows) { |row| row[:height_agl_m] }
        result[:dropped_counts][:missing_height] = dropped_missing_height

        expected_rel = profile[:expected_relative_altitude_m]
        if expected_rel
          diffs = working_rows.map { |row| (row[:relative_altitude_m] - expected_rel).abs }
          tolerance = profile[:alt_tolerance_m]

          ok_count = diffs.count { |diff| diff <= tolerance }
          out_count = diffs.length - ok_count

          result[:altitude_check] = {
            expected_relative_altitude_m: expected_rel,
            tolerance_m: tolerance,
            ok_count: ok_count,
            out_of_range_count: out_count
          }
        end
      else
        working_rows.each do |row|
          row[:relative_altitude_m] = nil
          row[:height_agl_m] = default_height_agl_m + profile[:agl_offset_m]
        end

        result[:warnings] << "Altitude relativa DJI nao encontrada; usando #{default_height_agl_m}m"
      end

      if working_rows.empty?
        result[:warnings] << "Nenhuma foto restante com altura AGL valida"
        return result
      end

      projected_rows = []
      projection_errors = 0

      working_rows.each do |row|
        begin
          projected_rows << row.merge(
            footprint_polygon_and_dims(
              row,
              projector: projector,
              fov_width_rad: fov_width_rad,
              fov_height_rad: fov_height_rad
            )
          )
        rescue StandardError
          projection_errors += 1
        end
      end

      result[:dropped_counts][:projection_errors] = projection_errors
      result[:rows] = projected_rows
      result[:images_count] = projected_rows.length

      if projected_rows.empty?
        result[:warnings] << "Nenhuma geometria de footprint foi gerada"
        return result
      end

      result[:bounds] = bounds_from_rows(projected_rows)
      result[:sample_centers_xy] = projected_rows.first(5).map do |row|
        {
          filename: row[:filename],
          x: row[:x0],
          y: row[:y0]
        }
      end

      result[:expected_footprint_70m_m] = footprint_size_at_height(
        fov_width_rad: fov_width_rad,
        fov_height_rad: fov_height_rad,
        height_m: 70.0
      )

      if export_geojson
        target_dir = resolve_geojson_output_dir(output_dir: output_dir, folder_path: folder_path)
        result[:geojson_path] = export_folder_geojson(
          rows: projected_rows,
          profile_name: profile_name,
          folder_name: folder_name,
          target_crs: profile[:target_crs],
          output_dir: target_dir
        )
      end

      result
    rescue Error => error
      result[:error] = error.message
      result
    end

    def normalize_profile(profile)
      profile_hash = symbolize_keys(profile || {})
      raise Error, "profile deve ser um Hash" unless profile_hash.is_a?(Hash)

      fov_diag = to_float_or_nil(profile_hash[:fov_diag_deg])
      raise Error, "profile.fov_diag_deg deve ser numerico" if fov_diag.nil?

      aspect_ratio = profile_hash[:aspect_ratio]
      unless aspect_ratio.is_a?(Array) && aspect_ratio.length == 2
        raise Error, "profile.aspect_ratio deve ser um Array com 2 valores"
      end

      width_ar = to_float_or_nil(aspect_ratio[0])
      height_ar = to_float_or_nil(aspect_ratio[1])
      raise Error, "profile.aspect_ratio invalido" if width_ar.nil? || height_ar.nil? || width_ar <= 0 || height_ar <= 0

      target_crs = safe_string(profile_hash[:target_crs])
      raise Error, "profile.target_crs deve ser informado" if target_crs.empty?

      {
        fov_diag_deg: fov_diag,
        aspect_ratio: [width_ar, height_ar],
        target_crs: target_crs,
        agl_offset_m: to_float_or_nil(profile_hash[:agl_offset_m]) || 0.0,
        expected_relative_altitude_m: to_float_or_nil(profile_hash[:expected_relative_altitude_m]),
        alt_tolerance_m: to_float_or_nil(profile_hash[:alt_tolerance_m]) || 5.0
      }
    end

    def compute_fov(fov_diag_deg:, aspect_ratio:)
      width_ar, height_ar = aspect_ratio
      diag = Math.hypot(width_ar, height_ar)

      alpha = (fov_diag_deg / 2.0) * Math::PI / 180.0
      fov_w_rad = 2.0 * Math.atan((width_ar / diag) * Math.tan(alpha))
      fov_h_rad = 2.0 * Math.atan((height_ar / diag) * Math.tan(alpha))

      {
        fov_width_rad: fov_w_rad,
        fov_height_rad: fov_h_rad
      }
    end

    def footprint_polygon_and_dims(row, projector:, fov_width_rad:, fov_height_rad:)
      x0, y0 = projector.call(row[:gps_longitude], row[:gps_latitude])
      height = Float(row[:height_agl_m])

      half_w = height * Math.tan(fov_width_rad / 2.0)
      half_h = height * Math.tan(fov_height_rad / 2.0)

      local_corners = [
        [-half_w, -half_h],
        [half_w, -half_h],
        [half_w, half_h],
        [-half_w, half_h]
      ]

      theta = Float(row[:rotation_deg]) * Math::PI / 180.0
      cos_t = Math.cos(theta)
      sin_t = Math.sin(theta)

      ring = local_corners.map do |dx, dy|
        rx = dx * cos_t - dy * sin_t
        ry = dx * sin_t + dy * cos_t
        [x0 + rx, y0 + ry]
      end

      ring << ring.first

      {
        geometry: {
          type: "Polygon",
          coordinates: [ring]
        },
        x0: x0,
        y0: y0,
        half_w: half_w,
        half_h: half_h
      }
    end

    def export_folder_geojson(rows:, profile_name:, folder_name:, target_crs:, output_dir:)
      FileUtils.mkdir_p(output_dir)

      safe_profile = safe_file_fragment(profile_name)
      safe_folder = safe_file_fragment(folder_name)
      path = File.join(output_dir, "drone_footprints_#{safe_profile}_#{safe_folder}.geojson")

      geojson = {
        type: "FeatureCollection",
        profile: profile_name,
        folder: folder_name,
        target_crs: target_crs,
        features: rows.map { |row| row_to_feature(row) }
      }

      File.write(path, JSON.pretty_generate(geojson))
      path
    end

    def row_to_feature(row)
      {
        type: "Feature",
        geometry: row[:geometry],
        properties: {
          filename: row[:filename],
          folder: row[:folder],
          gps_latitude: row[:gps_latitude],
          gps_longitude: row[:gps_longitude],
          height_agl_m: row[:height_agl_m],
          gimbal_pitch_deg: row[:gimbal_pitch_deg],
          gimbal_yaw_deg: row[:gimbal_yaw_deg],
          flight_yaw_deg: row[:flight_yaw_deg],
          rotation_deg: row[:rotation_deg],
          x0: row[:x0],
          y0: row[:y0],
          half_w: row[:half_w],
          half_h: row[:half_h]
        }
      }
    end

    def resolve_geojson_output_dir(output_dir:, folder_path:)
      output_text = safe_string(output_dir)
      return File.expand_path(output_text) unless output_text.empty?

      folder_text = safe_string(folder_path)
      return File.expand_path(folder_text) unless folder_text.empty?

      File.expand_path(".")
    end

    def footprint_size_at_height(fov_width_rad:, fov_height_rad:, height_m:)
      h = Float(height_m)

      {
        width_m: 2.0 * h * Math.tan(fov_width_rad / 2.0),
        height_m: 2.0 * h * Math.tan(fov_height_rad / 2.0)
      }
    end

    def bounds_from_rows(rows)
      points = rows.flat_map { |row| row.dig(:geometry, :coordinates, 0) || [] }
      return nil if points.empty?

      xs = points.map { |xy| xy[0] }
      ys = points.map { |xy| xy[1] }
      [xs.min, ys.min, xs.max, ys.max]
    end

    def enrich_filename(rows)
      filename_col = find_first_column(rows, FILENAME_CANDIDATES, required: false)

      rows.each_with_index.map do |row, index|
        current = filename_col ? safe_string(row[filename_col]) : ""
        row[:filename] = current.empty? ? format("img_%05d", index) : current
        row
      end
    end

    def find_first_column(rows, candidates, required: false)
      keys = rows.flat_map(&:keys).uniq
      return nil if keys.empty? && !required

      key_index = keys.each_with_object({}) do |key, map|
        map[normalize_column_name(key)] ||= key
      end

      candidates.each do |candidate|
        match = key_index[normalize_column_name(candidate)]
        return match unless match.nil?
      end

      raise Error, "Nenhuma das colunas encontradas: #{candidates.inspect}" if required

      nil
    end

    def normalize_column_name(name)
      name.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end

    def partition_rows(rows)
      kept = []
      dropped = 0

      rows.each do |row|
        if yield(row)
          kept << row
        else
          dropped += 1
        end
      end

      [kept, dropped]
    end

    def fetch_hash_value(hash, *keys)
      keys.each do |key|
        return hash[key] if hash.respond_to?(:key?) && hash.key?(key)

        string_key = key.to_s
        return hash[string_key] if hash.respond_to?(:key?) && hash.key?(string_key)

        symbol_key = key.to_sym
        return hash[symbol_key] if hash.respond_to?(:key?) && hash.key?(symbol_key)
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

    def base_folder_result(folder_name:, folder_path:, input_count:)
      {
        folder: folder_name,
        folder_path: folder_path,
        input_count: input_count,
        images_count: 0,
        camera_models: [],
        used_columns: {},
        dropped_counts: {
          invalid_gps: 0,
          non_zenital: 0,
          missing_yaw: 0,
          missing_height: 0,
          projection_errors: 0
        },
        altitude_check: nil,
        expected_footprint_70m_m: nil,
        sample_centers_xy: [],
        bounds: nil,
        rows: [],
        geojson_path: nil,
        warnings: [],
        error: nil
      }
    end
  end
end
