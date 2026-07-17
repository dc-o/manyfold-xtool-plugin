# frozen_string_literal: true

require "stringio"

module ManyfoldXtool
  class AttachProjectCover
    def initialize(source_file:, png_data:)
      @source_file = source_file
      @png_data = png_data
    end

    def call
      validate_input

      cover_file = find_or_initialize_cover_file
      image_io = build_image_io

      cover_file.attachment_attacher.assign(image_io)
      cover_file.save!

      source_file.model.update_column(
        :preview_file_id,
        cover_file.id
      )

      Rails.logger.info(
        "[manyfold-xtool] Created cover ModelFile " \
          "#{cover_file.id} with filename #{cover_filename.inspect}"
      )

      Rails.logger.info(
        "[manyfold-xtool] Set cover ModelFile #{cover_file.id} " \
          "as preview for Model #{source_file.model.id}"
      )

      cover_file
    rescue StandardError => error
      Rails.logger.error(
        "[manyfold-xtool] Creating cover ModelFile failed: " \
          "#{error.class}: #{error.message}"
      )

      Rails.logger.error(error.full_message)

      raise
    end

    private

    attr_reader :source_file, :png_data

    def validate_input
      raise ArgumentError, "Source ModelFile is missing" unless source_file
      raise ArgumentError, "Source Model is missing" unless source_file.model

      if png_data.nil? || png_data.empty?
        raise ArgumentError, "PNG data is missing"
      end
    end

    def find_or_initialize_cover_file
      association = source_file.model.model_files

      if ModelFile.column_names.include?("filename")
        association.find_or_initialize_by(
          filename: cover_filename
        )
      elsif ModelFile.column_names.include?("name")
        association.find_or_initialize_by(
          name: cover_filename
        )
      else
        find_cover_by_attachment_filename(association)
      end
    end

    def find_cover_by_attachment_filename(association)
      existing = association.find do |model_file|
        attached_filename(model_file) == cover_filename
      end

      existing || association.build
    end

    def source_filename
      metadata_filename =
        source_file
          .attachment_attacher
          .file
          .metadata
          .to_h["filename"]
          .to_s

      return metadata_filename unless metadata_filename.empty?

      if source_file.respond_to?(:filename)
        return source_file.filename.to_s
      end

      if source_file.respond_to?(:name)
        return source_file.name.to_s
      end

      raise ArgumentError, "Could not determine XS filename"
    end

    def cover_filename
      extension = File.extname(source_filename)

      basename = File.basename(
        source_filename,
        extension
      )

      "#{basename}-cover.png"
    end

    def attached_filename(model_file)
      attached_file = model_file.attachment_attacher.file

      return "" unless attached_file

      attached_file.metadata.to_h["filename"].to_s
    end

    def build_image_io
      image_io = StringIO.new(png_data)
      image_io.binmode
      image_io.rewind

      filename = cover_filename

      image_io.define_singleton_method(
        :original_filename
      ) do
        filename
      end

      image_io.define_singleton_method(
        :content_type
      ) do
        "image/png"
      end

      image_io
    end
  end
end