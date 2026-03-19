# frozen_string_literal: true

require_relative "lib/zenmosaic/version"

Gem::Specification.new do |spec|
  spec.name = "zenmosaic"
  spec.version = Zenmosaic::VERSION
  spec.authors = ["Marcio"]
  spec.email = ["marcio@example.com"]

  spec.summary = "Gem Rails para extensoes leves de interface e configuracao"
  spec.description = "Zenmosaic adiciona uma integracao simples via Railtie, configuracao global e helper de view para aplicacoes Rails."
  spec.homepage = "https://github.com/marciomr/zenmosaic"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "CHANGELOG.md",
      "LICENSE.txt",
      "README.md",
      "lib/**/*"
    ]
  end

  spec.require_paths = ["lib"]

  spec.add_dependency "exifr", "~> 1.4"
end
