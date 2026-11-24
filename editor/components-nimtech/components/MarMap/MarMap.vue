<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import type { Map as MapView, Marker, StyleSpecification } from "maplibre-gl";
import MarIcon from "../MarIcon";
import { getCoordinates, type MapCoordinates } from "./geocode";

const {
  lat = null,
  lng = null,
  zoom = 13,
  label = "",
  address = "",
  interactive = false,
  height = "16em",
  variant = "inline",
} = defineProps<{
  /** Latitude of the map center and marker. */
  lat?: number | null;
  /** Longitude of the map center and marker. */
  lng?: number | null;
  /** Zoom level of the map view. */
  zoom?: number;
  /** Caption shown in a themed chip above the marker pin. */
  label?: string;
  /** Address resolved to coordinates through Nominatim when lat and lng are absent. */
  address?: string;
  /** Enables drag, scroll zoom, double click zoom, touch, box zoom, and keyboard handlers. */
  interactive?: boolean;
  /** CSS height of the map frame. */
  height?: string;
  /** Bare map in the flow, or a card carrying the label, the address, and a link out to Google Maps. */
  variant?: "inline" | "card";
}>();

const frame = ref<HTMLElement>();
const probe = ref<HTMLElement>();
const pin = ref<HTMLElement>();
const center = ref<MapCoordinates | null>(null);

let view: MapView | null = null;
let marker: Marker | null = null;
let lib: typeof import("maplibre-gl") | null = null;

const resolveCenter = async (): Promise<void> => {
  if (lat != null && lng != null && !Number.isNaN(lat) && !Number.isNaN(lng)) {
    center.value = { lat, lng };
    return;
  }
  if (address) {
    center.value = (await getCoordinates(address)) ?? center.value;
    return;
  }
  center.value = { lat: 59.9139, lng: 10.7522 };
};

const themeColor = (name: string): string =>
  getComputedStyle(frame.value!).getPropertyValue(name).trim();

const mixColors = (top: string, bottom: string, share: number): string => {
  probe.value!.style.color = `color-mix(in srgb, ${top} ${share}%, ${bottom})`;
  const value = getComputedStyle(probe.value!).color;
  const srgb = /^color\(srgb ([\d.]+) ([\d.]+) ([\d.]+)(?: \/ ([\d.]+))?\)$/.exec(value);
  if (!srgb) return value;
  const to255 = (channel: string): number => Math.round(Number(channel) * 255);
  return `rgba(${to255(srgb[1])}, ${to255(srgb[2])}, ${to255(srgb[3])}, ${srgb[4] ?? "1"})`;
};

const buildStyle = (): StyleSpecification => {
  const base = themeColor("--mar-surface-100");
  const text = themeColor("--mar-text-color");
  const muted = themeColor("--mar-text-muted-color");
  const primary = themeColor("--mar-primary-color");
  const water = mixColors(primary, base, 20);
  return {
    version: 8,
    glyphs: "https://tiles.openfreemap.org/fonts/{fontstack}/{range}",
    sources: {
      openmaptiles: {
        type: "vector",
        url: "https://tiles.openfreemap.org/planet",
      },
    },
    layers: [
      {
        id: "ground",
        type: "background",
        paint: { "background-color": base },
      },
      {
        id: "green",
        type: "fill",
        source: "openmaptiles",
        "source-layer": "landcover",
        paint: { "fill-color": mixColors(primary, base, 7), "fill-opacity": 0.6 },
      },
      {
        id: "water",
        type: "fill",
        source: "openmaptiles",
        "source-layer": "water",
        paint: { "fill-color": water },
      },
      {
        id: "waterway",
        type: "line",
        source: "openmaptiles",
        "source-layer": "waterway",
        paint: { "line-color": water, "line-width": 1 },
      },
      {
        id: "building",
        type: "fill",
        source: "openmaptiles",
        "source-layer": "building",
        minzoom: 13,
        paint: { "fill-color": mixColors(text, base, 6) },
      },
      {
        id: "road-minor",
        type: "line",
        source: "openmaptiles",
        "source-layer": "transportation",
        minzoom: 10,
        filter: ["match", ["get", "class"], ["motorway", "trunk", "primary", "secondary"], false, true],
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": mixColors(text, base, 9),
          "line-width": ["interpolate", ["linear"], ["zoom"], 10, 0.5, 14, 1.5, 18, 6],
        },
      },
      {
        id: "road-major",
        type: "line",
        source: "openmaptiles",
        "source-layer": "transportation",
        filter: ["match", ["get", "class"], ["motorway", "trunk", "primary", "secondary"], true, false],
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": mixColors(text, base, 16),
          "line-width": ["interpolate", ["linear"], ["zoom"], 6, 0.6, 12, 2, 18, 10],
        },
      },
      {
        id: "border",
        type: "line",
        source: "openmaptiles",
        "source-layer": "boundary",
        filter: ["all", ["<=", ["get", "admin_level"], 4], ["==", ["get", "maritime"], 0]],
        paint: {
          "line-color": mixColors(text, base, 22),
          "line-width": 1,
          "line-dasharray": [3, 2],
        },
      },
      {
        id: "place",
        type: "symbol",
        source: "openmaptiles",
        "source-layer": "place",
        filter: ["match", ["get", "class"], ["city", "town", "village", "suburb"], true, false],
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Noto Sans Regular"],
          "text-size": ["interpolate", ["linear"], ["zoom"], 4, 10, 12, 14],
        },
        paint: {
          "text-color": muted,
          "text-halo-color": base,
          "text-halo-width": 1.2,
        },
      },
    ],
  } as StyleSpecification;
};

const applyInteractive = (): void => {
  if (!view) return;
  const handlers = [
    view.scrollZoom,
    view.boxZoom,
    view.dragPan,
    view.doubleClickZoom,
    view.touchZoomRotate,
    view.keyboard,
  ];
  for (const handler of handlers) {
    if (interactive) handler.enable();
    else handler.disable();
  }
};

const createView = async (): Promise<void> => {
  if (!frame.value || !center.value) return;
  if (!lib) {
    await import("maplibre-gl/dist/maplibre-gl.css");
    const [module, worker] = await Promise.all([
      import("maplibre-gl"),
      import("maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url"),
    ]);
    module.setWorkerUrl(worker.default);
    lib = module;
  }
  view?.remove();
  view = new lib.Map({
    container: frame.value,
    style: buildStyle(),
    center: [center.value.lng, center.value.lat],
    zoom,
    attributionControl: false,
    dragRotate: false,
    pitchWithRotate: false,
    touchPitch: false,
  });
  applyInteractive();
  if (pin.value) {
    marker = new lib.Marker({ element: pin.value, anchor: "bottom" })
      .setLngLat([center.value.lng, center.value.lat])
      .addTo(view);
  }
};

const mapsHref = computed(() => {
  const query = center.value
    ? `${center.value.lat},${center.value.lng}`
    : address;
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
});

const themeObserver = new MutationObserver(() => {
  if (view) view.setStyle(buildStyle());
});

onMounted(async () => {
  themeObserver.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["class", "data-theme"],
  });
  themeObserver.observe(document.body, {
    attributes: true,
    attributeFilter: ["class", "data-theme"],
  });
  await resolveCenter();
  await createView();
});

onBeforeUnmount(() => {
  themeObserver.disconnect();
  marker?.remove();
  view?.remove();
  view = null;
  marker = null;
});

watch([() => lat, () => lng, () => address], async () => {
  await resolveCenter();
  if (!center.value) return;
  if (!view) {
    await createView();
    return;
  }
  view.jumpTo({ center: [center.value.lng, center.value.lat], zoom });
  marker?.setLngLat([center.value.lng, center.value.lat]);
});

watch(() => zoom, () => view?.zoomTo(zoom));
watch(() => interactive, applyInteractive);
</script>

<template>
  <div class="mar-map" :class="`mar-map-${variant}`">
    <div
      ref="frame"
      class="mar-map-frame"
      :class="{ 'mar-map-static': !interactive }"
      :style="{ height }"
    ></div>
    <span ref="probe" class="mar-map-probe"></span>
    <div ref="pin" class="mar-map-marker">
      <span v-if="label && variant !== 'card'" class="mar-map-marker-label">{{ label }}</span>
      <MarIcon icon="map-pin" class="mar-map-marker-pin" />
    </div>
    <a
      v-if="variant === 'card' && (label || address)"
      class="mar-map-card"
      :href="mapsHref"
      target="_blank"
      rel="noreferrer"
    >
      <span v-if="label" class="mar-map-card-title">{{ label }}</span>
      <span v-if="address" class="mar-map-card-address">{{ address }}</span>
    </a>
  </div>
</template>

<style scoped>
.mar-map {
  width: 100%;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 10px;
  overflow: hidden;
  background: var(--mar-surface-100);
}

.mar-map-frame {
  width: 100%;
  font-size: inherit;
  background: var(--mar-surface-100);
}

.mar-map-frame :deep(.maplibregl-canvas) {
  outline: none;
}

.mar-map-static :deep(.maplibregl-canvas) {
  cursor: default;
}

.mar-map-probe {
  position: absolute;
  visibility: hidden;
  pointer-events: none;
}

.mar-map-marker {
  display: none;
}

.mar-map-marker.maplibregl-marker {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.25em;
}

.mar-map-marker-pin {
  color: var(--mar-primary-color);
  font-size: 1em;
  filter: drop-shadow(0 1px 2px var(--mar-overlay-color));
}

.mar-map-card {
  display: flex;
  flex-direction: column;
  gap: 0.25em;
  padding: 0.875em 1em;
  border-top: 1px solid var(--mar-content-border-color);
  background: var(--mar-surface-0);
  text-decoration: none;
}

.mar-map-card:hover {
  background: var(--mar-surface-100);
}

.mar-map-card-title {
  color: var(--mar-text-color);
  font-size: 0.9375em;
  font-weight: 600;
}

.mar-map-card-address {
  color: var(--mar-text-muted-color);
  font-size: 0.8125em;
  line-height: 1.35;
}

.mar-map-marker-label {
  max-width: 18.6667em;
  padding: 0.25em 0.6667em;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 999px;
  background: var(--mar-surface-0);
  color: var(--mar-text-color);
  font-size: 0.75em;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  box-shadow: 0 1px 2px var(--mar-overlay-color);
}
</style>
