module Jekyll
  module ImageLinks
    module Hooks
      def self.register!
        Jekyll::Hooks.register(%i[pages documents], :post_render) do |doc|
          site = doc.site
          cfg = (site.config["image_links"] || {})
          next if cfg["enabled"] == false
          next unless doc.respond_to?(:output_ext) && doc.output_ext == ".html"

          html = doc.output.to_s
          next unless html.include?('data-jil-image-map="true"')

          assets_path = cfg["assets_path"] || "/assets/jekyll-image-links"
          assets_path = "/#{assets_path}" unless assets_path.start_with?("/")

          begin
            doc.output = inject_assets(html, assets_path: assets_path, site: site, cfg: cfg)
          rescue StandardError => e
            Jekyll.logger.warn("jekyll-image-links:", "Failed to process #{doc.relative_path}: #{e.class}: #{e.message}")
          end
        end
      end

      def self.build_jil_config(site, cfg)
        return { useHoverPopup: false } if cfg["use_hover_popup"] == false
        return { useHoverPopup: true } if cfg["use_hover_popup"] == true

        hover_cfg = site.config["hover_popup"] || {}
        return { useHoverPopup: false } if hover_cfg["enabled"] == false

        # Auto: omit useHoverPopup and detect window.JekyllHoverPopup at runtime.
        {}
      end

      def self.inject_assets(html, assets_path:, site:, cfg:)
        return html if html.include?('data-jil-root="true"')

        jil_config = build_jil_config(site, cfg)

        tags = <<~HTML
          <script>
            window.__JIL_CONFIG__ = #{jil_config.to_json};
          </script>
          <link rel="stylesheet" href="#{assets_path}/image_links.css" />
          <script defer src="#{assets_path}/image_links.js" data-jil-root="true"></script>
        HTML

        if html.include?("</body>")
          html.sub("</body>", "#{tags}\n</body>")
        else
          "#{html}\n#{tags}\n"
        end
      end
    end
  end
end

Jekyll::ImageLinks::Hooks.register!
