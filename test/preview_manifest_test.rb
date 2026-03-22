# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "test_helper"

class PreviewManifestTest < Minitest::Test
  def test_resolve_image_path_with_extension_fallback
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "foto.JPG"), "fake")

      found = Zenmosaic::PreviewManifest.resolve_image_path(dir, "foto.jpg")

      refute_nil found
      assert_equal File.expand_path(File.join(dir, "foto.JPG")), found
    end
  end

  def test_build_hourly_generates_folder_preview_and_manifest
    Dir.mktmpdir do |dir|
      images_base = File.join(dir, "images")
      folder_name = "09.45"
      images_folder = File.join(images_base, folder_name)
      output = File.join(dir, "preview")
      FileUtils.mkdir_p(images_folder)

      File.binwrite(File.join(images_folder, "frame_01.JPG"), "fake")

      footprints_result = {
        profile_name: "air3s_wide_70m_rj",
        collections: [
          {
            collection: folder_name,
            rows: [
              {
                filename: "09.45/frame_01.jpg",
                x0: 100.0,
                y0: 200.0,
                half_w: 10.0,
                half_h: 8.0,
                rotation_deg: 12.0,
                geometry: {
                  type: "Polygon",
                  coordinates: [[[90.0, 192.0], [110.0, 192.0], [110.0, 208.0], [90.0, 208.0], [90.0, 192.0]]]
                }
              }
            ]
          }
        ]
      }

      result = Zenmosaic::PreviewManifest.build_hourly(
        footprints_result: footprints_result,
        images_base_dir: images_base,
        export_manifest: true,
        output_dir: output
      )

      assert_equal "air3s_wide_70m_rj", result[:profile_name]
      assert_equal 1, result[:collections].length

      collection = result[:collections][0]
      assert_equal folder_name, collection[:collection]
      assert_equal 1, collection[:attempted]
      assert_equal 1, collection[:plotted]
      assert_equal 0, collection[:failed]
      assert_equal 0, collection[:skipped]
      assert collection[:bounds]
      assert_equal 1, collection[:items].length
      assert collection[:manifest_path]
      assert File.exist?(collection[:manifest_path])

      manifest_json = JSON.parse(File.read(collection[:manifest_path]))
      assert_equal folder_name, manifest_json["collection"]
      assert_equal 1, manifest_json["plotted"]
    end
  end
end
