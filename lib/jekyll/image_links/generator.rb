module Jekyll
  module ImageLinks
    class Generator < Jekyll::Generator
      safe true
      priority :low

      def generate(site)
        cfg = (site.config["image_links"] || {})
        return if cfg["enabled"] == false

        assets_path = cfg["assets_path"] || "/assets/jekyll-image-links"
        assets_path = "/#{assets_path}" unless assets_path.start_with?("/")

        asset_dir = File.expand_path("../../../assets/jekyll-image-links", __dir__)

        files = {
          "image_links.js" => File.join(asset_dir, "image_links.js"),
          "image_links.css" => File.join(asset_dir, "image_links.css"),
        }

        files.each do |name, source_path|
          next unless File.file?(source_path)
          site.static_files << AssetFile.new(
            site,
            site.source,
            assets_path.sub(%r{\A/}, ""),
            name,
            source_path: source_path
          )
        end
      end
    end
  end
end
