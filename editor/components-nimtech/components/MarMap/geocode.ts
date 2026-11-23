export interface MapCoordinates {
  lat: number;
  lng: number;
}

export const getCoordinates = async (
  address: string,
): Promise<MapCoordinates | null> => {
  const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q=${encodeURIComponent(address)}`;
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) return null;
  const rows = (await response.json()) as { lat: string; lon: string }[];
  const hit = rows[0];
  if (!hit) return null;
  const lat = Number(hit.lat);
  const lng = Number(hit.lon);
  if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
  return { lat, lng };
};
