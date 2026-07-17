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

    def call(original, *args, **options)
      derivatives = call_original_processor(
        original,
        *args,
        **options
      )

      derivatives = {} unless derivatives.is_a?(Hash)

      return derivatives unless xtool_studio_file?

      Rails.logger.info(
        "[manyfold-xtool] Processing XS cover for " \
          "#{filename.inspect}"
      )

      cover_data = extract_cover(original)
      return derivatives unless cover_data

      preview = StringIO.new(cover_data)
      preview.binmode
      preview.rewind

      Rails.logger.info(
        "[manyfold-xtool] Adding preview derivative, " \
          "#{cover_data.bytesize} bytes"
      )

      derivatives.merge(
        render: preview
      )
    rescue StandardError => error
      Rails.logger.error(
        "[manyfold-xtool] Derivative processor failed: " \
          "#{error.class}: #{error.message}"
      )

      Rails.logger.error(
        error.backtrace.first(20).join("\n")
      )

      derivatives || {}
    ensure
      original.rewind if original.respond_to?(:rewind)
    end

    private

    attr_reader :attacher, :original_processor

    def call_original_processor(original, *args, **options)
      original.rewind if original.respond_to?(:rewind)

      if original_processor.nil?
        {}
      elsif options.empty?
        attacher.instance_exec(
          original,
          *args,
          &original_processor
        )
      else
        attacher.instance_exec(
          original,
          *args,
          **options,
          &original_processor
        )
      end
    ensure
      original.rewind if original.respond_to?(:rewind)
    end

    def xtool_studio_file?
      File.extname(filename).casecmp?(".xs") ||
        XS_MIME_TYPES.include?(mime_type)
    end

    def filename
      value = metadata["filename"].to_s
      return value unless value.empty?

      record = attacher.record

      return record.path.to_s if record.respond_to?(:path)
      return record.filename.to_s if record.respond_to?(:filename)
      return record.name.to_s if record.respond_to?(:name)

      ""
    end

    def mime_type
      metadata["mime_type"].to_s
    end

    def metadata
      file = attacher.file

      return {} unless file.respond_to?(:metadata)

      file.metadata || {}
    end

    def extract_cover(original)
      Tempfile.create(["xtool-project", ".xs"]) do |tempfile|
        tempfile.binmode

        original.rewind if original.respond_to?(:rewind)
        IO.copy_stream(original, tempfile)

        tempfile.flush
        tempfile.rewind

        Rails.logger.debug(
          "[manyfold-xtool] Temporary XS archive size: " \
            "#{tempfile.size}"
        )

        Zip::File.open(tempfile.path) do |archive|
          entry = archive.find_entry(COVER_PATH)

          unless entry
            Rails.logger.warn(
              "[manyfold-xtool] #{COVER_PATH} not found"
            )

            Rails.logger.debug(
              "[manyfold-xtool] Archive entries: " \
                "#{archive.entries.map(&:name).inspect}"
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