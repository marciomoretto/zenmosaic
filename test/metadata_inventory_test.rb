# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class MetadataInventoryTest < Minitest::Test
  def test_process_subfolders_in_memory
    Dir.mktmpdir do |root|
      images_root = File.join(root, "images")

      FileUtils.mkdir_p(File.join(images_root, "10.00", "nested"))
      FileUtils.mkdir_p(File.join(images_root, "11.00"))

      xmp_1 = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" drone-dji:RelativeAltitude="70.5" />
          </rdf:RDF>
        </x:xmpmeta>
      XMP
      xmp_2 = <<~XMP
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:drone-dji="http://www.dji.com/drone-dji/1.0/" drone-dji:FlightYawDegree="12.25" />
          </rdf:RDF>
        </x:xmpmeta>
      XMP

      File.binwrite(File.join(images_root, "10.00", "nested", "a.jpg"), xmp_1)
      File.binwrite(File.join(images_root, "11.00", "b.png"), xmp_2)

      result = Zenmosaic::MetadataInventory.process_subfolders(
        image_dir: images_root,
        subfolders: ["10.00", "11.00", "12.00"]
      )

      assert_equal 3, result.size

      ten = result.find { |item| item[:folder] == "10.00" }
      eleven = result.find { |item| item[:folder] == "11.00" }
      twelve = result.find { |item| item[:folder] == "12.00" }

      assert_equal 1, ten[:images_count]
      assert_equal "10.00", ten[:rows][0][:folder]
      assert_equal "10.00/nested/a.jpg", ten[:rows][0][:filename]
      assert_in_delta 70.5, ten[:rows][0][:dji_relative_altitude], 0.0001

      assert_equal 1, eleven[:images_count]
      assert_equal "11.00", eleven[:rows][0][:folder]
      assert_equal "11.00/b.png", eleven[:rows][0][:filename]
      assert_in_delta 12.25, eleven[:rows][0][:dji_flight_yaw_degree], 0.0001

      assert_equal 0, twelve[:images_count]
    end
  end

  def test_process_subfolders_validates_input
    error = assert_raises(Zenmosaic::Error) do
      Zenmosaic::MetadataInventory.process_subfolders(image_dir: " ", subfolders: [])
    end
    assert_match "image_dir", error.message

    error = assert_raises(Zenmosaic::Error) do
      Zenmosaic::MetadataInventory.process_subfolders(image_dir: "/tmp", subfolders: "10.00")
    end
    assert_match "Array", error.message
  end
end
