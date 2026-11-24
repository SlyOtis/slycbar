<script setup lang="ts">
import { computed, ref, watch } from "vue";
import MarIcon from "../MarIcon";
import { formatDate, isHour12Format, useDateFormat } from "@/composables/useDateFormat";
import { getCoordinates, type MapCoordinates } from "../MarMap/geocode";
import {
  getForecast,
  weatherIcon,
  weatherLabel,
  type WeatherForecast,
  type WeatherPoint,
} from "./forecast";

const {
  lat = null,
  lng = null,
  address = "",
  label = "",
  variant = "card",
  forecast = "hours",
  count = 6,
} = defineProps<{
  /** Latitude of the forecast location. */
  lat?: number | null;
  /** Longitude of the forecast location. */
  lng?: number | null;
  /** Address resolved to coordinates through Nominatim when lat and lng are absent. */
  address?: string;
  /** Place name shown beside the reading, falling back to the address. */
  label?: string;
  /** Full card with the detail row and the strip, or a single inline row. */
  variant?: "card" | "inline";
  /** Strip below the reading: the next hours, the coming days, or nothing. */
  forecast?: "none" | "hours" | "days";
  /** Number of cells in the forecast strip. */
  count?: number;
}>();

const data = ref<WeatherForecast | null>(null);
const failed = ref(false);

let request = 0;

const resolveCenter = async (): Promise<MapCoordinates> => {
  if (lat != null && lng != null && !Number.isNaN(lat) && !Number.isNaN(lng)) {
    return { lat, lng };
  }
  if (address) return (await getCoordinates(address)) ?? { lat: 59.9139, lng: 10.7522 };
  return { lat: 59.9139, lng: 10.7522 };
};

const load = async (): Promise<void> => {
  request += 1;
  const token = request;
  failed.value = false;
  data.value = null;
  try {
    const hit = await resolveCenter();
    const next = await getForecast(hit.lat, hit.lng);
    if (token !== request) return;
    if (!next) {
      failed.value = true;
      return;
    }
    data.value = next;
  } catch {
    if (token === request) failed.value = true;
  }
};

watch(
  () => [lat, lng, address],
  () => {
    void load();
  },
  { immediate: true },
);

const current = computed(() => data.value?.current ?? null);
const today = computed(() => data.value?.days[0] ?? null);

const place = computed(() => label || address || "Oslo");

const cells = computed<WeatherPoint[]>(() => {
  if (!data.value || forecast === "none") return [];
  const source = forecast === "days" ? data.value.days.slice(1) : data.value.hours;
  return source.slice(0, Math.max(0, count));
});

const degrees = (value: number): string => `${Math.round(value)}°`;

const dateFormat = useDateFormat();

const cellTime = (point: WeatherPoint): string => {
  const hour = isHour12Format(dateFormat.value.time) ? "h a" : "HH";
  return formatDate(point.time, forecast === "days" ? "EEE" : hour, dateFormat.value);
};

const updated = computed(() =>
  current.value ? formatDate(current.value.time, dateFormat.value.time, dateFormat.value) : "",
);
</script>

<template>
  <div :class="['mar-weather', `mar-weather-${variant}`]">
    <p v-if="failed" class="mar-weather-empty">Forecast unavailable</p>
    <p v-else-if="!current" class="mar-weather-empty">Loading forecast</p>
    <template v-else>
      <div class="mar-weather-now">
        <MarIcon :icon="weatherIcon(current.symbol)" class="mar-weather-now-icon" />
        <span class="mar-weather-temp">{{ degrees(current.temperature) }}</span>
        <div class="mar-weather-now-text">
          <span class="mar-weather-place">{{ place }}</span>
          <span class="mar-weather-condition">
            {{ weatherLabel(current.symbol) }}
            <template v-if="variant === 'card'"> at {{ updated }}</template>
          </span>
        </div>
      </div>
      <div v-if="variant === 'card' && today" class="mar-weather-details">
        <span class="mar-weather-detail">
          <MarIcon icon="thermometer" />
          {{ degrees(today.high) }} / {{ degrees(today.low) }}
        </span>
        <span class="mar-weather-detail">
          <MarIcon icon="wind" />
          {{ current.windSpeed.toFixed(1) }} m/s
        </span>
        <span class="mar-weather-detail">
          <MarIcon icon="cloud-rain" />
          {{ current.precipitation.toFixed(1) }} mm
        </span>
        <span class="mar-weather-detail">
          <MarIcon icon="droplet" />
          {{ Math.round(current.humidity) }} %
        </span>
      </div>
      <div v-if="variant === 'card' && cells.length" class="mar-weather-strip">
        <div v-for="point in cells" :key="point.time" class="mar-weather-cell">
          <span class="mar-weather-cell-time">{{ cellTime(point) }}</span>
          <MarIcon :icon="weatherIcon(point.symbol)" class="mar-weather-cell-icon" />
          <span class="mar-weather-cell-temp">{{ degrees(point.high) }}</span>
          <span v-if="forecast === 'days'" class="mar-weather-cell-low">
            {{ degrees(point.low) }}
          </span>
        </div>
      </div>
      <a
        v-if="variant === 'card'"
        class="mar-weather-credit"
        href="https://www.met.no/en"
        target="_blank"
        rel="noreferrer"
      >
        Weather data from MET Norway
      </a>
    </template>
  </div>
</template>

<style scoped>
.mar-weather {
  display: flex;
  flex-direction: column;
  color: var(--mar-text-color);
}

.mar-weather-card {
  gap: 1em;
  padding: 1.25em;
  border: 1px solid var(--mar-content-border-color);
  border-radius: 10px;
  background: var(--mar-surface-0);
}

.mar-weather-empty {
  margin: 0;
  color: var(--mar-text-muted-color);
  font-size: 0.875em;
}

.mar-weather-now {
  display: flex;
  align-items: center;
  gap: 0.875em;
}

.mar-weather-now-icon {
  flex: none;
  width: 2.75em;
  height: 2.75em;
  color: var(--mar-primary-color);
}

.mar-weather-inline .mar-weather-now-icon {
  width: 1.5em;
  height: 1.5em;
}

.mar-weather-temp {
  font-size: 2.5em;
  font-weight: 600;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}

.mar-weather-inline .mar-weather-temp {
  font-size: 1.125em;
}

.mar-weather-now-text {
  display: flex;
  flex-direction: column;
  gap: 0.125em;
  min-width: 0;
}

.mar-weather-inline .mar-weather-now-text {
  flex-direction: row;
  align-items: baseline;
  gap: 0.5em;
}

.mar-weather-place {
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.mar-weather-condition {
  color: var(--mar-text-muted-color);
  font-size: 0.8125em;
}

.mar-weather-details {
  display: flex;
  flex-wrap: wrap;
  gap: 1.5385em;
  padding-top: 1.0769em;
  border-top: 1px solid var(--mar-content-border-color);
  color: var(--mar-text-muted-color);
  font-size: 0.8125em;
}

.mar-weather-detail {
  display: inline-flex;
  align-items: center;
  gap: 0.4615em;
  font-variant-numeric: tabular-nums;
}

.mar-weather-detail :deep(svg) {
  width: 1.2308em;
  height: 1.2308em;
}

.mar-weather-strip {
  display: flex;
  gap: 0.5em;
  overflow-x: auto;
  padding-top: 0.875em;
  border-top: 1px solid var(--mar-content-border-color);
}

.mar-weather-cell {
  display: flex;
  flex: 1 0 3.5em;
  flex-direction: column;
  align-items: center;
  gap: 0.375em;
  padding: 0.5em 0.25em;
  border-radius: 8px;
  background: var(--mar-surface-100);
}

.mar-weather-cell-time {
  color: var(--mar-text-muted-color);
  font-size: 0.6875em;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}

.mar-weather-cell-icon {
  width: 1.5em;
  height: 1.5em;
  color: var(--mar-primary-color);
}

.mar-weather-cell-temp {
  font-size: 0.9375em;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.mar-weather-cell-low {
  color: var(--mar-text-muted-color);
  font-size: 0.75em;
  font-variant-numeric: tabular-nums;
}

.mar-weather-credit {
  color: var(--mar-text-muted-color);
  font-size: 0.6875em;
  text-decoration: none;
}

.mar-weather-credit:hover {
  text-decoration: underline;
}
</style>
