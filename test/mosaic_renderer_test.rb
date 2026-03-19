# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "test_helper"

class MosaicRendererTest < Minitest::Test
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

  def create_sample_image(path, color: "#cc3333", size: "240x180")
    ok = system("convert", "-size", size, "xc:#{color}", path, out: File::NULL, err: File::NULL)
    raise "Falha ao criar imagem de teste" unless ok
  end

  def test_compute_global_rotation
    items = [
      { transform: { x0: 0.0, y0: 0.0 } },
      { transform: { x0: 10.0, y0: 10.0 } }
    ]

    cx, cy, principal, global = Zenmosaic::MosaicRenderer.compute_global_rotation(items)

    assert_in_delta 5.0, cx, 0.0001
    assert_in_delta 5.0, cy, 0.0001
    assert_in_delta 45.0, principal, 0.5
    assert_in_delta(-45.0, global, 0.5)
  end

  def test_render_hourly_generates_native_and_compressed_files
    skip "ImageMagick nao disponivel" unless imagemagick_available?

    Dir.mktmpdir do |root|
      output = File.join(root, "out")
      images_dir = File.join(root, "images", "09.45")
      FileUtils.mkdir_p(images_dir)

      image_path = File.join(images_dir, "frame_01.jpg")
      create_sample_image(image_path)

      preview_result = {
        folders: [
          {
            folder: "09.45",
            items: [
              {
                filename: "09.45/frame_01.jpg",
                image_path: image_path,
                transform: {
                  x0: 500_000.0,
                  y0: 7_450_000.0,
                  half_w: 20.0,
                  half_h: 15.0,
                  rotation_deg: 10.0
                },
                geometry: {
                  type: "Polygon",
                  coordinates: [[
                    [499_980.0, 7_449_985.0],
                    [500_020.0, 7_449_985.0],
                    [500_020.0, 7_450_015.0],
                    [499_980.0, 7_450_015.0],
                    [499_980.0, 7_449_985.0]
                  ]]
                }
              }
            ]
          }
        ]
      }

      result = Zenmosaic::MosaicRenderer.render_hourly(
        preview_result: preview_result,
        profile_name: "air3s_wide_70m_rj",
        output_dir: output,
        downsample_native: 1,
        compressed_scale: 0.5,
        compressed_quality: 85
      )

      folder = result[:folders].first
      assert_equal "09.45", folder[:folder]
      assert_equal 1, folder[:attempted]
      assert_equal 1, folder[:plotted]
      assert_equal 0, folder[:failed]
      assert File.exist?(folder[:output_path_native])
      assert File.exist?(folder[:output_path_compressed])
    end
  end
end
