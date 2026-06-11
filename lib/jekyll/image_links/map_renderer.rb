require "cgi"
require "digest"
require "json"
require "yaml"

module Jekyll
  module ImageLinks
    class MapRenderer
      PORTABLE_FIGURE = /<figure\b[^>]*\bdata-jil-map="true"[^>]*>[\s\S]*?<\/figure>/i
      PORTABLE_IMAGE = /<img\b[^>]*\bclass="[^"]*\bjil-map-image\b[^"]*"[^>]*\/?>(?:\s*<script\b[^>]*\bclass="jil-regions-data"[^>]*>[\s\S]*?<\/script>)?/i
      REGIONS_SCRIPT = /<script\b[^>]*\bclass="jil-regions-data"[^>]*>([\s\S]*?)<\/script>/i

      class << self
        def portable_markup?(html)
          return true if html.include?('data-jil-map="true"')

          html.scan(PORTABLE_IMAGE).any? { |fragment| portable_image?(fragment) }
        end

        def enhance_html(html, site:, page:, cfg:)
          return html unless portable_markup?(html)

          html = html.gsub(PORTABLE_FIGURE) do |figure_html|
            enhance_portable_markup(figure_html, site: site, page: page, cfg: cfg)
          rescue StandardError => e
            Jekyll.logger.warn("jekyll-image-links:", "Failed to enhance portable figure: #{e.message}")
            figure_html
          end

          html.gsub(PORTABLE_IMAGE) do |image_html|
            next image_html unless portable_image?(image_html)

            enhance_portable_markup(image_html, site: site, page: page, cfg: cfg)
          rescue StandardError => e
            Jekyll.logger.warn("jekyll-image-links:", "Failed to enhance portable image map: #{e.message}")
            image_html
          end
        end

        def render_portable_figure(attrs, site:, page: nil, liquid_context: nil, cfg: {}, regions_body: nil)
          src = attrs["src"].to_s
          width = attrs["width"].to_s
          height = attrs["height"].to_s
          title = attrs["title"]
          alt = attrs["alt"] || title
          regions_file = attrs["file"]
          viewer = attrs["viewer"]
          inline = attrs["inline"]
          labels = attrs["labels"]

          resolved_src = resolve_url(src, site: site, page: page, liquid_context: liquid_context)
          regions_attr = regions_file ? %( data-jil-regions="#{escape_attr(regions_file)}") : ""
          viewer_attr = %( data-jil-viewer="#{viewer}") unless viewer.nil? || viewer.empty?
          inline_attr = %( data-jil-inline="#{inline}") unless inline.nil? || inline.empty?
          labels_attr = %( data-jil-labels="#{labels}") unless labels.nil? || labels.empty?
          title_attr = title ? %( data-jil-title="#{escape_attr(title)}") : ""

          regions_script = ""
          if regions_body && !regions_body.strip.empty? && regions_file.to_s.strip.empty?
            regions_script = %(\n<script type="application/yaml" class="jil-regions-data">#{regions_body.strip}\n</script>)
          end

          <<~HTML.strip
            <img
              class="jil-map-image"
              src="#{escape_attr(resolved_src)}"
              alt="#{escape_attr(alt)}"
              width="#{escape_attr(width)}"
              height="#{escape_attr(height)}"
              loading="lazy"#{title_attr}#{regions_attr}#{viewer_attr}#{inline_attr}#{labels_attr}
            />#{regions_script}
          HTML
        end

        def render_interactive(map_data, viewer:, inline:, labels:, alt:)
          map_json = JSON.generate(map_data)
          id = "jil-map-#{Digest::MD5.hexdigest(map_json)[0, 8]}"
          title = map_data["title"]
          caption_html = title ? %(<div class="jil-caption">#{escape_html(title)}</div>) : ""

          <<~HTML.strip
            <div class="jil-figure" data-jil-image-map="true"><div class="jil-map-host" id="#{id}" data-jil-map="#{escape_attr(map_json)}" data-jil-viewer="#{viewer}" data-jil-inline="#{inline}" data-jil-labels="#{labels}"><img class="jil-map-image" src="#{escape_attr(map_data["src"])}" alt="#{escape_attr(alt)}" width="#{map_data["width"]}" height="#{map_data["height"]}" loading="lazy" /></div>#{caption_html}</div>
          HTML
        end

        private

        def enhance_portable_markup(markup_html, site:, page:, cfg:)
          figure_tag = markup_html[/\A<figure\b[^>]*>/i]
          img_tag = markup_html[/<img\b[^>]*>/i] || ""
          container_tag = figure_tag || img_tag
          container_attrs = parse_html_attrs(container_tag)
          img_attrs = parse_html_attrs(img_tag)

          merged = {
            "src" => container_attrs["data-jil-src"] || img_attrs["src"],
            "width" => container_attrs["data-jil-width"] || img_attrs["width"],
            "height" => container_attrs["data-jil-height"] || img_attrs["height"],
            "title" => container_attrs["data-jil-title"],
            "alt" => img_attrs["alt"],
            "file" => container_attrs["data-jil-regions"] || img_attrs["data-jil-regions"],
            "viewer" => container_attrs["data-jil-viewer"] || img_attrs["data-jil-viewer"],
            "inline" => container_attrs["data-jil-inline"] || img_attrs["data-jil-inline"],
            "labels" => container_attrs["data-jil-labels"] || img_attrs["data-jil-labels"],
          }

          merged["title"] ||= img_attrs["data-jil-title"] || merged["alt"]

          regions_body = markup_html[REGIONS_SCRIPT, 1]
          render_interactive_from_attrs(merged, site: site, page: page, cfg: cfg, regions_body: regions_body)
        end

        def portable_image?(fragment)
          return false unless fragment.match?(/\bclass="[^"]*\bjil-map-image\b/i)

          fragment.include?("data-jil-regions=") ||
            fragment.include?('data-jil-map="true"') ||
            fragment.match?(REGIONS_SCRIPT)
        end

        def render_interactive_from_attrs(attrs, site:, page:, cfg:, regions_body: nil, liquid_context: nil)
          src = resolve_url(attrs["src"], site: site, page: page, liquid_context: liquid_context)
          width = attrs["width"].to_i
          height = attrs["height"].to_i
          title = attrs["title"]
          alt = attrs["alt"] || title
          viewer = parse_bool(attrs["viewer"], default: cfg.fetch("viewer_by_default", true))
          inline = parse_bool(attrs["inline"], default: cfg.fetch("inline_by_default", true))
          labels = parse_bool(attrs["labels"], default: cfg.fetch("labels_by_default", false))

          regions = load_regions(
            site: site,
            regions_file: attrs["file"],
            regions_body: regions_body
          )
          validate_regions!(regions)
          validate_dimensions!(width, height, src)

          map_data = {
            "src" => src,
            "width" => width,
            "height" => height,
            "title" => title,
            "regions" => normalize_regions(regions, site: site, page: page, liquid_context: liquid_context),
          }

          render_interactive(map_data, viewer: viewer, inline: inline, labels: labels, alt: alt)
        end

        def load_regions(site:, regions_file:, regions_body:)
          if regions_file && !regions_file.to_s.strip.empty?
            path = regions_file.to_s
            full_path = Jekyll.sanitized_path(site.source, path)
            raise ArgumentError, "image_map file not found: #{path}" unless File.file?(full_path)

            data = YAML.safe_load(File.read(full_path), permitted_classes: [Date, Time, Symbol], aliases: true)
            extract_regions_array(data)
          else
            return [] if regions_body.to_s.strip.empty?

            parsed = YAML.safe_load(regions_body, permitted_classes: [Date, Time, Symbol], aliases: true)
            extract_regions_array(parsed)
          end
        end

        def extract_regions_array(data)
          case data
          when Hash
            data["regions"] || data[:regions] || []
          when Array
            data
          else
            raise ArgumentError, "image_map regions must be a YAML list or a mapping with regions:"
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
          raise ArgumentError, "image_map requires width and height attributes" unless width.positive? && height.positive?
          raise ArgumentError, "image_map requires src attribute" if src.to_s.strip.empty?
        end

        def normalize_regions(regions, site:, page:, liquid_context: nil)
          regions.map do |region|
            region = stringify_keys(region)
            {
              "href" => resolve_url(region["href"], site: site, page: page, liquid_context: liquid_context),
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

        def resolve_url(url, site:, page: nil, liquid_context: nil)
          return "" if url.nil?

          url = Liquid::Template.parse(url.to_s).render(liquid_context).strip if liquid_context
          url = url.to_s.strip
          return url if url.start_with?("http://", "https://", "mailto:", "#")

          baseurl = site.baseurl.to_s
          baseurl = "" if baseurl == "/"

          page_url = page_url_for(page)

          if url.start_with?("/")
            "#{baseurl}#{url}"
          else
            page_dir = page_url ? File.dirname(page_url) : ""
            "#{baseurl}#{File.join(page_dir, url)}"
          end
        end

        def page_url_for(page)
          return page.url if page.respond_to?(:url) && page.url
          return page["url"] if page.respond_to?(:[]) && page["url"]

          nil
        end

        def parse_bool(value, default:)
          return default if value.nil? || value.to_s.empty?
          %w[true 1 yes on].include?(value.to_s.downcase)
        end

        def parse_html_attrs(tag_open)
          attrs = {}
          tag_open.scan(/([\w-]+)\s*=\s*"([^"]*)"/) { |key, value| attrs[key] = value }
          tag_open.scan(/([\w-]+)\s*=\s*'([^']*)'/) { |key, value| attrs[key] = value }
          attrs
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
end
