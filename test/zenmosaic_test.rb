# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class ZenmosaicTest < Minitest::Test
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
    end
  end

  def test_that_it_has_a_version_number
    refute_nil Zenmosaic::VERSION
  end

  def test_default_configuration
    assert Zenmosaic.configuration.enabled
    assert_equal "Zen", Zenmosaic.configuration.label_prefix
    assert_equal "/tmp/zenmosaic_batches", Zenmosaic.configuration.images_root
  end

  def test_configuration_can_be_changed
    Zenmosaic.configure do |config|
      config.enabled = false
      config.label_prefix = "Mosaic"
      config.images_root = "/tmp/custom"
    end

    refute Zenmosaic.configuration.enabled
    assert_equal "Mosaic", Zenmosaic.configuration.label_prefix
    assert_equal "/tmp/custom", Zenmosaic.configuration.images_root
  end

  def test_build_processing_request_uses_default_profile
    request = Zenmosaic.build_processing_request(paths: ["amostras/foto_01.jpg"])

    assert_equal "air3s_wide_70m_rj", request.profile_name
    assert_equal ["/tmp/zenmosaic_batches/amostras/foto_01.jpg"], request.paths
    assert_equal "EPSG:32723", request.profile[:target_crs]
  end

  def test_build_processing_request_accepts_explicit_profile
    request = Zenmosaic.build_processing_request(
      profile: "mavic3pro_mediumtele_sp",
      paths: ["lote_002/foto.jpg"]
    )

    assert_equal "mavic3pro_mediumtele_sp", request.profile_name
    assert_equal 35.0, request.profile[:fov_diag_deg]
  end

  def test_build_processing_request_accepts_profile_data
    profile_data = PROFILE_DATA.merge(fov_diag_deg: 60.0)

    request = Zenmosaic.build_processing_request(
      profile: "cliente_x",
      profile_data: profile_data,
      paths: ["lote_002/foto.jpg"]
    )

    assert_equal "cliente_x", request.profile_name
    assert_equal 60.0, request.profile[:fov_diag_deg]
  end

  def test_build_processing_request_validates_profile
    error = assert_raises(Zenmosaic::Error) do
      Zenmosaic.build_processing_request(profile: "nao_existe", paths: ["lote_003/foto.jpg"])
    end

    assert_match "nao existe", error.message
  end

  def test_build_processing_request_validates_paths
    error = assert_raises(Zenmosaic::Error) do
      Zenmosaic.build_processing_request(profile: "air3s_wide_70m_rj", paths: [])
    end

    assert_match "paths", error.message
  end

  def test_extract_files_metadata
    Dir.mktmpdir do |root|
      image_path = File.join(root, "foto.jpg")

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" drone-dji:RelativeAltitude="69.9" />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(image_path, content)

      result = Zenmosaic.extract_files_metadata(
        profile: "air3s_wide_70m_rj",
        profile_data: PROFILE_DATA,
        paths: [image_path]
      )

      assert_equal "air3s_wide_70m_rj", result[:request][:profile_name]
      assert_equal [File.expand_path(image_path)], result[:request][:input_paths]
      assert_equal 1, result[:images].size
      assert_in_delta 69.9, result[:images][0][:dji_relative_altitude], 0.0001
    end
  end

  def test_build_footprints_from_paths
    Dir.mktmpdir do |root|
      image_path = File.join(root, "img.jpg")

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
      File.binwrite(image_path, content)

      result = Zenmosaic.build_footprints(
        profile: "air3s_wide_70m_rj",
        profile_data: PROFILE_DATA,
        paths: [image_path],
        export_geojson: true,
        output_dir: File.join(root, "geojson")
      )

      assert_equal "air3s_wide_70m_rj", result[:profile_name]
      assert_equal 1, result[:collection][:images_count]
      assert File.exist?(result[:collection][:geojson_path])
    end
  end

  def test_build_preview_from_paths
    Dir.mktmpdir do |root|
      image_path = File.join(root, "foto.JPG")

      content = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
              drone-dji:GpsLatitude="-23.0"
              drone-dji:GpsLongitude="-45.0"
              drone-dji:RelativeAltitude="68.5"
              drone-dji:GimbalPitchDegree="-90.0"
              drone-dji:GimbalYawDegree="8.0"
              drone-dji:FlightYawDegree="2.0"
            />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      File.binwrite(image_path, content)

      result = Zenmosaic.build_preview(
        profile: "air3s_wide_70m_rj",
        profile_data: PROFILE_DATA,
        paths: [image_path],
        export_geojson: true,
        output_dir: File.join(root, "preview"),
        export_manifest: true
      )

      assert_equal "air3s_wide_70m_rj", result[:request][:profile_name]
      assert_equal 1, result[:collection][:plotted]
      assert File.exist?(result[:collection][:manifest_path])
    end
  end

  def test_render_mosaic_from_paths
    skip "ImageMagick nao disponivel" unless imagemagick_available?

    Dir.mktmpdir do |root|
      output = File.join(root, "mosaicos")

      image_path = File.join(root, "foto.jpg")
      create_sample_image(image_path)
      append_dji_xmp(image_path)

      result = Zenmosaic.render_mosaic(
        profile: "air3s_wide_70m_rj",
        profile_data: PROFILE_DATA,
        paths: [image_path],
        export_geojson: true,
        output_dir: output,
        export_manifest: true,
        max_images_to_plot: 12,
        downsample_native: 1,
        compressed_scale: 0.5,
        compressed_quality: 85
      )

      collection = result[:collection]
      assert_equal 1, collection[:plotted]
      assert File.exist?(collection[:output_path_native])
      assert File.exist?(collection[:output_path_compressed])
    end
  end
end
