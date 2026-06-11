Gem::Specification.new do |spec|
  spec.name = "jekyll-image-links"
  spec.version = File.read(File.expand_path("lib/jekyll/image_links/version.rb", __dir__))
    .match(/VERSION\s*=\s*"([^"]+)"/)[1]
  spec.authors = ["directsun"]
  spec.email = []

  spec.summary = "Jekyll plugin for clickable polygon regions on images, inspired by 5etools map viewer."
  spec.homepage = "https://github.com/sunflowermans/image-links"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir.glob("{lib,assets}/**/*") + %w[LICENSE README.md]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 3.7", "< 5.0"
end
