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
        folders: [
          {
            folder: folder_name,
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
      assert_equal 1, result[:folders].length

      folder = result[:folders][0]
      assert_equal folder_name, folder[:folder]
      assert_equal 1, folder[:attempted]
      assert_equal 1, folder[:plotted]
      assert_equal 0, folder[:failed]
      assert_equal 0, folder[:skipped]
      assert folder[:bounds]
      assert_equal 1, folder[:items].length
      assert folder[:manifest_path]
      assert File.exist?(folder[:manifest_path])

      manifest_json = JSON.parse(File.read(folder[:manifest_path]))
      assert_equal folder_name, manifest_json["folder"]
      assert_equal 1, manifest_json["plotted"]
    end
  end
end
