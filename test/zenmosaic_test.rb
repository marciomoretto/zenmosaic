# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class ZenmosaicTest < Minitest::Test
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

  def create_sample_image(path, color: "#2255cc", size: "240x180")
    ok = system("convert", "-size", size, "xc:#{color}", path, out: File::NULL, err: File::NULL)
    raise "Falha ao criar imagem de teste" unless ok
  end

  def append_dji_xmp(path)
    content = <<~XMP
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description
            xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
            drone-dji:GpsLatitude="-23.0"
            drone-dji:GpsLongitude="-45.0"
            drone-dji:RelativeAltitude="70.0"
            drone-dji:GimbalPitchDegree="-90.0"
            drone-dji:GimbalYawDegree="8.0"
            drone-dji:FlightYawDegree="2.0"
          />
        </rdf:RDF>
      </x:xmpmeta>
    XMP

    File.open(path, "ab") { |f| f.write(content) }
  end

  def setup
    Zenmosaic.configuration = Zenmosaic::Configuration.new

    Zenmosaic.configure do |config|
      config.enabled = true
      config.label_prefix = "Zen"
      config.images_root = "/tmp/zenmosaic_batches"
      config.default_profile = "air3s_wide_70m_rj"
    end
  end

  def test_that_it_has_a_version_number
    refute_nil Zenmosaic::VERSION
  end

  def test_default_configuration
    assert Zenmosaic.configuration.enabled
    assert_equal "Zen", Zenmosaic.configuration.label_prefix
    assert Zenmosaic.configuration.profiles.key?("air3s_wide_70m_rj")
    assert_equal "air3s_wide_70m_rj", Zenmosaic.configuration.default_profile
  end

  def test_configuration_can_be_changed
    custom_profiles = Zenmosaic::DefaultProfiles.all
    custom_profiles["perfil_custom"] = {
      expected_camera_models: ["CUSTOM"],
      fov_diag_deg: 42.0,
      aspect_ratio: [3, 2],
      agl_offset_m: 2.0,
      alt_tolerance_m: 4.0,
      target_crs: "EPSG:4326"
    }

    Zenmosaic.configure do |config|
      config.enabled = false
      config.label_prefix = "Mosaic"
      config.profiles = custom_profiles
      config.default_profile = "perfil_custom"
    end

    refute Zenmosaic.configuration.enabled
    assert_equal "Mosaic", Zenmosaic.configuration.label_prefix
    assert_equal "perfil_custom", Zenmosaic.configuration.default_profile
    assert Zenmosaic.configuration.profiles.key?("perfil_custom")
  end

  def test_build_processing_request_uses_default_profile
    request = Zenmosaic.build_processing_request(folder: "lote_001")

    assert_equal "air3s_wide_70m_rj", request.profile_name
    assert_equal "lote_001", request.folder_name
    assert_equal "/tmp/zenmosaic_batches/lote_001", request.folder_path
    assert_equal "EPSG:32723", request.profile[:target_crs]
  end

  def test_build_processing_request_accepts_explicit_profile
    request = Zenmosaic.build_processing_request(
      profile: "mavic3pro_mediumtele_sp",
      folder: "lote_002"
    )

    assert_equal "mavic3pro_mediumtele_sp", request.profile_name
    assert_equal 35.0, request.profile[:fov_diag_deg]
  end

  def test_build_processing_request_validates_profile
    error = assert_raises(Zenmosaic::Error) do
      Zenmosaic.build_processing_request(profile: "nao_existe", folder: "lote_003")
    end

    assert_match "nao existe", error.message
  end

  def test_build_processing_request_validates_folder
    error = assert_raises(Zenmosaic::Error) do
      Zenmosaic.build_processing_request(profile: "air3s_wide_70m_rj", folder: " ")
    end

    assert_match "pasta", error.message
  end

  def test_extract_batch_metadata
    Dir.mktmpdir do |root|
      folder = File.join(root, "lote_010")
      FileUtils.mkdir_p(folder)

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" drone-dji:RelativeAltitude="69.9" />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(File.join(folder, "foto.jpg"), content)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.extract_batch_metadata(
        profile: "air3s_wide_70m_rj",
        folder: "lote_010"
      )

      assert_equal "air3s_wide_70m_rj", result[:request][:profile_name]
      assert_equal "lote_010", result[:request][:folder_name]
      assert_equal 1, result[:images].size
      assert_in_delta 69.9, result[:images][0][:dji_relative_altitude], 0.0001
    end
  end

  def test_extract_hourly_metadata
    Dir.mktmpdir do |root|
      base_folder = File.join(root, "lote_020")
      hour_folder = File.join(base_folder, "14.30")
      FileUtils.mkdir_p(hour_folder)

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" drone-dji:CameraPitchDegree="-85.0" />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(File.join(hour_folder, "img.jpg"), content)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.extract_hourly_metadata(
        profile: "air3s_wide_70m_rj",
        folder: "lote_020",
        subfolders: ["14.30"]
      )

      assert_equal "lote_020", result[:request][:folder_name]
      assert_equal 1, result[:folders].length
      assert_equal "14.30", result[:folders][0][:folder]
      assert_equal 1, result[:folders][0][:images_count]
      assert_in_delta(-85.0, result[:folders][0][:rows][0][:dji_camera_pitch_degree], 0.0001)
    end
  end

  def test_extract_folder_metadata_single_folder
    Dir.mktmpdir do |root|
      hour_folder = File.join(root, "18.00")
      FileUtils.mkdir_p(hour_folder)

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" drone-dji:RelativeAltitude="68.5" />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(File.join(hour_folder, "img.jpg"), content)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.extract_folder_metadata(
        profile: "air3s_wide_70m_rj",
        folder: "18.00"
      )

      assert_equal "air3s_wide_70m_rj", result[:request][:profile_name]
      assert_equal "18.00", result[:request][:folder_name]
      assert_equal "18.00", result[:folder][:folder]
      assert_equal 1, result[:folder][:images_count]
      assert_in_delta 68.5, result[:folder][:rows][0][:dji_relative_altitude], 0.0001
    end
  end

  def test_build_hourly_footprints
    Dir.mktmpdir do |root|
      batch_folder = File.join(root, "lote_030")
      hour_folder = File.join(batch_folder, "15.00")
      out_folder = File.join(root, "geojson")
      FileUtils.mkdir_p(hour_folder)

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
              drone-dji:GpsLatitude="-23.0"
              drone-dji:GpsLongitude="-45.0"
              drone-dji:RelativeAltitude="70.0"
              drone-dji:GimbalPitchDegree="-90.0"
              drone-dji:GimbalYawDegree="12.0"
              drone-dji:FlightYawDegree="3.0"
            />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(File.join(hour_folder, "img.jpg"), content)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.build_hourly_footprints(
        profile: "air3s_wide_70m_rj",
        folder: "lote_030",
        subfolders: ["15.00"],
        export_geojson: true,
        output_dir: out_folder
      )

      assert_equal "air3s_wide_70m_rj", result[:profile_name]
      assert_equal 1, result[:folders].length
      assert_equal 1, result[:folders][0][:images_count]
      assert File.exist?(result[:folders][0][:geojson_path])
    end
  end

  def test_build_folder_footprints_single_folder
    Dir.mktmpdir do |root|
      hour_folder = File.join(root, "18.10")
      out_folder = File.join(root, "geojson")
      FileUtils.mkdir_p(hour_folder)

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
              drone-dji:GpsLatitude="-23.0"
              drone-dji:GpsLongitude="-45.0"
              drone-dji:RelativeAltitude="70.0"
              drone-dji:GimbalPitchDegree="-90.0"
              drone-dji:GimbalYawDegree="11.0"
              drone-dji:FlightYawDegree="3.0"
            />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(File.join(hour_folder, "img.jpg"), content)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.build_folder_footprints(
        profile: "air3s_wide_70m_rj",
        folder: "18.10",
        export_geojson: true,
        output_dir: out_folder
      )

      assert_equal "air3s_wide_70m_rj", result[:profile_name]
      assert_equal "18.10", result[:folder][:folder]
      assert_equal 1, result[:folder][:images_count]
      assert File.exist?(result[:folder][:geojson_path])
    end
  end

  def test_build_hourly_preview
    Dir.mktmpdir do |root|
      batch_folder = File.join(root, "lote_040")
      hour_folder = File.join(batch_folder, "16.00")
      output = File.join(root, "preview")
      FileUtils.mkdir_p(hour_folder)

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
              drone-dji:GpsLatitude="-23.0"
              drone-dji:GpsLongitude="-45.0"
              drone-dji:RelativeAltitude="70.0"
              drone-dji:GimbalPitchDegree="-90.0"
              drone-dji:GimbalYawDegree="8.0"
              drone-dji:FlightYawDegree="2.0"
            />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(File.join(hour_folder, "foto.JPG"), content)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.build_hourly_preview(
        profile: "air3s_wide_70m_rj",
        folder: "lote_040",
        subfolders: ["16.00"],
        export_geojson: true,
        output_dir: output,
        export_manifest: true
      )

      assert_equal "air3s_wide_70m_rj", result[:request][:profile_name]
      assert_equal 1, result[:footprints][:folders].length
      assert_equal 1, result[:preview][:folders].length
      assert_equal 1, result[:preview][:folders][0][:plotted]
      assert File.exist?(result[:preview][:folders][0][:manifest_path])
    end
  end

  def test_build_folder_preview_single_folder
    Dir.mktmpdir do |root|
      hour_folder = File.join(root, "18.20")
      output = File.join(root, "preview")
      FileUtils.mkdir_p(hour_folder)

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
              drone-dji:GpsLatitude="-23.0"
              drone-dji:GpsLongitude="-45.0"
              drone-dji:RelativeAltitude="70.0"
              drone-dji:GimbalPitchDegree="-90.0"
              drone-dji:GimbalYawDegree="8.0"
              drone-dji:FlightYawDegree="2.0"
            />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(File.join(hour_folder, "foto.JPG"), content)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.build_folder_preview(
        profile: "air3s_wide_70m_rj",
        folder: "18.20",
        export_geojson: true,
        output_dir: output,
        export_manifest: true
      )

      assert_equal "air3s_wide_70m_rj", result[:request][:profile_name]
      assert_equal "18.20", result[:folder][:folder]
      assert_equal 1, result[:folder][:plotted]
      assert File.exist?(result[:folder][:manifest_path])
    end
  end

  def test_render_hourly_mosaics
    skip "ImageMagick nao disponivel" unless imagemagick_available?

    Dir.mktmpdir do |root|
      batch_folder = File.join(root, "lote_050")
      hour_folder = File.join(batch_folder, "17.00")
      output = File.join(root, "mosaicos")
      FileUtils.mkdir_p(hour_folder)

      image_path = File.join(hour_folder, "foto.jpg")
      create_sample_image(image_path)
      append_dji_xmp(image_path)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.render_hourly_mosaics(
        profile: "air3s_wide_70m_rj",
        folder: "lote_050",
        subfolders: ["17.00"],
        export_geojson: true,
        output_dir: output,
        export_manifest: true,
        max_images_to_plot: 12,
        downsample_native: 1,
        compressed_scale: 0.5,
        compressed_quality: 85
      )

      folder = result[:mosaics][:folders][0]
      assert_equal "17.00", folder[:folder]
      assert_equal 1, folder[:plotted]
      assert File.exist?(folder[:output_path_native])
      assert File.exist?(folder[:output_path_compressed])
    end
  end

  def test_render_folder_mosaic_single_folder
    skip "ImageMagick nao disponivel" unless imagemagick_available?

    Dir.mktmpdir do |root|
      hour_folder = File.join(root, "18.30")
      output = File.join(root, "mosaicos")
      FileUtils.mkdir_p(hour_folder)

      image_path = File.join(hour_folder, "foto.jpg")
      create_sample_image(image_path)
      append_dji_xmp(image_path)

      Zenmosaic.configure do |config|
        config.images_root = root
      end

      result = Zenmosaic.render_folder_mosaic(
        profile: "air3s_wide_70m_rj",
        folder: "18.30",
        export_geojson: true,
        output_dir: output,
        export_manifest: true,
        max_images_to_plot: 12,
        downsample_native: 1,
        compressed_scale: 0.5,
        compressed_quality: 85
      )

      folder = result[:folder]
      assert_equal "18.30", folder[:folder]
      assert_equal 1, folder[:plotted]
      assert File.exist?(folder[:output_path_native])
      assert File.exist?(folder[:output_path_compressed])
    end
  end
end
