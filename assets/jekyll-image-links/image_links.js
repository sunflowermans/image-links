(function () {
  "use strict";

  const ROOT_SELECTOR = '[data-jil-root="true"]';

  function init() {
    document.querySelectorAll("[data-jil-map]").forEach(initMapHost);
  }

  function initMapHost(host) {
    if (host.dataset.jilReady === "true") return;
    host.dataset.jilReady = "true";

    const mapData = JSON.parse(host.dataset.jilMap);
    const inline = host.dataset.jilInline !== "false";
    const viewer = host.dataset.jilViewer !== "false";
    const labels = host.dataset.jilLabels === "true";
    const img = host.querySelector(".jil-map-image");

    if (!img) return;

    if (labels) renderLabels(host, mapData, img);
    if (inline) bindInlineClicks(host, mapData, img);
    if (viewer) addViewerButton(host, mapData);
  }

  function renderLabels(host, mapData, img) {
    const overlay = document.createElement("div");
    overlay.className = "jil-label-layer";
    host.appendChild(overlay);

    const update = () => {
      overlay.innerHTML = "";
      const rect = img.getBoundingClientRect();
      if (!rect.width || !rect.height) return;

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
    };

    if (img.complete) update();
    img.addEventListener("load", update);
    window.addEventListener("resize", update);
  }

  function bindInlineClicks(host, mapData, img) {
    host.classList.add("jil-inline");
    img.addEventListener("click", (event) => {
      const point = imagePointFromEvent(img, mapData, event);
      const region = firstIntersectedRegion(mapData.regions, point);
      if (!region) return;

      event.preventDefault();
      navigateToRegion(region, event);
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
    const modal = buildViewerModal(mapData);
    document.body.appendChild(modal.backdrop);
    modal.focus();
    modal.backdrop.addEventListener("click", (evt) => {
      if (evt.target === modal.backdrop) modal.close();
    });
  }

  function buildViewerModal(mapData) {
    const backdrop = document.createElement("div");
    backdrop.className = "jil-viewer-backdrop";
    backdrop.setAttribute("role", "dialog");
    backdrop.setAttribute("aria-modal", "true");
    backdrop.setAttribute("aria-label", mapData.title || "Map viewer");

    const panel = document.createElement("div");
    panel.className = "jil-viewer-panel";

    const header = document.createElement("div");
    header.className = "jil-viewer-header";

    const title = document.createElement("div");
    title.className = "jil-viewer-title";
    title.textContent = mapData.title || "Map viewer";

    const closeBtn = document.createElement("button");
    closeBtn.type = "button";
    closeBtn.className = "jil-viewer-close btn btn-outline";
    closeBtn.textContent = "Close";

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

    panel.append(header, controls, scroll);
    backdrop.appendChild(panel);

    const state = {
      zoom: 1,
      image: null,
      mapData,
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

    canvas.addEventListener("click", (event) => {
      const point = canvasPointFromEvent(canvas, state.zoom, event);
      const region = firstIntersectedRegion(mapData.regions, point);
      if (!region) return;
      navigateToRegion(region, event);
    });

    canvas.addEventListener("mousemove", (event) => {
      const point = canvasPointFromEvent(canvas, state.zoom, event);
      const region = firstIntersectedRegion(mapData.regions, point);
      canvas.style.cursor = region ? "pointer" : "grab";
    });

    let dragStart = null;
    canvas.addEventListener("mousedown", (event) => {
      if (event.button !== 2) return;
      event.preventDefault();
      dragStart = {
        x: event.clientX,
        y: event.clientY,
        scrollLeft: scroll.scrollLeft,
        scrollTop: scroll.scrollTop,
      };
      canvas.style.cursor = "grabbing";
    });

    window.addEventListener("mouseup", () => {
      dragStart = null;
      canvas.style.cursor = "grab";
    });

    window.addEventListener("mousemove", (event) => {
      if (!dragStart) return;
      scroll.scrollLeft = dragStart.scrollLeft + (dragStart.x - event.clientX);
      scroll.scrollTop = dragStart.scrollTop + (dragStart.y - event.clientY);
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
    image.src = mapData.src;

    const close = () => backdrop.remove();
    closeBtn.addEventListener("click", close);
    backdrop.addEventListener("keydown", (event) => {
      if (event.key === "Escape") close();
    });

    return {
      backdrop,
      focus: () => closeBtn.focus(),
      close,
    };
  }

  function makeButton(label) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "btn btn-outline";
    button.textContent = label;
    return button;
  }

  function navigateToRegion(region, event) {
    if (event.shiftKey) {
      window.open(region.href, "_blank", "noopener,noreferrer");
      return;
    }
    window.location.href = region.href;
  }

  function imagePointFromEvent(img, mapData, event) {
    const rect = img.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * mapData.width;
    const y = ((event.clientY - rect.top) / rect.height) * mapData.height;
    return [Math.round(x), Math.round(y)];
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

  if (document.querySelector(ROOT_SELECTOR)) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", init);
    } else {
      init();
    }
  }
})();
