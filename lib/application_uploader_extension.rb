# frozen_string_literal: true

require "stringio"
require "tempfile"
require "zip"

module ManyfoldXtool
  module ApplicationUploaderExtension
    COVER_PATH = "resources/project-cover.png"
    MAX_COVER_SIZE = 20 * 1024 * 1024
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b

    def generate_derivatives(io, *args, **kwargs)
      unless xtool_studio_file?
        Rails.logger.debug(
          "[manyfold-xtool] Not an XS file, skipping xTool processor"
        )

        return {}
      end

      Rails.logger.info(
        "[manyfold-xtool] Generating derivative for #{xtool_filename.inspect}"
      )

      cover_data = extract_xtool_cover(io)

      unless cover_data
        Rails.logger.warn(
          "[manyfold-xtool] No usable project cover found"
        )

        return {}
      end

      preview = StringIO.new(cover_data)
      preview.binmode
      preview.rewind

      Rails.logger.info(
        "[manyfold-xtool] Returning preview derivative, " \
          "#{cover_data.bytesize} bytes"
      )

      {
        preview: preview
      }
    rescue StandardError => error
      Rails.logger.error(
        "[manyfold-xtool] Derivative generation failed: " \
          "#{error.class}: #{error.message}"
      )

      Rails.logger.error(
        error.backtrace.first(20).join("\n")
      )

      {}
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    private

    def xtool_studio_file?
      File.extname(xtool_filename).casecmp?(".xs") ||
        xtool_mime_types.include?(xtool_mime_type)
    end

    def xtool_mime_types
      [
        "application/vnd.xtoolstudio",
        "application/x-xtool-studio",
        "application/x-xtool-xs",
        "application/xtool-xs-model-file"
      ]
    end

    def xtool_filename
      metadata = xtool_metadata

      filename = metadata["filename"].to_s
      return filename unless filename.empty?

      if respond_to?(:record, true)
        current_record = record

        return current_record.path.to_s if current_record.respond_to?(:path)
        return current_record.filename.to_s if current_record.respond_to?(:filename)
        return current_record.name.to_s if current_record.respond_to?(:name)
      end

      ""
    end

    def xtool_mime_type
      xtool_metadata["mime_type"].to_s
    end

    def xtool_metadata
      current_file = file if respond_to?(:file)

      return current_file.metadata || {} if current_file.respond_to?(:metadata)

      {}
    end

    def extract_xtool_cover(io)
      Tempfile.create(["xtool-project", ".xs"]) do |tempfile|
        tempfile.binmode

        io.rewind if io.respond_to?(:rewind)
        IO.copy_stream(io, tempfile)

        tempfile.flush
        tempfile.rewind

        Rails.logger.debug(
          "[manyfold-xtool] Temporary archive size: #{tempfile.size}"
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
              "[manyfold-xtool] Cover exceeds maximum size: " \
                "#{entry.size} bytes"
            )

            return nil
          end

          data = entry.get_input_stream.read

          unless data.start_with?(PNG_SIGNATURE)
            Rails.logger.warn(
              "[manyfold-xtool] Embedded cover is not a PNG"
            )

            return nil
          end

          data
        end
      end
    end
  end
end