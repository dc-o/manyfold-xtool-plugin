# frozen_string_literal: true

require "stringio"
require "tempfile"
require "zip"

module ManyfoldXtool
  class DerivativeProcessor
    COVER_PATH = "resources/project-cover.png"
    MAX_COVER_SIZE = 20 * 1024 * 1024
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b

    XS_MIME_TYPES = [
      "application/vnd.xtoolstudio",
      "application/x-xtool-studio",
      "application/x-xtool-xs",
      "application/xtool-xs-model-file"
    ].freeze

    def initialize(attacher:, original_processor:)
      @attacher = attacher
      @original_processor = original_processor
    end

    def call(original)
      derivatives = call_original_processor(original)
      derivatives = {} unless derivatives.is_a?(Hash)

      return derivatives unless xtool_studio_file?

      Rails.logger.info(
        "[manyfold-xtool] Processing XS cover for #{filename.inspect}"
      )

      cover_data = extract_cover(original)

      unless cover_data
        Rails.logger.warn(
          "[manyfold-xtool] No usable project cover found"
        )

        return derivatives
      end

      render = build_render(cover_data)

      result = derivatives.merge(
        render: render
      )

      attach_cover_safely(cover_data)

      Rails.logger.info(
        "[manyfold-xtool] Returning render derivative, " \
          "#{cover_data.bytesize} bytes"
      )

      result
    rescue StandardError => error
      Rails.logger.error(
        "[manyfold-xtool] Derivative processing failed: " \
          "#{error.class}: #{error.message}"
      )

      Rails.logger.error(error.full_message)

      derivatives || {}
    ensure
      original.rewind if original.respond_to?(:rewind)
    end

    private

    attr_reader :attacher, :original_processor

    def call_original_processor(original)
      return {} unless original_processor

      original.rewind if original.respond_to?(:rewind)

      result = attacher.instance_exec(
        original,
        &original_processor
      )

      result.is_a?(Hash) ? result : {}
    ensure
      original.rewind if original.respond_to?(:rewind)
    end

    def build_render(cover_data)
      render = StringIO.new(cover_data)
      render.binmode
      render.rewind
      render
    end

    def attach_cover_safely(cover_data)
      source_file = attacher.record

      unless source_file.is_a?(ModelFile)
        Rails.logger.warn(
          "[manyfold-xtool] Attacher record is not a ModelFile"
        )

        return
      end

      ManyfoldXtool::AttachProjectCover.new(
        source_file: source_file,
        png_data: cover_data
      ).call
    rescue StandardError => error
      Rails.logger.error(
        "[manyfold-xtool] Separate cover attachment failed, " \
          "but render generation continues: " \
          "#{error.class}: #{error.message}"
      )

      Rails.logger.error(error.full_message)
    end

    def xtool_studio_file?
      File.extname(filename).casecmp?(".xs") ||
        XS_MIME_TYPES.include?(mime_type)
    end

    def filename
      current_record = attacher.record

      if current_record.respond_to?(:filename)
        record_filename = current_record.filename.to_s

        return record_filename unless record_filename.empty?
      end

      attachment_metadata["filename"].to_s
    end

    def mime_type
      attachment_metadata["mime_type"].to_s
    end

    def attachment_metadata
      current_record = attacher.record

      if current_record.respond_to?(:attachment_attacher)
        attachment =
          current_record.attachment_attacher.file

        return attachment.metadata.to_h if attachment
      end

      current_file = attacher.file

      return current_file.metadata.to_h if
        current_file.respond_to?(:metadata)

      {}
    end

    def extract_cover(original)
      Tempfile.create(
        ["xtool-project", ".xs"]
      ) do |tempfile|
        tempfile.binmode

        original.rewind if original.respond_to?(:rewind)
        IO.copy_stream(original, tempfile)

        tempfile.flush
        tempfile.rewind

        Zip::File.open(tempfile.path) do |archive|
          entry = archive.find_entry(COVER_PATH)

          unless entry
            Rails.logger.warn(
              "[manyfold-xtool] #{COVER_PATH} not found"
            )

            return nil
          end

          if entry.size > MAX_COVER_SIZE
            Rails.logger.warn(
              "[manyfold-xtool] Embedded cover is too large: " \
                "#{entry.size} bytes"
            )

            return nil
          end

          data = entry.get_input_stream.read

          unless data.start_with?(PNG_SIGNATURE)
            Rails.logger.warn(
              "[manyfold-xtool] Embedded cover is not a valid PNG"
            )

            return nil
          end

          data
        end
      end
    end
  end
end