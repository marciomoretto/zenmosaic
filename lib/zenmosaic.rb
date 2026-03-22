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

    def build_processing_request(profile: nil, profile_data: nil, paths:)
      resolved_profile = resolve_profile(profile: profile, profile_data: profile_data)

      ProcessingRequest.new(
        profile_name: resolved_profile[:profile_name],
        paths: paths,
        profile: resolved_profile[:profile],
        images_root: configuration.images_root
      )
    end

    def extract_files_metadata(profile: nil, profile_data: nil, paths:)
      metadata = extract_paths_metadata(profile: profile, profile_data: profile_data, paths: paths)

      {
        request: metadata[:request],
        images: metadata[:collection][:rows]
      }
    end

    alias extract_batch_metadata extract_files_metadata

    def extract_image_metadata(path)
      MetadataExtractor.extract_image_metadata(path)
    end

    def build_footprints(profile: nil, profile_data: nil, paths:,
                         export_geojson: false, output_dir: nil,
                         pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      metadata = extract_paths_metadata(profile: profile, profile_data: profile_data, paths: paths)

      result = FootprintPipeline.build_hourly(
        profile_name: metadata[:request][:profile_name],
        profile: metadata[:request][:profile],
        collections: [metadata[:collection]],
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
        collection: result[:collections][0]
      }
    end

    def extract_paths_metadata(profile: nil, profile_data: nil, paths:)
      request = build_processing_request(profile: profile, profile_data: profile_data, paths: paths)
      expanded_paths = request.paths

      validate_input_paths!(expanded_paths)
      input_base_dir = common_base_dir(expanded_paths)

      resolved_profile = resolve_profile(profile: profile, profile_data: profile_data)

      rows = expanded_paths.map do |path|
        relative_name = path.sub(%r{^#{Regexp.escape(input_base_dir)}/?}, "")
        metadata = MetadataExtractor.extract_image_metadata(path)
        metadata.delete(:file_name)
        metadata.delete("file_name")

        metadata.merge(
          filename: relative_name,
          collection: "."
        )
      end

      {
        request: {
          profile_name: resolved_profile[:profile_name],
          profile: resolved_profile[:profile],
          input_paths: expanded_paths,
          input_base_dir: input_base_dir
        },
        collection: {
          collection: ".",
          collection_path: input_base_dir,
          images_count: rows.length,
          rows: rows
        }
      }
    end

    def build_preview(profile: nil, profile_data: nil, paths:,
                             max_images_to_plot: 12, downsample: 6,
                             export_geojson: false,
                             output_dir: nil, export_manifest: true,
                             pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      footprints = build_footprints(
        profile: profile,
        profile_data: profile_data,
        paths: paths,
        export_geojson: export_geojson,
        output_dir: output_dir,
        pitch_tolerance_deg: pitch_tolerance_deg,
        default_height_agl_m: default_height_agl_m
      )

      collection_data = footprints[:collection]
      request = footprints[:request]

      preview = PreviewManifest.build_hourly(
        footprints_result: {
          profile_name: footprints[:profile_name],
          collections: [collection_data]
        },
        images_base_dir: request[:input_base_dir] || "/",
        max_images_to_plot: max_images_to_plot,
        downsample: downsample,
        output_dir: output_dir,
        export_manifest: export_manifest
      )

      {
        request: request,
        footprints: footprints,
        preview: preview,
        collection: preview[:collections][0]
      }
    end

    def render_mosaic(profile: nil, profile_data: nil, paths:,
                             max_images_to_plot: 12, downsample: 6,
                             downsample_native: 1, compressed_scale: 0.35, compressed_quality: 88,
                             export_geojson: true,
                             output_dir: nil, export_manifest: true,
                             pitch_tolerance_deg: 2.0, default_height_agl_m: 70.0)
      preview_bundle = build_preview(
        profile: profile,
        profile_data: profile_data,
        paths: paths,
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
        collection: mosaics[:collections][0]
      }
    end

    private

    def resolve_profile(profile:, profile_data: nil)
      if profile_data
        clean_name = profile.to_s.strip

        return {
          profile_name: clean_name.empty? ? "custom" : clean_name,
          profile: profile_data
        }
      end

      profile_name = profile.to_s.strip
      profile_name = "air3s_wide_70m_rj" if profile_name.empty?

      profiles = DefaultProfiles.all
      raise Error, "profile '#{profile_name}' nao existe" unless profiles.key?(profile_name)

      {
        profile_name: profile_name,
        profile: profiles.fetch(profile_name)
      }
    end

    def validate_input_paths!(paths)
      paths.each do |path|
        raise Error, "arquivo '#{path}' nao existe" unless File.file?(path)

        extension = File.extname(path).downcase
        next if MetadataExtractor::IMAGE_EXTENSIONS.include?(extension)

        raise Error, "arquivo '#{path}' nao e uma imagem suportada"
      end
    end

    def common_base_dir(paths)
      expanded = paths.map { |path| File.expand_path(path) }
      return File.dirname(expanded.first) if expanded.length == 1

      segments = expanded.map { |path| File.dirname(path).split(File::SEPARATOR) }
      common_segments = segments.shift

      segments.each do |parts|
        index = 0
        limit = [common_segments.length, parts.length].min
        index += 1 while index < limit && common_segments[index] == parts[index]
        common_segments = common_segments.first(index)
      end

      candidate = common_segments.join(File::SEPARATOR)
      candidate = File::SEPARATOR if candidate.empty?
      File.expand_path(candidate)
    end
  end
end

require_relative "zenmosaic/railtie" if defined?(Rails::Railtie)
