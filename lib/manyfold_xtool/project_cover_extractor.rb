# frozen_string_literal: true

require "zip"

module ManyfoldXtool
  class ProjectCoverExtractor
    COVER_PATH = "resources/project-cover.png"
    MAX_COVER_SIZE = 20 * 1024 * 1024

    class CoverNotFoundError < StandardError; end

    class CoverTooLargeError < StandardError; end

    def self.extract(source_path)
      new(source_path).extract
    end

    def initialize(source_path)
      @source_path = Pathname(source_path)
    end

    def extract
      Zip::File.open(source_path.to_s) do |archive|
        entry = archive.find_entry(COVER_PATH)
        raise CoverNotFoundError, "#{COVER_PATH} ist nicht im XS-Archiv enthalten" unless entry

        validate_entry!(entry)

        entry.get_input_stream.read
      end
    rescue Zip::Error => error
      raise CoverNotFoundError, "XS-Datei konnte nicht als ZIP geöffnet werden: #{error.message}"
    end

    private

    attr_reader :source_path

    def validate_entry!(entry)
      return if entry.size <= MAX_COVER_SIZE

      raise CoverTooLargeError,
            "Das eingebettete Cover überschreitet #{MAX_COVER_SIZE} Bytes"
    end
  end
end