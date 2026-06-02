require "cgi"
require "digest"
require "json"
require "yaml"

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

        src = resolve_url(@attrs["src"], context)
        width = @attrs["width"]&.to_i
        height = @attrs["height"]&.to_i
        title = @attrs["title"]
        alt = @attrs["alt"] || title
        viewer = parse_bool(@attrs["viewer"], default: cfg.fetch("viewer_by_default", true))
        inline = parse_bool(@attrs["inline"], default: cfg.fetch("inline_by_default", true))
        labels = parse_bool(@attrs["labels"], default: cfg.fetch("labels_by_default", false))

        body = @attrs["file"] ? "" : super
        regions = load_regions(context, body)
        validate_regions!(regions)
        validate_dimensions!(width, height, src)

        map_data = {
          "src" => src,
          "width" => width,
          "height" => height,
          "title" => title,
          "regions" => normalize_regions(regions, context),
        }

        map_json = JSON.generate(map_data)
        id = "jil-map-#{Digest::MD5.hexdigest(map_json)[0, 8]}"
        caption_html = title ? %(<div class="jil-caption">#{escape_html(title)}</div>) : ""

        <<~HTML
          {::nomarkdown}
          <div class="jil-figure" data-jil-image-map="true"><div class="jil-map-host" id="#{id}" data-jil-map="#{escape_attr(map_json)}" data-jil-viewer="#{viewer}" data-jil-inline="#{inline}" data-jil-labels="#{labels}"><img class="jil-map-image" src="#{escape_attr(src)}" alt="#{escape_attr(alt)}" width="#{width}" height="#{height}" loading="lazy" /></div>#{caption_html}</div>
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

      def parse_bool(value, default:)
        return default if value.nil? || value.empty?
        %w[true 1 yes on].include?(value.to_s.downcase)
      end

      def load_regions(context, body)
        if @attrs["file"]
          path = @attrs["file"]
          full_path = Jekyll.sanitized_path(context.registers[:site].source, path)
          raise ArgumentError, "image_map file not found: #{path}" unless File.file?(full_path)

          data = YAML.safe_load(File.read(full_path), permitted_classes: [Date, Time, Symbol], aliases: true)
          case data
          when Hash
            data["regions"] || data[:regions] || []
          when Array
            data
          else
            raise ArgumentError, "image_map file must contain a regions array or a mapping with regions:"
          end
        else
          return [] if body.strip.empty?

          parsed = YAML.safe_load(body, permitted_classes: [Date, Time, Symbol], aliases: true)
          case parsed
          when Array
            parsed
          when Hash
            parsed["regions"] || parsed[:regions] || []
          else
            raise ArgumentError, "image_map block must contain a YAML list of regions"
          end
        end
      end

      def validate_regions!(regions)
        raise ArgumentError, "image_map requires at least one region" if regions.nil? || regions.empty?

        regions.each_with_index do |region, index|
          region = stringify_keys(region)
          raise ArgumentError, "region #{index + 1} is missing href" if region["href"].to_s.strip.empty?
          raise ArgumentError, "region #{index + 1} is missing points" unless region["points"].is_a?(Array) && !region["points"].empty?
        end
      end

      def validate_dimensions!(width, height, src)
        raise ArgumentError, "image_map requires width and height attributes" unless width&.positive? && height&.positive?
        raise ArgumentError, "image_map requires src attribute" if src.to_s.strip.empty?
      end

      def normalize_regions(regions, context)
        regions.map do |region|
          region = stringify_keys(region)
          {
            "href" => resolve_url(region["href"], context),
            "title" => region["title"] || region["label"] || region["name"],
            "label" => region["label"] || region["title"] || region["name"],
            "points" => normalize_points(region["points"]),
          }
        end
      end

      def normalize_points(points)
        points.map do |point|
          case point
          when Array
            [point[0].to_i, point[1].to_i]
          when Hash
            [(point["x"] || point[:x]).to_i, (point["y"] || point[:y]).to_i]
          else
            raise ArgumentError, "image_map points must be [x, y] pairs"
          end
        end
      end

      def resolve_url(url, context)
        return "" if url.nil?

        url = Liquid::Template.parse(url).render(context)
        url = url.strip
        return url if url.start_with?("http://", "https://", "mailto:", "#")

        site = context.registers[:site]
        baseurl = site.baseurl.to_s
        baseurl = "" if baseurl == "/"

        if url.start_with?("/")
          "#{baseurl}#{url}"
        else
          page = context.registers[:page]
          page_dir = page && page["url"] ? File.dirname(page["url"]) : ""
          "#{baseurl}#{File.join(page_dir, url)}"
        end
      end

      def stringify_keys(value)
        return value unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, val), out|
          out[key.to_s] = val
        end
      end

      def escape_attr(value)
        value.to_s
          .gsub("&", "&amp;")
          .gsub('"', "&quot;")
          .gsub("<", "&lt;")
      end

      def escape_html(value)
        CGI.escapeHTML(value.to_s)
      end
    end
  end
end

Liquid::Template.register_tag("image_map", Jekyll::ImageLinks::ImageMapTag)
