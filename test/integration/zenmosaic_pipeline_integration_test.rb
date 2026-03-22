# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class ZenmosaicPipelineIntegrationTest < Minitest::Test
  PROFILE_DATA = {
    expected_camera_models: nil,
    fov_diag_deg: 84.0,
    aspect_ratio: [4, 3],
    agl_offset_m: 0.0,
    expected_relative_altitude_m: 70.0,
    alt_tolerance_m: 5.0,
    target_crs: "EPSG:32723"
  }.freeze

  def executable_available?(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
      candidate = File.join(dir, name)
      File.file?(candidate) && File.executable?(candidate)
    end
  end

  def imagemagick_available?
    executable_available?("convert") &&
      executable_available?("identify") &&
      executable_available?("composite")
  end

  def create_sample_image(path, color: "#2266aa", size: "240x180")
    ok = system("convert", "-size", size, "xc:#{color}", path, out: File::NULL, err: File::NULL)
    raise "Falha ao criar imagem de teste" unless ok
  end

  def dji_xmp(latitude: -23.0, longitude: -45.0, relative_altitude: 70.0,
              gimbal_pitch: -90.0, gimbal_yaw: 8.0, flight_yaw: 2.0)
    <<~XMP
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description
            xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
            drone-dji:GpsLatitude="#{latitude}"
            drone-dji:GpsLongitude="#{longitude}"
            drone-dji:RelativeAltitude="#{relative_altitude}"
            drone-dji:GimbalPitchDegree="#{gimbal_pitch}"
            drone-dji:GimbalYawDegree="#{gimbal_yaw}"
            drone-dji:FlightYawDegree="#{flight_yaw}"
          />
        </rdf:RDF>
      </x:xmpmeta>
    XMP
  end

  def write_xmp_only_image(path, **kwargs)
    File.binwrite(path, dji_xmp(**kwargs))
  end

  def append_dji_xmp(path, **kwargs)
    File.open(path, "ab") { |file| file.write(dji_xmp(**kwargs)) }
  end

  def setup
    Zenmosaic.configuration = Zenmosaic::Configuration.new
  end

  def test_build_folder_preview_end_to_end_generates_geojson_and_manifest
    Dir.mktmpdir do |root|
      image_dir = File.join(root, "entrada")
      output_dir = File.join(root, "out")
      FileUtils.mkdir_p(image_dir)
      image_path = File.join(image_dir, "frame_01.jpg")
      write_xmp_only_image(image_path)

      result = Zenmosaic.build_preview(
        profile: "air3s_wide_70m_rj",
        profile_data: PROFILE_DATA,
        paths: [image_path],
        output_dir: output_dir,
        export_geojson: true,
        export_manifest: true
      )

      assert_equal "air3s_wide_70m_rj", result.dig(:request, :profile_name)

      footprint_collection = result.dig(:footprints, :collection)
      preview_collection = result[:collection]

      assert_equal 1, footprint_collection[:images_count]
      assert_equal 1, preview_collection[:plotted]
      assert File.exist?(footprint_collection[:geojson_path])
      assert File.exist?(preview_collection[:manifest_path])
      refute footprint_collection.key?(:csv_path)
      refute preview_collection.key?(:csv_path)
    end
  end

  def test_build_preview_end_to_end_for_two_files
    Dir.mktmpdir do |root|
      output_dir = File.join(root, "out")
      hour_one = File.join(root, "14.00")
      hour_two = File.join(root, "14.10")
      FileUtils.mkdir_p(hour_one)
      FileUtils.mkdir_p(hour_two)

      image_a = File.join(hour_one, "a.jpg")
      image_b = File.join(hour_two, "b.jpg")
      write_xmp_only_image(image_a, gimbal_yaw: 11.0, flight_yaw: 3.0)
      write_xmp_only_image(image_b, gimbal_yaw: 13.0, flight_yaw: 4.0)

      result = Zenmosaic.build_preview(
        profile: "air3s_wide_70m_rj",
        profile_data: PROFILE_DATA,
        paths: [image_a, image_b],
        output_dir: output_dir,
        export_geojson: true,
        export_manifest: true
      )

      assert_equal "air3s_wide_70m_rj", result.dig(:request, :profile_name)
      assert_equal 2, result.dig(:footprints, :collection, :images_count)
      assert_equal 2, result.dig(:preview, :collections, 0, :plotted)
      assert File.exist?(result.dig(:footprints, :collection, :geojson_path))
      assert File.exist?(result.dig(:preview, :collections, 0, :manifest_path))
    end
  end

  def test_render_folder_mosaic_end_to_end
    skip "ImageMagick nao disponivel" unless imagemagick_available?

    Dir.mktmpdir do |root|
      image_dir = File.join(root, "entrada")
      output_dir = File.join(root, "mosaicos")
      FileUtils.mkdir_p(image_dir)

      image_path = File.join(image_dir, "frame_01.jpg")
      create_sample_image(image_path)
      append_dji_xmp(image_path)

      result = Zenmosaic.render_mosaic(
        profile: "air3s_wide_70m_rj",
        profile_data: PROFILE_DATA,
        paths: [image_path],
        output_dir: output_dir,
        export_geojson: true,
        export_manifest: true,
        max_images_to_plot: 12,
        downsample_native: 1,
        compressed_scale: 0.5,
        compressed_quality: 85
      )

      mosaic_collection = result[:collection]

      assert_equal 1, mosaic_collection[:plotted]
      assert File.exist?(mosaic_collection[:output_path_native])
      assert File.exist?(mosaic_collection[:output_path_compressed])
      assert File.exist?(result.dig(:footprints, :collection, :geojson_path))
      assert File.exist?(result.dig(:preview, :collections, 0, :manifest_path))
    end
  end
end
