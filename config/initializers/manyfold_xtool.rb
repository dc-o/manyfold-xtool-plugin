# frozen_string_literal: true

require_relative "../../lib/manyfold_xtool/derivative_processor"
require_relative "../../lib/file_handlers/xtool_studio_preview"
require_relative "../../lib/manyfold_xtool/model_file_uploader_extension"
require_relative "../../lib/manyfold_xtool/model_file_attacher_extension"

Rails.application.config.after_initialize do

  extension = ManyfoldXtool::ModelFileUploaderExtension

  unless ModelFileUploader.ancestors.include?(extension)
    ModelFileUploader.prepend(extension)

    Rails.logger.info(
      "[manyfold-xtool] ModelFileUploader extension installed"
    )
  end

  attacher_class = ModelFileUploader::Attacher

  unless attacher_class.instance_variable_defined?(
    :@manyfold_xtool_processor_installed
  )
    original_processor = attacher_class.derivatives

    attacher_class.derivatives do |original, *args, **options|
      processor = ManyfoldXtool::DerivativeProcessor.new(
        attacher: self,
        original_processor: original_processor
      )

      processor.call(
        original,
        *args,
        **options
      )
    end

    attacher_class.instance_variable_set(
      :@manyfold_xtool_processor_installed,
      true
    )

    Rails.logger.info(
      "[manyfold-xtool] Derivative processor installed"
    )
  end

  attacher_extension =
    ManyfoldXtool::ModelFileAttacherExtension

  unless ModelFileUploader::Attacher.ancestors.include?(
    attacher_extension
  )
    ModelFileUploader::Attacher.prepend(
      attacher_extension
    )

    Rails.logger.info(
      "[manyfold-xtool] ModelFile attacher extension installed"
    )
  end

  handler = FileHandlers::XtoolStudioPreview

  unless FileHandlers::ALL_HANDLERS.include?(handler)
    FileHandlers::ALL_HANDLERS << handler

    Rails.logger.info(
      "[manyfold-xtool] File handler registered"
    )
  end

  Rails.cache.clear
end