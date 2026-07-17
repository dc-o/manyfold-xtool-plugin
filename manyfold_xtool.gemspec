require_relative "lib/manyfold_xtool/version"

Gem::Specification.new do |spec|
  spec.name = "manyfold xtool File Handler"
  spec.version = ManyfoldXtool::VERSION
  spec.authors = ["Korbinian Ober"]
  spec.email = ["korbinian@dc-o.de"]
  spec.homepage = "https://github.com/dc-o/manyfold-xtool-plugin"
  spec.summary = "Adds support for xTool Studio based files."
  spec.description = "This plugin adds support for xTool Studio based files."
  spec.license = "MIT"
  spec.metadata = {
    "manyfold_version" => ">= 0.146.0",
  }
  spec.add_dependency "rubyzip", "~> 3.0"
end
