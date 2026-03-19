# frozen_string_literal: true

require_relative "zenmosaic/version"
require_relative "zenmosaic/default_profiles"
require_relative "zenmosaic/configuration"
require_relative "zenmosaic/processing_request"
require_relative "zenmosaic/metadata_extractor"
require_relative "zenmosaic/metadata_inventory"
require_relative "zenmosaic/coordinate_transformer"
require_relative "zenmosaic/footprint_pipeline"
require_relative "zenmosaic/preview_manifest"
require_relative "zenmosaic/mosaic_renderer"

module Zenmosaic
  class Error < StandardError; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def build_processing_request(profile: nil, folder:)
      selected_profile = profile || configuration.default_profile

      ProcessingRequest.new(
        profile_name: selected_profile,
        folder_name: folder,
        profiles: configuration.profiles,
        images_root: configuration.images_root
      )
    end

    def extract_batch_metadata(profile: nil, folder:)
      request = build_processing_request(profile: profile, folder: folder)

      {
        request: request.to_h,
        images: MetadataExtractor.extract_folder_metadata(request.folder_path)
      }
    end

    def extract_folder_metadata(profile: nil, folder:)
      request = build_processing_request(profile: profile, folder: folder)
      folder_path = request.folder_path

      parent_dir = File.dirname(folder_path)
      folder_name = File.basename(folder_path)
      folder_name = request.folder_name if folder_name.nil? || folder_name.empty? || folder_name == "/"

      folder_result = MetadataInventory.process_single_subfolder(
        image_dir: parent_dir,
        subfolder_name: folder_name
      )

      {
        request: request.to_h,
        folder: folder_result
      }
    end

    def extract_image_metadata(path)
      MetadataExtractor.extract_image_metadata(path)
    end

    def extract_hourly_metadata(profile: nil, folder:, subfolders:)
      request = build_processing_request(profile: profile, folder: folder)

      {
        request: request.to_h,
        folders: MetadataInventory.process_subfolders(
          image_dir: request.folder_path,
          subfolders: subfolders
        )
      }
    end

    def build_hourly_footprints(profile: nil, folder:, subfolders:,
                                export_geojson: false, output_dir: nil,
                                pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      metadata = extract_hourly_metadata(
        profile: profile,
        folder: folder,
        subfolders: subfolders
      )

      result = FootprintPipeline.build_hourly(
        profile_name: metadata[:request][:profile_name],
        profile: metadata[:request][:profile],
        folders: metadata[:folders],
        export_geojson: export_geojson,
        output_dir: output_dir,
        pitch_tolerance_deg: pitch_tolerance_deg,
        default_height_agl_m: default_height_agl_m
      )

      result.merge(request: metadata[:request])
    end

    def build_folder_footprints(profile: nil, folder:,
                                export_geojson: false, output_dir: nil,
                                pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      metadata = extract_folder_metadata(
        profile: profile,
        folder: folder
      )

      result = FootprintPipeline.build_hourly(
        profile_name: metadata[:request][:profile_name],
        profile: metadata[:request][:profile],
        folders: [metadata[:folder]],
        export_geojson: export_geojson,
        output_dir: output_dir,
        pitch_tolerance_deg: pitch_tolerance_deg,
        default_height_agl_m: default_height_agl_m
      )

      {
        request: metadata[:request],
        profile_name: result[:profile_name],
        target_crs: result[:target_crs],
        fov_diag_deg: result[:fov_diag_deg],
        fov_width_rad: result[:fov_width_rad],
        fov_height_rad: result[:fov_height_rad],
        folder: result[:folders][0]
      }
    end

    def build_hourly_preview(profile: nil, folder:, subfolders:, images_base_dir: nil,
                             max_images_to_plot: 12, downsample: 6,
                             export_geojson: false,
                             output_dir: nil, export_manifest: true,
                             pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      footprints = build_hourly_footprints(
        profile: profile,
        folder: folder,
        subfolders: subfolders,
        export_geojson: export_geojson,
        output_dir: output_dir,
        pitch_tolerance_deg: pitch_tolerance_deg,
        default_height_agl_m: default_height_agl_m
      )

      resolved_images_base = images_base_dir || footprints.dig(:request, :folder_path)

      preview = PreviewManifest.build_hourly(
        footprints_result: footprints,
        images_base_dir: resolved_images_base,
        max_images_to_plot: max_images_to_plot,
        downsample: downsample,
        output_dir: output_dir,
        export_manifest: export_manifest
      )

      {
        request: footprints[:request],
        footprints: footprints,
        preview: preview
      }
    end

    def build_folder_preview(profile: nil, folder:, images_dir: nil,
                             max_images_to_plot: 12, downsample: 6,
                             export_geojson: false,
                             output_dir: nil, export_manifest: true,
                             pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      footprints = build_folder_footprints(
        profile: profile,
        folder: folder,
        export_geojson: export_geojson,
        output_dir: output_dir,
        pitch_tolerance_deg: pitch_tolerance_deg,
        default_height_agl_m: default_height_agl_m
      )

      folder_data = footprints[:folder]
      request = footprints[:request]
      resolved_images_base = images_dir || File.dirname(request[:folder_path])

      preview = PreviewManifest.build_hourly(
        footprints_result: {
          profile_name: footprints[:profile_name],
          folders: [folder_data]
        },
        images_base_dir: resolved_images_base,
        max_images_to_plot: max_images_to_plot,
        downsample: downsample,
        output_dir: output_dir,
        export_manifest: export_manifest
      )

      {
        request: request,
        footprints: footprints,
        preview: preview,
        folder: preview[:folders][0]
      }
    end

    def render_hourly_mosaics(profile: nil, folder:, subfolders:, images_base_dir: nil,
                              max_images_to_plot: 12, downsample: 6,
                              downsample_native: 1, compressed_scale: 0.35, compressed_quality: 88,
                              export_geojson: true,
                              output_dir: nil, export_manifest: true,
                              pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      preview_bundle = build_hourly_preview(
        profile: profile,
        folder: folder,
        subfolders: subfolders,
        images_base_dir: images_base_dir,
        max_images_to_plot: max_images_to_plot,
        downsample: downsample,
        export_geojson: export_geojson,
        output_dir: output_dir,
        export_manifest: export_manifest,
        pitch_tolerance_deg: pitch_tolerance_deg,
        default_height_agl_m: default_height_agl_m
      )

      profile_name = preview_bundle.dig(:request, :profile_name)

      mosaics = MosaicRenderer.render_hourly(
        preview_result: preview_bundle[:preview],
        profile_name: profile_name,
        output_dir: output_dir || ".",
        downsample_native: downsample_native,
        compressed_scale: compressed_scale,
        compressed_quality: compressed_quality
      )

      preview_bundle.merge(mosaics: mosaics)
    end

    def render_folder_mosaic(profile: nil, folder:, images_dir: nil,
                             max_images_to_plot: 12, downsample: 6,
                             downsample_native: 1, compressed_scale: 0.35, compressed_quality: 88,
                             export_geojson: true,
                             output_dir: nil, export_manifest: true,
                             pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      preview_bundle = build_folder_preview(
        profile: profile,
        folder: folder,
        images_dir: images_dir,
        max_images_to_plot: max_images_to_plot,
        downsample: downsample,
        export_geojson: export_geojson,
        output_dir: output_dir,
        export_manifest: export_manifest,
        pitch_tolerance_deg: pitch_tolerance_deg,
        default_height_agl_m: default_height_agl_m
      )

      profile_name = preview_bundle.dig(:request, :profile_name)

      mosaics = MosaicRenderer.render_hourly(
        preview_result: preview_bundle[:preview],
        profile_name: profile_name,
        output_dir: output_dir || ".",
        downsample_native: downsample_native,
        compressed_scale: compressed_scale,
        compressed_quality: compressed_quality
      )

      {
        request: preview_bundle[:request],
        footprints: preview_bundle[:footprints],
        preview: preview_bundle[:preview],
        mosaics: mosaics,
        folder: mosaics[:folders][0]
      }
    end
  end
end

require_relative "zenmosaic/railtie" if defined?(Rails::Railtie)
