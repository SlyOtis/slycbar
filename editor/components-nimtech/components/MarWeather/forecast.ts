import type { IconType } from "@/types/icon.types";

export interface WeatherPoint {
  time: string;
  symbol: string;
  temperature: number;
  low: number;
  high: number;
  windSpeed: number;
  humidity: number;
  precipitation: number;
}

export interface WeatherForecast {
  current: WeatherPoint;
  hours: WeatherPoint[];
  days: WeatherPoint[];
}

interface MetDetails {
  air_temperature?: number;
  wind_speed?: number;
  relative_humidity?: number;
  precipitation_amount?: number;
}

interface MetPeriod {
  summary?: { symbol_code?: string };
  details?: MetDetails;
}

interface MetEntry {
  time: string;
  data: {
    instant: { details: MetDetails };
    next_1_hours?: MetPeriod;
    next_6_hours?: MetPeriod;
    next_12_hours?: MetPeriod;
  };
}

const endpoint = "https://api.met.no/weatherapi/locationforecast/2.0/compact";

const cache = new Map<string, { expires: number; forecast: WeatherForecast | null }>();

const period = (entry: MetEntry): MetPeriod | undefined =>
  entry.data.next_1_hours ?? entry.data.next_6_hours ?? entry.data.next_12_hours;

const toPoint = (entry: MetEntry): WeatherPoint => {
  const instant = entry.data.instant.details;
  const ahead = period(entry);
  const temperature = Number(instant.air_temperature ?? 0);
  return {
    time: entry.time,
    symbol: ahead?.summary?.symbol_code ?? "cloudy",
    temperature,
    low: temperature,
    high: temperature,
    windSpeed: Number(instant.wind_speed ?? 0),
    humidity: Number(instant.relative_humidity ?? 0),
    precipitation: Number(ahead?.details?.precipitation_amount ?? 0),
  };
};

const dayKey = (time: string): string => {
  const date = new Date(time);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
};

const noonDistance = (time: string): number =>
  Math.abs(new Date(time).getHours() - 12);

const toDays = (points: WeatherPoint[]): WeatherPoint[] => {
  const buckets = new Map<string, WeatherPoint[]>();
  for (const point of points) {
    const key = dayKey(point.time);
    const bucket = buckets.get(key);
    if (bucket) bucket.push(point);
    else buckets.set(key, [point]);
  }
  return [...buckets.values()].map((bucket) => {
    const midday = bucket.reduce((best, point) =>
      noonDistance(point.time) < noonDistance(best.time) ? point : best,
    );
    return {
      ...midday,
      low: Math.min(...bucket.map((point) => point.temperature)),
      high: Math.max(...bucket.map((point) => point.temperature)),
      precipitation: bucket.reduce((sum, point) => sum + point.precipitation, 0),
    };
  });
};

export const getForecast = async (
  lat: number,
  lng: number,
): Promise<WeatherForecast | null> => {
  const key = `${lat.toFixed(4)},${lng.toFixed(4)}`;
  const hit = cache.get(key);
  if (hit && hit.expires > Date.now()) return hit.forecast;
  const url = `${endpoint}?lat=${lat.toFixed(4)}&lon=${lng.toFixed(4)}`;
  const response = await fetch(url, { headers: { Accept: "application/json" } });
  if (!response.ok) return null;
  const body = (await response.json()) as {
    properties?: { timeseries?: MetEntry[] };
  };
  const series = body.properties?.timeseries ?? [];
  const points = series.map(toPoint);
  const current = points[0];
  const forecast = current
    ? { current, hours: points.slice(1), days: toDays(points) }
    : null;
  const expires = Date.parse(response.headers.get("expires") ?? "");
  cache.set(key, {
    expires: Number.isNaN(expires) ? Date.now() + 900000 : expires,
    forecast,
  });
  return forecast;
};

const stem = (symbol: string): string => symbol.split("_")[0] ?? "";

export const weatherIcon = (symbol: string): IconType => {
  const base = stem(symbol);
  const night = symbol.endsWith("_night");
  if (base.includes("thunder")) return "cloud-lightning";
  if (base.includes("sleet")) return "cloud-sleet";
  if (base.includes("snow")) return "cloud-snow";
  if (base.includes("rain")) return "cloud-rain";
  if (base === "fog") return "cloud-fog";
  if (base === "cloudy") return "cloud";
  if (base === "clearsky") return night ? "moon" : "sun";
  if (base === "fair") return night ? "moon-cloud" : "sun-cloud";
  if (base === "partlycloudy") return night ? "cloud-moon" : "cloud-sun";
  return "cloud";
};

export const weatherLabel = (symbol: string): string => {
  const base = stem(symbol);
  if (base === "clearsky") return "Clear sky";
  if (base === "fair") return "Fair";
  if (base === "partlycloudy") return "Partly cloudy";
  if (base === "cloudy") return "Cloudy";
  if (base === "fog") return "Fog";
  const kind = base.includes("sleet")
    ? "sleet"
    : base.includes("snow")
      ? "snow"
      : "rain";
  const intensity = base.startsWith("heavy")
    ? "Heavy "
    : base.startsWith("light")
      ? "Light "
      : "";
  const head = `${intensity}${kind}${base.includes("showers") ? " showers" : ""}`;
  const text = base.includes("thunder") ? `${head} and thunder` : head;
  return text.charAt(0).toUpperCase() + text.slice(1);
};
