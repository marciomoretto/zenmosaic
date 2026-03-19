# frozen_string_literal: true

module Zenmosaic
  module DefaultProfiles
    ALL = {
      "air3s_wide_70m_rj" => {
        expected_camera_models: nil,
        fov_diag_deg: 84.0,
        aspect_ratio: [4, 3],
        agl_offset_m: 0.0,
        expected_relative_altitude_m: 70.0,
        alt_tolerance_m: 5.0,
        target_crs: "EPSG:32723"
      },
      "mavic3pro_wide_sp" => {
        expected_camera_models: nil,
        fov_diag_deg: 84.0,
        aspect_ratio: [4, 3],
        agl_offset_m: 0.0,
        alt_tolerance_m: 5.0,
        target_crs: "EPSG:32723"
      },
      "mavic3pro_mediumtele_sp" => {
        expected_camera_models: nil,
        fov_diag_deg: 35.0,
        aspect_ratio: [4, 3],
        agl_offset_m: 0.0,
        alt_tolerance_m: 5.0,
        target_crs: "EPSG:32723"
      }
    }.freeze

    module_function

    def all
      deep_dup(ALL)
    end

    def deep_dup(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), copy|
          copy[key] = deep_dup(val)
        end
      when Array
        value.map { |item| deep_dup(item) }
      else
        value
      end
    end
  end
end
