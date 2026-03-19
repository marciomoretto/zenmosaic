# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class ZenmosaicPipelineIntegrationTest < Minitest::Test
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

    Zenmosaic.configure do |config|
      config.default_profile = "air3s_wide_70m_rj"
    end
  end

  def test_build_folder_preview_end_to_end_generates_geojson_and_manifest
    Dir.mktmpdir do |root|
      folder_name = "18.40"
      image_dir = File.join(root, folder_name)
      output_dir = File.join(root, "out")
      FileUtils.mkdir_p(image_dir)
      write_xmp_only_image(File.join(image_dir, "frame_01.jpg"))

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.build_folder_preview(
        profile: "air3s_wide_70m_rj",
        folder: folder_name,
        output_dir: output_dir,
        export_geojson: true,
        export_manifest: true
      )

      assert_equal folder_name, result.dig(:request, :folder_name)
      assert_equal "air3s_wide_70m_rj", result.dig(:request, :profile_name)

      footprint_folder = result.dig(:footprints, :folder)
      preview_folder = result[:folder]

      assert_equal 1, footprint_folder[:images_count]
      assert_equal 1, preview_folder[:plotted]
      assert File.exist?(footprint_folder[:geojson_path])
      assert File.exist?(preview_folder[:manifest_path])
      refute footprint_folder.key?(:csv_path)
      refute preview_folder.key?(:csv_path)
    end
  end

  def test_build_hourly_preview_end_to_end_for_two_subfolders
    Dir.mktmpdir do |root|
      batch_folder = File.join(root, "lote_900")
      output_dir = File.join(root, "out")
      hour_one = File.join(batch_folder, "14.00")
      hour_two = File.join(batch_folder, "14.10")
      FileUtils.mkdir_p(hour_one)
      FileUtils.mkdir_p(hour_two)

      write_xmp_only_image(File.join(hour_one, "a.jpg"), gimbal_yaw: 11.0, flight_yaw: 3.0)
      write_xmp_only_image(File.join(hour_two, "b.jpg"), gimbal_yaw: 13.0, flight_yaw: 4.0)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.build_hourly_preview(
        profile: "air3s_wide_70m_rj",
        folder: "lote_900",
        subfolders: ["14.00", "14.10"],
        output_dir: output_dir,
        export_geojson: true,
        export_manifest: true
      )

      assert_equal "air3s_wide_70m_rj", result.dig(:request, :profile_name)
      assert_equal 2, result.dig(:footprints, :folders).length
      assert_equal 2, result.dig(:preview, :folders).length

      result[:footprints][:folders].each do |folder|
        assert_equal 1, folder[:images_count]
        assert File.exist?(folder[:geojson_path])
      end

      result[:preview][:folders].each do |folder|
        assert_equal 1, folder[:plotted]
        assert File.exist?(folder[:manifest_path])
      end
    end
  end

  def test_render_folder_mosaic_end_to_end
    skip "ImageMagick nao disponivel" unless imagemagick_available?

    Dir.mktmpdir do |root|
      folder_name = "18.50"
      image_dir = File.join(root, folder_name)
      output_dir = File.join(root, "mosaicos")
      FileUtils.mkdir_p(image_dir)

      image_path = File.join(image_dir, "frame_01.jpg")
      create_sample_image(image_path)
      append_dji_xmp(image_path)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.render_folder_mosaic(
        profile: "air3s_wide_70m_rj",
        folder: folder_name,
        output_dir: output_dir,
        export_geojson: true,
        export_manifest: true,
        max_images_to_plot: 12,
        downsample_native: 1,
        compressed_scale: 0.5,
        compressed_quality: 85
      )

      mosaic_folder = result[:folder]

      assert_equal folder_name, mosaic_folder[:folder]
      assert_equal 1, mosaic_folder[:plotted]
      assert File.exist?(mosaic_folder[:output_path_native])
      assert File.exist?(mosaic_folder[:output_path_compressed])
      assert File.exist?(result.dig(:footprints, :folder, :geojson_path))
      assert File.exist?(result.dig(:preview, :folders, 0, :manifest_path))
    end
  end
end
