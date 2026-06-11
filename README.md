# jekyll-image-links

A Jekyll plugin for [Just the Docs](https://github.com/just-the-docs/just-the-docs) sites that adds clickable polygon regions on images.

Inspired by the Dynamic Map Viewer in [5etools](https://github.com/5etools/5etools-src), which uses custom JavaScript (not HTML `<map>` tags) to define polygon click areas on large map images.

## Features

- Define polygon click regions in Markdown using a Liquid tag
- Click a region to navigate to an internal or external link
- Hold **Shift** while clicking to open the link in a new tab
- Integrates with [jekyll-hover-popup](https://github.com/directsun/jekyll-hover-popup) when both plugins are enabled: region clicks open pinned hover-popup windows (no page darkening), and the map viewer opens inside a hover-popup window too
- Optional **Dynamic Map Viewer** button with zoom, pan, and region highlighting
- Optional region labels overlaid on the image
- Load region data inline or from a YAML file

## Install

Add to your site `Gemfile`:

```ruby
group :jekyll_plugins do
  gem "jekyll-image-links", path: "/path/to/image-links"
end
```

Then in `_config.yml`:

```yml
plugins:
  - jekyll-image-links
```

## Configuration

Optional `_config.yml` settings:

```yml
image_links:
  enabled: true
  assets_path: /assets/jekyll-image-links
  viewer_by_default: true
  inline_by_default: true
  labels_by_default: false
  use_hover_popup: auto # auto | true | false
```

When `jekyll-hover-popup` is also installed, image map region clicks open section previews in hover-popup windows instead of navigating the page. Set `use_hover_popup: false` to disable that integration.

## Usage

### Inline regions

```liquid
{% image_map src="/assets/maps/example.webp" width="1200" height="800" title="Example Map" %}
- href: /docs/room-a/
  title: Room A
  label: A
  points:
    - [120, 80]
    - [420, 80]
    - [420, 320]
    - [120, 320]
- href: /docs/room-b/
  title: Room B
  label: B
  points:
    - [480, 120]
    - [760, 120]
    - [760, 420]
    - [480, 420]
{% endimage_map %}
```

### External YAML file

`assets/maps/example-map.yml`:

```yml
width: 1200
height: 800
regions:
  - href: /docs/room-a/
    title: Room A
    points: [[120, 80], [420, 80], [420, 320], [120, 320]]
  - href: /docs/room-b/
    title: Room B
    points: [[480, 120], [760, 120], [760, 420], [480, 420]]
```

When `width` and `height` are in the YAML file, you can omit them from the tag and control display size separately:

```liquid
{% image_map src="/assets/maps/example.webp" file="assets/maps/example-map.yml" style="width:100%;max-width:900px;height:auto" %}
{% endimage_map %}
```

Legacy form still works — numeric `width`/`height` on the tag or `<img>` define the native coordinate system when the YAML file does not include them:

```liquid
{% image_map src="/assets/maps/example.webp" width="1200" height="800" file="assets/maps/example-map.yml" %}
{% endimage_map %}
```

### Tag options

| Attribute | Description |
|-----------|-------------|
| `src` | Image URL (required) |
| `width` | Native image width in pixels (required unless set in YAML) |
| `height` | Native image height in pixels (required unless set in YAML) |
| `title` | Caption and viewer title |
| `alt` | Image alt text (defaults to `title`) |
| `file` | Path to a YAML regions file relative to site source |
| `style` | CSS display sizing (for example `width:100%;max-width:900px;height:auto`) |
| `viewer="false"` | Disable the Dynamic Map Viewer button |
| `inline="false"` | Disable direct click regions on the inline image |
| `labels="true"` | Show region labels on the inline image |

### Manual HTML (portable markup)

You can also write image maps directly in Markdown using `{::nomarkdown}` blocks. Only an `<img>` tag is required — no `<figure>` wrapper. Put configuration on the image itself using `data-jil-*` attributes.

Store the **native** image dimensions in the YAML file. Region `points` use that coordinate system. Use CSS on the `<img>` for **display** size (percentages, max width/height, and so on). At build time those display styles are moved to the surrounding `.jil-map-host` wrapper so percentage sizes resolve against the page layout correctly.

If the plugin is disabled or not installed, the image still renders normally and browsers ignore the extra `data-jil-*` attributes.

```markdown
{::nomarkdown}
<img
  class="jil-map-image"
  src="/assets/images/a-familiar-tower/tower-1-combined-cropped.png"
  alt="Level 1"
  style="width: 100%; max-width: 900px; height: auto;"
  loading="lazy"
  data-jil-title="Level 1"
  data-jil-regions="assets/maps/a-familiar-tower-1.yml"
  data-jil-viewer="true"
  data-jil-inline="true"
  data-jil-labels="true"
/>
{:/nomarkdown}
```

`assets/maps/a-familiar-tower-1.yml`:

```yml
width: 1413
height: 1455
regions:
  - href: /docs/room-a/
    title: Room A
    points: [[120, 80], [420, 80], [420, 320], [120, 320]]
```

Display sizing alternatives on the `<img>`:

| Attribute | Example | Description |
|-----------|---------|-------------|
| `style` | `width:100%;max-width:900px;height:auto` | Full CSS control (recommended) |
| `width` / `height` | `width="100%"` or `width="800"` | Display size when YAML provides native dimensions |
| `data-jil-max-width` | `900px` or `80%` | Shorthand for `max-width` |
| `data-jil-max-height` | `600px` | Shorthand for `max-height` |

Portable images are detected by `class="jil-map-image"` together with region data (`data-jil-regions`, an adjacent `<script class="jil-regions-data">` block, or legacy `data-jil-map="true"`). Legacy `<figure data-jil-map="true">` markup is still supported.

| Attribute | Description |
|-----------|-------------|
| `class="jil-map-image"` | Marks the image for enhancement (required) |
| `data-jil-regions` | Path to a YAML regions file relative to site source |
| `data-jil-title` | Caption and viewer title |
| `data-jil-viewer` | Enable/disable the Dynamic Map Viewer button |
| `data-jil-inline` | Enable/disable direct click regions on the inline image |
| `data-jil-labels` | Show region labels on the inline image |

## Coordinate system

Region `points` use the image's native pixel coordinates, matching the 5etools `mapRegions` format. Define the native size once in the YAML file (`width` and `height`) or on the tag/image when not using YAML dimensions. For example, a 4937×3439 map uses coordinates in that range.

The plugin scales clicks from whatever size the image is displayed at back into that native coordinate system. Changing display size with CSS, percentages, or max width/height does not require editing region points.

## How this relates to 5etools

5etools stores regions as `mapRegions` on image entries in JSON data, then renders them with a custom `RenderMap` class (`js/render-map.js`) that:

- draws the image on a `<canvas>`
- overlays clickable polygons
- uses a ray-casting algorithm for hit detection
- opens linked adventure content in hover windows

This plugin uses the same polygon coordinate model and the same hit-detection approach, adapted for Jekyll pages with normal `href` links instead of 5etools' internal book area IDs.

## License

MIT
