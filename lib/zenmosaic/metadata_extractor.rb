# frozen_string_literal: true

require "exifr/jpeg"
require "exifr/tiff"

module Zenmosaic
  module MetadataExtractor
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .tif .tiff .png].freeze

    XMP_FIELDS_MAP = {
      "GpsLatitude" => :dji_gps_latitude,
      "GpsLongitude" => :dji_gps_longitude,
      "GpsAltitude" => :dji_gps_altitude,
      "RelativeAltitude" => :dji_relative_altitude,
      "FlightYawDegree" => :dji_flight_yaw_degree,
      "GimbalRollDegree" => :dji_gimbal_roll_degree,
      "GimbalPitchDegree" => :dji_gimbal_pitch_degree,
      "GimbalYawDegree" => :dji_gimbal_yaw_degree,
      "CameraRollDegree" => :dji_camera_roll_degree,
      "CameraPitchDegree" => :dji_camera_pitch_degree,
      "CameraYawDegree" => :dji_camera_yaw_degree
    }.freeze

    module_function

    def safe_get(object, key, default = nil)
      return default if object.nil?

      if object.respond_to?(:[])
        begin
          value = object[key]
          return value unless value.nil?
        rescue StandardError
          nil
        end
      end

      if object.respond_to?(key)
        begin
          value = object.public_send(key)
          return value unless value.nil?
        rescue StandardError
          nil
        end
      end

      default
    end

    def decode_if_bytes(value)
      return value unless value.is_a?(String)

      value.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").delete("\u0000").strip
    rescue StandardError
      value
    end

    def rational_to_float(rational)
      return nil if rational.nil?

      return rational.to_f if rational.is_a?(Numeric)

      if rational.is_a?(Array) && rational.length == 2
        numerator = rational[0].to_f
        denominator = rational[1].to_f
        return nil if denominator.zero?

        return numerator / denominator
      end

      if rational.respond_to?(:numerator) && rational.respond_to?(:denominator)
        denominator = rational.denominator.to_f
        return nil if denominator.zero?

        return rational.numerator.to_f / denominator
      end

      Float(rational)
    rescue StandardError
      nil
    end

    def exif_aperture_to_fnumber(aperture_value)
      apex = rational_to_float(aperture_value)
      return nil if apex.nil?

      2**(apex / 2.0)
    rescue StandardError
      nil
    end

    def exif_shutter_to_seconds(shutter_speed_value)
      apex = rational_to_float(shutter_speed_value)
      return nil if apex.nil?

      1.0 / (2**apex)
    rescue StandardError
      nil
    end

    def convert_gps_to_degrees(values, ref = nil)
      return nil if values.nil?

      numeric_value = values.is_a?(Numeric) ? values.to_f : rational_to_float(values)
      unless numeric_value.nil?
        result = numeric_value
        ref_str = decode_if_bytes(ref)
        return -result.abs if %w[S W].include?(ref_str)

        return result
      end

      points = values.is_a?(Array) ? values : nil
      return nil unless points && points.length >= 3

      degrees = rational_to_float(points[0])
      minutes = rational_to_float(points[1])
      seconds = rational_to_float(points[2])
      return nil if [degrees, minutes, seconds].any?(&:nil?)

      result = degrees + (minutes / 60.0) + (seconds / 3600.0)
      ref_str = decode_if_bytes(ref)
      result = -result if %w[S W].include?(ref_str)
      result
    rescue StandardError
      nil
    end

    def extract_exif_metadata(path)
      data = default_exif_metadata

      begin
        image = load_exif_image(path)
        data[:image_width] = fetch_value(image, :width)
        data[:image_height] = fetch_value(image, :height)

        return data unless image.exif?

        data[:camera_make] = decode_if_bytes(fetch_value(image, :make))
        data[:camera_model] = decode_if_bytes(fetch_value(image, :model))
        data[:lens_model] = decode_if_bytes(fetch_value(image, :lens_model))

        focal_length = fetch_value(image, :focal_length)
        data[:focal_length] = rational_to_float(focal_length)

        focal_length_35mm = fetch_value(image, :focal_length_in_35mm_film, :focal_length_35mm)
        data[:focal_length_35mm] = focal_length_35mm.nil? ? nil : rational_to_float(focal_length_35mm) || focal_length_35mm

        iso = fetch_value(image, :iso_speed_ratings, :photographic_sensitivity, :iso)
        data[:iso] = iso

        aperture_value = fetch_value(image, :aperture_value)
        data[:aperture_value] = rational_to_float(aperture_value)
        data[:f_number] = exif_aperture_to_fnumber(aperture_value)

        explicit_f_number = fetch_value(image, :f_number, :fnumber)
        explicit_f_number_float = rational_to_float(explicit_f_number)
        data[:f_number] = explicit_f_number_float unless explicit_f_number_float.nil?

        shutter_speed_value = fetch_value(image, :shutter_speed_value)
        data[:shutter_speed_value] = rational_to_float(shutter_speed_value)
        data[:exposure_time_seconds] = exif_shutter_to_seconds(shutter_speed_value)

        explicit_exposure_time = fetch_value(image, :exposure_time)
        explicit_exposure_time_float = rational_to_float(explicit_exposure_time)
        data[:exposure_time_seconds] = explicit_exposure_time_float unless explicit_exposure_time_float.nil?

        data[:datetime] = decode_if_bytes(fetch_value(image, :date_time, :datetime))
        data[:datetime_original] = decode_if_bytes(fetch_value(image, :date_time_original, :datetime_original))
        data[:subsec_time_original] = decode_if_bytes(fetch_value(image, :sub_sec_time_original, :subsectimeoriginal))

        gps = fetch_value(image, :gps)

        latitude = fetch_value(gps, :latitude, :gps_latitude) || fetch_value(image, :gps_latitude)
        latitude_ref = fetch_value(gps, :latitude_ref, :gps_latitude_ref) || fetch_value(image, :gps_latitude_ref)
        longitude = fetch_value(gps, :longitude, :gps_longitude) || fetch_value(image, :gps_longitude)
        longitude_ref = fetch_value(gps, :longitude_ref, :gps_longitude_ref) || fetch_value(image, :gps_longitude_ref)

        data[:gps_latitude] = convert_gps_to_degrees(latitude, latitude_ref)
        data[:gps_longitude] = convert_gps_to_degrees(longitude, longitude_ref)

        altitude = fetch_value(gps, :altitude, :gps_altitude) || fetch_value(image, :gps_altitude)
        altitude_ref = fetch_value(gps, :altitude_ref, :gps_altitude_ref) || fetch_value(image, :gps_altitude_ref)
        altitude_float = rational_to_float(altitude)
        altitude_ref_code = normalize_altitude_ref(altitude_ref)

        if altitude_float
          altitude_float = -altitude_float if altitude_ref_code == 1
          data[:gps_altitude] = altitude_float
        end

        data[:gps_altitude_ref] = altitude_ref_code.nil? ? altitude_ref : altitude_ref_code

        image_direction = fetch_value(gps, :img_direction, :image_direction, :gps_img_direction) || fetch_value(image, :gps_img_direction)
        data[:gps_img_direction] = rational_to_float(image_direction)
      rescue StandardError
        nil
      end

      data
    end

    def extract_xmp_metadata(path)
      data = default_xmp_metadata

      begin
        content = File.binread(path)
        xmp = extract_xmp_block(content)
        return data if xmp.nil?

        XMP_FIELDS_MAP.each do |xml_attr_name, output_key|
          raw = extract_xmp_attr(xmp, xml_attr_name)
          next if raw.nil?

          data[output_key] = try_float(raw)
        end
      rescue StandardError
        nil
      end

      data
    end

    def extract_image_metadata(path)
      exif = extract_exif_metadata(path)
      xmp = extract_xmp_metadata(path)

      exif.merge(xmp).merge(
        file_name: File.basename(path),
        file_path: File.expand_path(path)
      )
    end

    def extract_folder_metadata(folder_path)
      clean_folder = folder_path.to_s.strip
      raise Error, "pasta deve ser informada" if clean_folder.empty?

      expanded_folder = File.expand_path(clean_folder)
      raise Error, "pasta '#{expanded_folder}' nao existe" unless Dir.exist?(expanded_folder)

      image_paths = Dir.glob(File.join(expanded_folder, "**", "*")).select do |path|
        File.file?(path) && IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
      end.sort

      image_paths.map { |path| extract_image_metadata(path) }
    end

    def default_exif_metadata
      {
        image_width: nil,
        image_height: nil,
        camera_make: nil,
        camera_model: nil,
        lens_model: nil,
        focal_length: nil,
        focal_length_35mm: nil,
        iso: nil,
        aperture_value: nil,
        f_number: nil,
        shutter_speed_value: nil,
        exposure_time_seconds: nil,
        datetime: nil,
        datetime_original: nil,
        subsec_time_original: nil,
        gps_latitude: nil,
        gps_longitude: nil,
        gps_altitude: nil,
        gps_altitude_ref: nil,
        gps_img_direction: nil
      }
    end

    def default_xmp_metadata
      XMP_FIELDS_MAP.values.each_with_object({}) do |field, data|
        data[field] = nil
      end
    end

    def fetch_value(object, *candidates)
      candidates.each do |candidate|
        value = safe_get(object, candidate, nil)
        return value unless value.nil?
      end

      nil
    end

    def normalize_altitude_ref(value)
      return nil if value.nil?
      return value.to_i if value.is_a?(Numeric)

      str = decode_if_bytes(value).to_s.downcase
      return 1 if str == "1" || str.include?("below")
      return 0 if str == "0" || str.include?("above")

      nil
    end

    def extract_xmp_block(content)
      start_index = content.index("<x:xmpmeta".b)
      return nil if start_index.nil?

      closing_tag = "</x:xmpmeta>".b
      end_index = content.index(closing_tag, start_index)
      return nil if end_index.nil?

      content.byteslice(start_index, (end_index + closing_tag.bytesize) - start_index)
    end

    def extract_xmp_attr(xmp, attr_name)
      xmp_text = xmp.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      regex = /\b(?:[\w-]+:)?#{Regexp.escape(attr_name)}\s*=\s*["']([^"']+)["']/
      match = xmp_text.match(regex)
      match && match[1]
    end

    def try_float(raw_value)
      Float(raw_value)
    rescue StandardError
      raw_value
    end

    def load_exif_image(path)
      case File.extname(path).downcase
      when ".tif", ".tiff"
        EXIFR::TIFF.new(path)
      else
        EXIFR::JPEG.new(path)
      end
    end
  end
end
