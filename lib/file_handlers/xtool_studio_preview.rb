# frozen_string_literal: true

require "stringio"
require "tempfile"
require "zip"

module FileHandlers
  class XtoolStudioPreview < Base
    COVER_PATH = "resources/project-cover.png"
    MAX_COVER_SIZE = 20 * 1024 * 1024

    INPUT_TYPES = [
      "application/vnd.xtoolstudio",
      "application/x-xtool-studio",
      "application/x-xtool-xs",
      "application/xtool-xs-model-file"
    ].freeze

    OUTPUT_TYPES = [
      "image/png"
    ].freeze

    ENVIRONMENTS = [
      :server
    ].freeze

    def self.priority
      100
    end

    def self.load(io)
      with_local_path(io) do |path|
        png_data = extract_cover(path)
        next nil unless valid_png?(png_data)

        StringIO.new(png_data, "rb")
      end
    rescue Zip::Error, Errno::ENOENT, IOError, ArgumentError => error
      Rails.logger.warn(
        "[manyfold-xtool] Cover extraction failed: " \
          "#{error.class}: #{error.message}"
      )
      nil
    ensure
      io.rewind if io.respond_to?(:rewind)
    end

    def self.extract_cover(path)
      Zip::File.open(path.to_s) do |archive|
        entry = archive.find_entry(COVER_PATH)

        unless entry
          Rails.logger.warn(
            "[manyfold-xtool] #{COVER_PATH} not found in XS archive"
          )
          return nil
        end

        if entry.size > MAX_COVER_SIZE
          Rails.logger.warn(
            "[manyfold-xtool] Cover too large: #{entry.size} bytes"
          )
          return nil
        end

        entry.get_input_stream.read
      end
    end

    private_class_method :extract_cover

    def self.valid_png?(data)
      data.present? &&
        data.bytesize >= 8 &&
        data.start_with?("\x89PNG\r\n\x1A\n".b)
    end

    private_class_method :valid_png?

    def self.with_local_path(io)
      if io.respond_to?(:path) && io.path.present?
        yield io.path
      elsif io.respond_to?(:download)
        tempfile = io.download

        begin
          yield tempfile.path
        ensure
          tempfile.close! if tempfile.respond_to?(:close!)
        end
      else
        Tempfile.create(["xtool-project", ".xs"]) do |tempfile|
          tempfile.binmode
          IO.copy_stream(io, tempfile)
          tempfile.flush

          yield tempfile.path
        end
      end
    end

    private_class_method :with_local_path
  end
end
