(function () {
  "use strict";

  const ROOT_SELECTOR = '[data-jil-root="true"]';
  const config = window.__JIL_CONFIG__ || {};
  // Hosts that already have listeners on this element instance.
  // data-jil-ready is not enough: a hover-popup preview clones the live map,
  // so the attribute is copied, but click listeners are not. A WeakSet tracks
  // the actual element. Clones are absent from it and get set up again, and
  // entries disappear when the preview window is discarded.
  const readyHosts = new WeakSet();

  function getHoverPopup() {
    const api = window.JekyllHoverPopup;
    if (!api || typeof api.openLink !== "function" || typeof api.openContent !== "function") {
      return null;
    }
    return api;
  }

  function useHoverPopup() {
    if (config.useHoverPopup === false) return false;
    return !!getHoverPopup();
  }

  function logError(message, error) {
    if (error) console.error(`[jil] ${message}`, error);
    else console.error(`[jil] ${message}`);
  }

  function reportMapProblems(img, mapData) {
    const src = mapData.src || img.getAttribute("src") || "image map";
    const width = Number(mapData.width);
    const height = Number(mapData.height);

    if (!width || !height) {
      logError(`${src}: map data is missing width or height`);
    }

    const regions = mapData.regions;
    if (!Array.isArray(regions) || regions.length === 0) {
      logError(`${src}: map data has no regions`);
    }

    const checkSize = () => {
      const naturalWidth = img.naturalWidth;
      const naturalHeight = img.naturalHeight;
      if (!naturalWidth || !naturalHeight) {
        logError(`${src}: image failed to load`);
        return;
      }
      if (!width || !height) return;
      if (naturalWidth === width && naturalHeight === height) return;
      logError(`${src}: image is ${naturalWidth}×${naturalHeight} but map data is ${width}×${height}`);
    };

    img.addEventListener("error", () => {
      logError(`${src}: image failed to load`);
    });

    if (img.complete) checkSize();
    else img.addEventListener("load", checkSize);

    (regions || []).forEach((region, index) => {
      const name = region.title || region.href || `region ${index + 1}`;
      const points = region.points;
      if (!region.href) logError(`${src}: "${name}" is missing href`);
      if (!Array.isArray(points) || points.length < 3) {
        logError(`${src}: "${name}" needs at least 3 points`);
        return;
      }
      if (!width || !height) return;

      const xs = points.map((point) => point[0]);
      const ys = points.map((point) => point[1]);
      const outside = xs.some((x) => x < 0 || x > width) || ys.some((y) => y < 0 || y > height);
      if (!outside) return;
      logError(
        `${src}: "${name}" is outside ${width}×${height} (x ${Math.min(...xs)}–${Math.max(...xs)}, y ${Math.min(...ys)}–${Math.max(...ys)})`
      );
    });
  }

  function init() {
    document.querySelectorAll("img.jil-map-image[data-jil-regions]").forEach((img) => {
      if (img.closest("[data-jil-map]")) return;
      logError(
        `${img.getAttribute("src") || "image"} was not enhanced (${img.getAttribute("data-jil-regions")})`
      );
    });

    // Maps already in the page. Maps that appear later, such as inside a
    // preview window, are handled by watchInsertedMaps.
    initWithin(document);
  }

  // Set up every map host inside root. root may be the document (first load)
  // or a node just inserted into a preview window.
  function initWithin(root) {
    if (!root || !root.querySelectorAll) return;

    const hosts = [];
    // The inserted node can be the host itself. querySelectorAll only looks
    // at descendants, so include root when it is a map host.
    if (root.nodeType === 1 && root.matches("[data-jil-map]")) hosts.push(root);
    root.querySelectorAll("[data-jil-map]").forEach((host) => hosts.push(host));

    hosts.forEach((host) => {
      try {
        initMapHost(host);
      } catch (error) {
        logError(`Failed to init ${host.id || "image map"}`, error);
      }
    });
  }

  // Page load only sees maps in the original document. Preview windows fetch
  // or clone section HTML later, so watch for those nodes and set them up then.
  function watchInsertedMaps() {
    if (!document.body || typeof MutationObserver === "undefined") return;

    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          // Text nodes cannot contain a map host.
          if (node.nodeType !== 1) return;
          initWithin(node);
        });
      });
    });

    // subtree covers maps nested inside the preview's section wrapper,
    // not only nodes appended directly to body.
    observer.observe(document.body, { childList: true, subtree: true });
  }

  // Drop UI that was copied from an already-initialized map. Labels and the
  // viewer button are created in JS, so a clone includes the elements but not
  // their listeners. Removing them lets init add a fresh, working copy.
  // Server-rendered markup has neither, so this is a no-op on first setup.
  function stripGeneratedUi(host) {
    host.querySelectorAll(".jil-label-layer").forEach((node) => node.remove());
    const figure = host.closest(".jil-figure");
    if (!figure) return;
    // The toolbar is a sibling of the host, inserted after the caption.
    figure.querySelectorAll(":scope > .jil-toolbar").forEach((node) => node.remove());
  }

  function initMapHost(host) {
    // Skip hosts already bound in this document. Clones are different elements
    // and fall through even when they carry data-jil-ready from the original.
    if (readyHosts.has(host)) return;
    readyHosts.add(host);
    host.dataset.jilReady = "true";
    stripGeneratedUi(host);

    let mapData;
    try {
      mapData = JSON.parse(host.dataset.jilMap);
    } catch (error) {
      logError(`Invalid map JSON on ${host.id || "image map"}`, error);
      return;
    }

    const inline = host.dataset.jilInline !== "false";
    const viewer = host.dataset.jilViewer !== "false";
    const labels = host.dataset.jilLabels === "true";
    const img = host.querySelector(".jil-map-image");

    if (!img) {
      logError(`${mapData.src || host.id || "image map"}: missing .jil-map-image`);
      return;
    }

    reportMapProblems(img, mapData);
    if (labels) renderLabels(host, mapData, img);
    if (inline) bindInlineClicks(host, mapData, img);
    if (viewer) addViewerButton(host, mapData);
  }

  // Keep overlay geometry in sync with the image, including inside a preview
  // that is opened, resized, and then closed.
  function bindLiveUpdates(host, img, update) {
    const onLoad = () => update();
    img.addEventListener("load", onLoad);

    // Window listeners and a ResizeObserver would keep a closed preview's
    // nodes alive. Drop them once the host has left the document.
    const detach = () => {
      window.removeEventListener("resize", onResize);
      if (observer) observer.disconnect();
    };

    const onResize = () => {
      if (!host.isConnected) {
        detach();
        return;
      }
      update();
    };

    let observer = null;
    if (typeof ResizeObserver !== "undefined") {
      observer = new ResizeObserver(() => {
        // Closing a preview disconnects the host and fires this observer.
        if (!host.isConnected) {
          detach();
          return;
        }
        update();
      });
      // Watch both: the host size follows the preview window, and the image
      // size follows its own load and CSS.
      observer.observe(host);
      observer.observe(img);
    }

    window.addEventListener("resize", onResize);
    // A cached image may already be complete, so the load event never fires.
    if (img.complete) update();
  }

  function bindOverlayGeometry(overlay, host, mapData, img) {
    bindLiveUpdates(host, img, () => {
      const geom = getMapGeometry(img, mapData);
      if (!geom || !geom.width || !geom.height) return;
      overlay.style.left = `${geom.offsetX}px`;
      overlay.style.top = `${geom.offsetY}px`;
      overlay.style.width = `${geom.width}px`;
      overlay.style.height = `${geom.height}px`;
    });
  }

  function renderLabels(host, mapData, img) {
    const overlay = document.createElement("div");
    overlay.className = "jil-label-layer";
    host.appendChild(overlay);
    bindOverlayGeometry(overlay, host, mapData, img);

    bindLiveUpdates(host, img, () => {
      overlay.innerHTML = "";
      const geom = getMapGeometry(img, mapData);
      if (!geom || !geom.width || !geom.height) return;

      mapData.regions.forEach((region) => {
        const center = polygonCenter(region.points);
        if (!center) return;

        const left = (center[0] / mapData.width) * 100;
        const top = (center[1] / mapData.height) * 100;
        const label = region.label || region.title || "";
        if (!label) return;

        const link = document.createElement("a");
        link.className = "jil-label";
        link.href = region.href;
        link.textContent = label;
        link.style.left = `${left}%`;
        link.style.top = `${top}%`;
        link.title = region.title || label;
        overlay.appendChild(link);
      });
    });
  }

  function bindInlineClicks(host, mapData, img) {
    host.classList.add("jil-inline");
    img.addEventListener("click", (event) => {
      const point = imagePointFromEvent(img, mapData, event);
      const region = firstIntersectedRegion(mapData.regions, point);
      if (!region) return;

      event.preventDefault();
      openRegion(region, event);
    });

    img.addEventListener("mousemove", (event) => {
      const point = imagePointFromEvent(img, mapData, event);
      const region = firstIntersectedRegion(mapData.regions, point);
      img.style.cursor = region ? "pointer" : "";
    });
  }

  function addViewerButton(host, mapData) {
    const figure = host.closest(".jil-figure");
    if (!figure) return;

    const caption = figure.querySelector(".jil-caption");
    const toolbar = document.createElement("div");
    toolbar.className = "jil-toolbar";

    const button = document.createElement("button");
    button.type = "button";
    button.className = "jil-viewer-button btn btn-outline";
    button.textContent = mapData.title ? `Open ${mapData.title}` : "Open map viewer";
    button.addEventListener("click", (event) => openViewer(mapData, event));
    toolbar.appendChild(button);

    if (caption) {
      caption.insertAdjacentElement("afterend", toolbar);
    } else {
      host.insertAdjacentElement("afterend", toolbar);
    }
  }

  function openViewer(mapData, event) {
    const panel = buildViewerPanel(mapData);
    const jhp = useHoverPopup() ? getHoverPopup() : null;

    if (jhp) {
      jhp.openContent({
        title: mapData.title || "Map viewer",
        pageUrl: mapData.src,
        content: panel.root,
        clientX: event.clientX,
        clientY: event.clientY,
        isPermanent: true,
        maxWidth: "min(96vw, 1200px)",
      });
      return;
    }

    const backdrop = document.createElement("div");
    backdrop.className = "jil-viewer-backdrop";
    backdrop.setAttribute("role", "dialog");
    backdrop.setAttribute("aria-modal", "true");
    backdrop.setAttribute("aria-label", mapData.title || "Map viewer");
    backdrop.appendChild(panel.root);
    document.body.appendChild(backdrop);
    panel.focusClose();
    backdrop.addEventListener("click", (evt) => {
      if (evt.target === backdrop) backdrop.remove();
    });
    backdrop.addEventListener("keydown", (evt) => {
      if (evt.key === "Escape") backdrop.remove();
    });
  }

  function buildViewerPanel(mapData) {
    const root = document.createElement("div");
    root.className = "jil-viewer-panel jil-viewer-in-popup";

    const header = document.createElement("div");
    header.className = "jil-viewer-header";

    const title = document.createElement("div");
    title.className = "jil-viewer-title";
    title.textContent = mapData.title || "Map viewer";

    const closeBtn = document.createElement("button");
    closeBtn.type = "button";
    closeBtn.className = "jil-viewer-close btn btn-outline";
    closeBtn.textContent = "Close";
    closeBtn.hidden = true;

    header.append(title, closeBtn);

    const controls = document.createElement("div");
    controls.className = "jil-viewer-controls";

    const zoomOut = makeButton("Zoom out");
    const zoomIn = makeButton("Zoom in");
    const zoomReset = makeButton("Reset zoom");
    const zoomFit = makeButton("Zoom to fit");
    controls.append(zoomOut, zoomIn, zoomReset, zoomFit);

    const scroll = document.createElement("div");
    scroll.className = "jil-viewer-scroll";

    const canvas = document.createElement("canvas");
    canvas.className = "jil-viewer-canvas";
    scroll.appendChild(canvas);

    root.append(header, controls, scroll);

    const state = {
      zoom: 1,
      image: null,
    };

    const paint = () => {
      if (!state.image) return;
      const width = Math.round(mapData.width * state.zoom);
      const height = Math.round(mapData.height * state.zoom);
      canvas.width = width;
      canvas.height = height;

      const ctx = canvas.getContext("2d");
      ctx.clearRect(0, 0, width, height);
      ctx.drawImage(state.image, 0, 0, width, height);

      mapData.regions.forEach((region) => {
        ctx.beginPath();
        region.points.forEach((point, index) => {
          const x = point[0] * state.zoom;
          const y = point[1] * state.zoom;
          if (index === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        });
        ctx.closePath();
        ctx.fillStyle = "rgba(51, 122, 183, 0.35)";
        ctx.strokeStyle = "rgba(51, 122, 183, 0.95)";
        ctx.lineWidth = 2;
        ctx.fill();
        ctx.stroke();
      });
    };

    const setZoom = (value) => {
      state.zoom = clamp(value, 0.1, 8);
      paint();
    };

    const fitZoom = () => {
      const maxWidth = scroll.clientWidth || mapData.width;
      const maxHeight = scroll.clientHeight || mapData.height;
      setZoom(Math.min(maxWidth / mapData.width, maxHeight / mapData.height, 1));
      scroll.scrollTop = 0;
      scroll.scrollLeft = 0;
    };

    zoomOut.addEventListener("click", () => setZoom(state.zoom / 1.25));
    zoomIn.addEventListener("click", () => setZoom(state.zoom * 1.25));
    zoomReset.addEventListener("click", () => {
      setZoom(1);
      scroll.scrollTop = 0;
      scroll.scrollLeft = 0;
    });
    zoomFit.addEventListener("click", fitZoom);

    let dragStart = null;
    let didPan = false;

    const cursorForPoint = (event) => {
      const point = canvasPointFromEvent(canvas, state.zoom, event);
      const region = firstIntersectedRegion(mapData.regions, point);
      return region ? "pointer" : "grab";
    };

    canvas.addEventListener("click", (event) => {
      if (didPan) {
        didPan = false;
        event.preventDefault();
        return;
      }
      const point = canvasPointFromEvent(canvas, state.zoom, event);
      const region = firstIntersectedRegion(mapData.regions, point);
      if (!region) return;
      event.preventDefault();
      openRegion(region, event);
    });

    canvas.addEventListener("mousemove", (event) => {
      if (dragStart) return;
      canvas.style.cursor = cursorForPoint(event);
    });

    canvas.addEventListener("mousedown", (event) => {
      // Left-drag empty areas to pan; right-drag pans from anywhere.
      if (event.button === 0) {
        const point = canvasPointFromEvent(canvas, state.zoom, event);
        if (firstIntersectedRegion(mapData.regions, point)) return;
      } else if (event.button !== 2) {
        return;
      }

      event.preventDefault();
      didPan = false;
      dragStart = {
        x: event.clientX,
        y: event.clientY,
        scrollLeft: scroll.scrollLeft,
        scrollTop: scroll.scrollTop,
      };
      canvas.style.cursor = "grabbing";
    });

    window.addEventListener("mouseup", (event) => {
      if (!dragStart) return;
      dragStart = null;
      canvas.style.cursor = cursorForPoint(event);
      // Clear after the trailing click so a pan doesn't open a region.
      if (didPan) {
        setTimeout(() => {
          didPan = false;
        }, 0);
      }
    });

    window.addEventListener("mousemove", (event) => {
      if (!dragStart) return;
      const dx = dragStart.x - event.clientX;
      const dy = dragStart.y - event.clientY;
      if (Math.abs(dx) > 2 || Math.abs(dy) > 2) didPan = true;
      scroll.scrollLeft = dragStart.scrollLeft + dx;
      scroll.scrollTop = dragStart.scrollTop + dy;
    });

    canvas.addEventListener("contextmenu", (event) => event.preventDefault());

    scroll.addEventListener("wheel", (event) => {
      if (!event.ctrlKey && !event.metaKey) return;
      event.preventDefault();
      setZoom(state.zoom * (event.deltaY < 0 ? 1.1 : 0.9));
    }, { passive: false });

    const image = new Image();
    image.onload = () => {
      state.image = image;
      fitZoom();
    };
    image.onerror = () => {
      logError(`${mapData.src || "viewer image"}: viewer image failed to load`);
    };
    image.src = mapData.src;

    return {
      root,
      focusClose: () => closeBtn.focus(),
    };
  }

  function makeButton(label) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-outline";
    button.textContent = label;
    return button;
  }

  async function openRegion(region, event) {
    if (event.shiftKey) {
      window.open(region.href, "_blank", "noopener,noreferrer");
      return;
    }

    const jhp = useHoverPopup() ? getHoverPopup() : null;
    if (jhp) {
      event.preventDefault();
      try {
        await jhp.openLink({
          href: region.href,
          title: region.title || region.label || region.href,
          clientX: event.clientX,
          clientY: event.clientY,
          isPermanent: true,
        });
      } catch (error) {
        logError(`Failed to open ${region.href}`, error);
      }
      return;
    }

    if (!region.href) {
      logError("Region is missing href");
      return;
    }

    window.location.href = region.href;
  }

  function imagePointFromEvent(img, mapData, event) {
    const rect = img.getBoundingClientRect();
    const geom = getMapGeometry(img, mapData);
    if (!geom || !geom.width || !geom.height) {
      return [0, 0];
    }

    const relX = (event.clientX - rect.left - geom.offsetX) / geom.width;
    const relY = (event.clientY - rect.top - geom.offsetY) / geom.height;
    return [
      Math.round(relX * mapData.width),
      Math.round(relY * mapData.height),
    ];
  }

  function getMapGeometry(img, mapData) {
    const rect = img.getBoundingClientRect();
    const mapW = mapData.width;
    const mapH = mapData.height;
    if (!rect.width || !rect.height || !mapW || !mapH) {
      return null;
    }

    const objectFit = window.getComputedStyle(img).objectFit || "fill";
    const mapAspect = mapW / mapH;

    if (objectFit === "fill") {
      return {
        offsetX: 0,
        offsetY: 0,
        width: rect.width,
        height: rect.height,
      };
    }

    const boxAspect = rect.width / rect.height;
    let width;
    let height;

    if (objectFit === "cover") {
      if (boxAspect > mapAspect) {
        height = rect.height;
        width = height * mapAspect;
      } else {
        width = rect.width;
        height = width / mapAspect;
      }
    } else {
      if (boxAspect > mapAspect) {
        height = rect.height;
        width = height * mapAspect;
      } else {
        width = rect.width;
        height = width / mapAspect;
      }
    }

    return {
      offsetX: (rect.width - width) / 2,
      offsetY: (rect.height - height) / 2,
      width,
      height,
    };
  }

  function canvasPointFromEvent(canvas, zoom, event) {
    const rect = canvas.getBoundingClientRect();
    const x = (event.clientX - rect.left) / zoom;
    const y = (event.clientY - rect.top) / zoom;
    return [Math.round(x), Math.round(y)];
  }

  function firstIntersectedRegion(regions, point) {
    return regions.find((region) => pointInPolygon(region.points, point)) || null;
  }

  function pointInPolygon(points, point) {
    const [x, y] = point;
    let count = 0;
    for (let i = 0; i < points.length; i += 1) {
      const a = { x: points[i][0], y: points[i][1] };
      const b = { x: points[(i + 1) % points.length][0], y: points[(i + 1) % points.length][1] };
      if (isWest(a, b, x, y)) count += 1;
    }
    return count % 2 === 1;
  }

  function isWest(a, b, x, y) {
    if (a.y <= b.y) {
      if (y <= a.y || y > b.y || (x >= a.x && x >= b.x)) return false;
      if (x < a.x && x < b.x) return true;
      return (y - a.y) / (x - a.x) > (b.y - a.y) / (b.x - a.x);
    }
    return isWest(b, a, x, y);
  }

  function polygonCenter(points) {
    let x = 0;
    let y = 0;
    points.forEach((point) => {
      x += point[0];
      y += point[1];
    });
    return [x / points.length, y / points.length];
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function start() {
    if (!document.querySelector(ROOT_SELECTOR)) {
      logError("image_links.js loaded without data-jil-root");
      return;
    }

    const run = () => {
      // Observe before the first pass so a preview inserted during init is
      // not missed. Init itself does not add map hosts, so this does not
      // set the same map up twice.
      watchInsertedMaps();
      init();
    };

    if (document.querySelector('[data-hover-popup-root="true"]') && !getHoverPopup()) {
      window.setTimeout(run, 0);
      return;
    }

    run();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
