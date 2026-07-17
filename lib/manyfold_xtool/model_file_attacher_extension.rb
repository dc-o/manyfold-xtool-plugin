# frozen_string_literal: true

module ManyfoldXtool
  module ModelFileAttacherExtension
    def create_derivatives(*arguments, **options)
      result = super

      set_xtool_model_preview(result)

      result
    rescue StandardError => error
      Rails.logger.error(
        "[manyfold-xtool] Automatic preview selection failed: " \
          "#{error.class}: #{error.message}"
      )

      Rails.logger.error(
        error.backtrace.first(20).join("\n")
      )

      raise
    end

    private

    def set_xtool_model_preview(result)
      return unless xtool_record?
      return unless render_generated?(result)

      model_file = record
      model = model_file.model

      return if model.nil?

      if model.preview_file_id.present?
        Rails.logger.debug(
          "[manyfold-xtool] Model #{model.id} already has preview " \
            "ModelFile #{model.preview_file_id}"
        )

        return
      end

      model.update_column(
        :preview_file_id,
        model_file.id
      )

      Rails.logger.info(
        "[manyfold-xtool] Set ModelFile #{model_file.id} as preview " \
          "for Model #{model.id}"
      )
    end

    def xtool_record?
      return false unless record

      path =
        if record.respond_to?(:path)
          record.path.to_s
        elsif record.respond_to?(:filename)
          record.filename.to_s
        else
          original_filename
        end

      File.extname(path).casecmp?(".xs")
    end

    def original_filename
      return "" unless file.respond_to?(:metadata)

      file.metadata.to_h["filename"].to_s
    end

    def render_generated?(result)
      generated = result.to_h

      generated.key?(:render) ||
        generated.key?("render") ||
        stored_render_available?
    end

    def stored_render_available?
      current_derivatives = derivatives.to_h

      current_derivatives.key?(:render) ||
        current_derivatives.key?("render")
    end
  end
end