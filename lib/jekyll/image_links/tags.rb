module Jekyll
  module ImageLinks
    class ImageMapTag < Liquid::Block
      def initialize(tag_name, markup, tokens)
        super
        @attrs = parse_attrs(markup)
      end

      def blank?
        false
      end

      def render(context)
        site = context.registers[:site]
        cfg = (site.config["image_links"] || {})
        regions_body = @attrs["file"] ? nil : super

        figure = MapRenderer.render_portable_figure(
          @attrs,
          site: site,
          page: context.registers[:page],
          liquid_context: context,
          cfg: cfg,
          regions_body: regions_body
        )

        <<~HTML
          {::nomarkdown}
          #{figure}
          {:/nomarkdown}
        HTML
      end

      private

      def parse_attrs(markup)
        attrs = {}
        markup.scan(/(\w+)\s*=\s*"([^"]*)"/) { |key, value| attrs[key] = value }
        markup.scan(/(\w+)\s*=\s*'([^']*)'/) { |key, value| attrs[key] = value }
        attrs["file"] ||= markup[/\Afile:\s*(\S+)/, 1] if markup.include?("file:")
        attrs
      end
    end
  end
end

Liquid::Template.register_tag("image_map", Jekyll::ImageLinks::ImageMapTag)
