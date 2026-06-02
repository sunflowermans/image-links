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
regions:
  - href: /docs/room-a/
    title: Room A
    points: [[120, 80], [420, 80], [420, 320], [120, 320]]
  - href: /docs/room-b/
    title: Room B
    points: [[480, 120], [760, 120], [760, 420], [480, 420]]
```

```liquid
{% image_map src="/assets/maps/example.webp" width="1200" height="800" file="assets/maps/example-map.yml" %}
{% endimage_map %}
```

### Tag options

| Attribute | Description |
|-----------|-------------|
| `src` | Image URL (required) |
| `width` | Native image width in pixels (required) |
| `height` | Native image height in pixels (required) |
| `title` | Caption and viewer title |
| `alt` | Image alt text (defaults to `title`) |
| `file` | Path to a YAML regions file relative to site source |
| `viewer="false"` | Disable the Dynamic Map Viewer button |
| `inline="false"` | Disable direct click regions on the inline image |
| `labels="true"` | Show region labels on the inline image |

## Coordinate system

Region `points` use the image's native pixel coordinates, matching the 5etools `mapRegions` format. For example, a 4937×3439 map uses coordinates in that range. The plugin scales clicks automatically when the image is displayed smaller on the page.

## How this relates to 5etools

5etools stores regions as `mapRegions` on image entries in JSON data, then renders them with a custom `RenderMap` class (`js/render-map.js`) that:

- draws the image on a `<canvas>`
- overlays clickable polygons
- uses a ray-casting algorithm for hit detection
- opens linked adventure content in hover windows

This plugin uses the same polygon coordinate model and the same hit-detection approach, adapted for Jekyll pages with normal `href` links instead of 5etools' internal book area IDs.

## License

MIT
