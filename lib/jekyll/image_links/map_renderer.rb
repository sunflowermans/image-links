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
          title = attrs["title"]
          alt = attrs["alt"] || title
          regions_file = attrs["file"]
          viewer = attrs["viewer"]
          inline = attrs["inline"]
          labels = attrs["labels"]

          resolved_src = resolve_url(src, site: site, page: page, liquid_context: liquid_context)
          map_source = load_map_source(
            site: site,
            regions_file: regions_file,
            regions_body: regions_body
          )
          native_from_source = native_dimensions_present?(map_source)
          display_style = build_display_style(attrs, native_from_source: native_from_source)

          regions_attr = regions_file ? %( data-jil-regions="#{escape_attr(regions_file)}") : ""
          viewer_attr = %( data-jil-viewer="#{viewer}") unless viewer.nil? || viewer.empty?
          inline_attr = %( data-jil-inline="#{inline}") unless inline.nil? || inline.empty?
          labels_attr = %( data-jil-labels="#{labels}") unless labels.nil? || labels.empty?
          title_attr = title ? %( data-jil-title="#{escape_attr(title)}") : ""

          regions_script = ""
          if regions_body && !regions_body.strip.empty? && regions_file.to_s.strip.empty?
            regions_script = %(\n<script type="application/yaml" class="jil-regions-data">#{regions_body.strip}\n</script>)
          end

          img_markup = render_img_attrs(
            src: resolved_src,
            alt: alt,
            native_width: native_from_source ? nil : attrs["width"],
            native_height: native_from_source ? nil : attrs["height"]
          )
          style_attr = display_style.empty? ? "" : %( style="#{escape_attr(display_style)}")

          <<~HTML.strip
            <img
              class="jil-map-image"
              #{img_markup}#{style_attr}
              loading="lazy"#{title_attr}#{regions_attr}#{viewer_attr}#{inline_attr}#{labels_attr}
            />#{regions_script}
          HTML
        end

        def render_interactive(map_data, viewer:, inline:, labels:, alt:, display_style: nil)
          map_json = JSON.generate(map_data)
          id = "jil-map-#{Digest::MD5.hexdigest(map_json)[0, 8]}"
          title = map_data["title"]
          caption_html = title ? %(<div class="jil-caption">#{escape_html(title)}</div>) : ""
          img_attrs = render_img_attrs(
            src: map_data["src"],
            alt: alt,
            native_width: nil,
            native_height: nil
          )
          host_class = "jil-map-host"
          host_class += " jil-height-constrained" if display_style.to_s.match?(/(?:^|;|\s)max-height\s*:/i)
          host_style_attr = display_style.to_s.strip.empty? ? "" : %( style="#{escape_attr(display_style)}")

          <<~HTML.strip
            <div class="jil-figure" data-jil-image-map="true"><div class="#{host_class}" id="#{id}" data-jil-map="#{escape_attr(map_json)}" data-jil-viewer="#{viewer}" data-jil-inline="#{inline}" data-jil-labels="#{labels}"#{host_style_attr.empty? ? "" : " #{host_style_attr}"}><img class="jil-map-image" #{img_attrs} loading="lazy" /></div>#{caption_html}</div>
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
            "style" => img_attrs["style"],
            "data-jil-max-width" => img_attrs["data-jil-max-width"],
            "data-jil-max-height" => img_attrs["data-jil-max-height"],
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
          title = attrs["title"]
          alt = attrs["alt"] || title
          viewer = parse_bool(attrs["viewer"], default: cfg.fetch("viewer_by_default", true))
          inline = parse_bool(attrs["inline"], default: cfg.fetch("inline_by_default", true))
          labels = parse_bool(attrs["labels"], default: cfg.fetch("labels_by_default", false))

          map_source = load_map_source(
            site: site,
            regions_file: attrs["file"],
            regions_body: regions_body
          )
          regions = map_source["regions"]
          validate_regions!(regions)

          width, height = resolve_native_dimensions(map_source, attrs)
          validate_dimensions!(width, height, src)

          native_from_source = native_dimensions_present?(map_source)
          display_style = build_display_style(attrs, native_from_source: native_from_source)

          map_data = {
            "src" => src,
            "width" => width,
            "height" => height,
            "title" => title,
            "regions" => normalize_regions(regions, site: site, page: page, liquid_context: liquid_context),
          }

          render_interactive(
            map_data,
            viewer: viewer,
            inline: inline,
            labels: labels,
            alt: alt,
            display_style: display_style
          )
        end

        def load_map_source(site:, regions_file:, regions_body:)
          data =
            if regions_file && !regions_file.to_s.strip.empty?
              path = regions_file.to_s
              full_path = Jekyll.sanitized_path(site.source, path)
              raise ArgumentError, "image_map file not found: #{path}" unless File.file?(full_path)

              YAML.safe_load(File.read(full_path), permitted_classes: [Date, Time, Symbol], aliases: true)
            elsif regions_body.to_s.strip.empty?
              {}
            else
              YAML.safe_load(regions_body, permitted_classes: [Date, Time, Symbol], aliases: true)
            end

          normalize_map_source(data)
        end

        def normalize_map_source(data)
          case data
          when Hash
            {
              "regions" => data["regions"] || data[:regions] || [],
              "width" => data["width"] || data[:width],
              "height" => data["height"] || data[:height],
            }
          when Array
            { "regions" => data, "width" => nil, "height" => nil }
          when nil
            { "regions" => [], "width" => nil, "height" => nil }
          else
            raise ArgumentError, "image_map regions must be a YAML list or a mapping with regions:"
          end
        end

        def native_dimensions_present?(map_source)
          map_source["width"].to_i.positive? && map_source["height"].to_i.positive?
        end

        def resolve_native_dimensions(map_source, attrs)
          width = map_source["width"].to_i
          height = map_source["height"].to_i

          if width <= 0 && attrs["width"].to_s.match?(/\A\d+\z/)
            width = attrs["width"].to_i
          end
          if height <= 0 && attrs["height"].to_s.match?(/\A\d+\z/)
            height = attrs["height"].to_i
          end

          [width, height]
        end

        def build_display_style(attrs, native_from_source:)
          rules = {}

          merge_style_rules!(rules, attrs["style"]) if attrs["style"]

          [
            ["data-jil-max-width", "max-width"],
            ["data-jil-max-height", "max-height"],
          ].each do |attr, prop|
            value = attrs[attr]
            rules[prop] = value if value && !value.to_s.strip.empty?
          end

          %w[width height].each do |dim|
            value = attrs[dim].to_s.strip
            next if value.empty?
            next if !native_from_source && value.match?(/\A\d+\z/)

            rules[dim] = format_css_size(value)
          end

          rules.map { |prop, value| "#{prop}: #{value}" }.join("; ")
        end

        def merge_style_rules!(rules, style)
          style.to_s.split(";").each do |declaration|
            prop, value = declaration.split(":", 2).map(&:strip)
            next if prop.nil? || prop.empty? || value.nil? || value.empty?

            rules[prop] = value
          end
        end

        def format_css_size(value)
          value = value.to_s.strip
          return value if value.match?(/\A[\d.]+%\z/) || value.match?(/\A[\d.]+px\z/i) || value == "auto"

          return "#{value}px" if value.match?(/\A\d+\z/)

          value
        end

        def render_img_attrs(src:, alt:, native_width:, native_height:)
          parts = [
            %(src="#{escape_attr(src)}"),
            %(alt="#{escape_attr(alt)}"),
          ]

          if native_width && native_height &&
             native_width.to_s.match?(/\A\d+\z/) && native_height.to_s.match?(/\A\d+\z/)
            parts << %(width="#{escape_attr(native_width)}")
            parts << %(height="#{escape_attr(native_height)}")
          end

          parts.join(" ")
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
          unless width.positive? && height.positive?
            raise ArgumentError, "image_map requires native width and height in the YAML file or numeric width/height attributes"
          end
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
