# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class MetadataExtractorTest < Minitest::Test
  def test_rational_to_float
    assert_equal 12.0, Zenmosaic::MetadataExtractor.rational_to_float(12)
    assert_equal 2.5, Zenmosaic::MetadataExtractor.rational_to_float([5, 2])
    assert_nil Zenmosaic::MetadataExtractor.rational_to_float([3, 0])
    assert_nil Zenmosaic::MetadataExtractor.rational_to_float(nil)
  end

  def test_aperture_and_shutter_conversions
    assert_in_delta 2.0, Zenmosaic::MetadataExtractor.exif_aperture_to_fnumber(2), 0.0001
    assert_in_delta 0.25, Zenmosaic::MetadataExtractor.exif_shutter_to_seconds(2), 0.0001
  end

  def test_convert_gps_to_degrees
    values = [[23, 1], [30, 1], [0, 1]]

    assert_in_delta 23.5, Zenmosaic::MetadataExtractor.convert_gps_to_degrees(values, "N"), 0.0001
    assert_in_delta(-23.5, Zenmosaic::MetadataExtractor.convert_gps_to_degrees(values, "S"), 0.0001)
  end

  def test_extract_xmp_metadata
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.jpg")
      content = <<~XMP
        random bytes
        <x:xmpmeta xmlns:x="adobe:ns:meta/" xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:RDF>
            <rdf:Description
              xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/"
              drone-dji:GpsLatitude="-23.1234"
              drone-dji:GpsLongitude="-46.9876"
              drone-dji:RelativeAltitude="71.25"
              drone-dji:GimbalPitchDegree="-90.0"
            />
          </rdf:RDF>
        </x:xmpmeta>
      XMP

      File.binwrite(path, content)

      data = Zenmosaic::MetadataExtractor.extract_xmp_metadata(path)

      assert_in_delta(-23.1234, data[:dji_gps_latitude], 0.0001)
      assert_in_delta(-46.9876, data[:dji_gps_longitude], 0.0001)
      assert_in_delta 71.25, data[:dji_relative_altitude], 0.0001
      assert_in_delta(-90.0, data[:dji_gimbal_pitch_degree], 0.0001)
      assert_nil data[:dji_camera_roll_degree]
    end
  end

  def test_extract_image_metadata_merges_default_exif_and_xmp
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sample.jpg")
      content = <<~XMP
        text
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" drone-dji:FlightYawDegree="15.5" />
          </rdf:RDF>
        </x:xmpmeta>
      XMP

      File.binwrite(path, content)

      data = Zenmosaic::MetadataExtractor.extract_image_metadata(path)

      assert_equal "sample.jpg", data[:file_name]
      assert_equal File.expand_path(path), data[:file_path]
      assert_in_delta 15.5, data[:dji_flight_yaw_degree], 0.0001
      assert data.key?(:camera_model)
      assert data.key?(:gps_latitude)
    end
  end

  def test_extract_folder_metadata_filters_by_extension
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "nested"))

      File.binwrite(File.join(dir, "nested", "a.jpg"), "fake")
      File.binwrite(File.join(dir, "nested", "b.JPEG"), "fake")
      File.binwrite(File.join(dir, "nested", "notes.txt"), "fake")

      data = Zenmosaic::MetadataExtractor.extract_folder_metadata(dir)

      assert_equal 2, data.size
      assert_equal ["a.jpg", "b.JPEG"], data.map { |item| item[:file_name] }
    end
  end
end
