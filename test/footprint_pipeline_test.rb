# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class FootprintPipelineTest < Minitest::Test
  def profile
    Zenmosaic::DefaultProfiles.all.fetch("air3s_wide_70m_rj")
  end

  def test_build_hourly_generates_footprints_and_geojson
    Dir.mktmpdir do |dir|
      result = Zenmosaic::FootprintPipeline.build_hourly(
        profile_name: "air3s_wide_70m_rj",
        profile: profile,
        collections: [
          {
            collection: "10.00",
            collection_path: dir,
            rows: [
              {
                filename: "10.00/a.jpg",
                dji_gps_latitude: -23.0,
                dji_gps_longitude: -45.0,
                dji_gimbal_pitch_degree: -90.0,
                dji_gimbal_yaw_degree: 10.0,
                dji_flight_yaw_degree: 2.0,
                dji_relative_altitude: 70.0
              }
            ]
          }
        ],
        export_geojson: true,
        output_dir: dir
      )

      assert_equal "air3s_wide_70m_rj", result[:profile_name]
      assert_equal "EPSG:32723", result[:target_crs]
      assert result[:fov_width_rad] > 0
      assert result[:fov_height_rad] > 0

      collection = result[:collections].first
      assert_nil collection[:error]
      assert_equal "10.00", collection[:collection]
      assert_equal 1, collection[:images_count]
      assert_equal 0, collection[:dropped_counts][:invalid_gps]
      assert collection[:geojson_path]
      assert File.exist?(collection[:geojson_path])

      row = collection[:rows].first
      assert_equal "Polygon", row[:geometry][:type]
      assert_equal 5, row[:geometry][:coordinates][0].length
      assert row[:x0].is_a?(Numeric)
      assert row[:y0].is_a?(Numeric)
      assert row[:half_w] > 0
      assert row[:half_h] > 0
    end
  end

  def test_build_hourly_filters_invalid_rows
    result = Zenmosaic::FootprintPipeline.build_hourly(
      profile_name: "air3s_wide_70m_rj",
      profile: profile,
      collections: [
        {
          collection: "11.00",
          collection_path: "/tmp",
          rows: [
            {
              filename: "a.jpg",
              dji_gps_latitude: nil,
              dji_gps_longitude: -45.0,
              dji_gimbal_pitch_degree: -90.0,
              dji_gimbal_yaw_degree: 10.0,
              dji_flight_yaw_degree: 2.0,
              dji_relative_altitude: 70.0
            },
            {
              filename: "b.jpg",
              dji_gps_latitude: -23.0,
              dji_gps_longitude: -45.0,
              dji_gimbal_pitch_degree: -70.0,
              dji_gimbal_yaw_degree: 12.0,
              dji_flight_yaw_degree: 3.0,
              dji_relative_altitude: 70.0
            }
          ]
        }
      ],
      export_geojson: false
    )

    collection = result[:collections].first
    assert_equal 0, collection[:images_count]
    assert_equal 1, collection[:dropped_counts][:invalid_gps]
    assert_equal 1, collection[:dropped_counts][:non_zenital]
    assert_includes collection[:warnings].join(" "), "Nenhuma foto zenital"
  end

  def test_build_hourly_uses_default_height_when_relative_altitude_is_missing
    result = Zenmosaic::FootprintPipeline.build_hourly(
      profile_name: "air3s_wide_70m_rj",
      profile: profile,
      collections: [
        {
          collection: "12.00",
          collection_path: "/tmp",
          rows: [
            {
              filename: "c.jpg",
              dji_gps_latitude: -23.0,
              dji_gps_longitude: -45.0,
              dji_gimbal_pitch_degree: -90.0,
              dji_gimbal_yaw_degree: 10.0,
              dji_flight_yaw_degree: 2.0
            }
          ]
        }
      ],
      export_geojson: false,
      default_height_agl_m: 72.0
    )

    collection = result[:collections].first
    assert_equal 1, collection[:images_count]
    assert_includes collection[:warnings].join(" "), "Altitude relativa DJI nao encontrada"
    assert_in_delta 72.0, collection[:rows].first[:height_agl_m], 0.0001
  end
end
