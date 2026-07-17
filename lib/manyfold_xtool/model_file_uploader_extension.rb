# frozen_string_literal: true

module ManyfoldXtool
  module ModelFileUploaderExtension
    def generate_location(
      io,
      record: nil,
      derivative: nil,
      metadata: nil,
      **options
    )
      location = super

      return location unless xtool_preview?(
        record: record,
        derivative: derivative
      )

      location.sub(/\.xs\z/i, ".png")
    end

    private

    def xtool_preview?(record:, derivative:)
      return false if record.nil?
      return false if derivative.nil?
      return false unless derivative.to_sym == :render

      path =
        if record.respond_to?(:path)
          record.path.to_s
        elsif record.respond_to?(:filename)
          record.filename.to_s
        else
          ""
        end

      File.extname(path).casecmp?(".xs")
    end
  end
end