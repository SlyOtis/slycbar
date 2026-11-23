export type ThemeMode = "light" | "dark";

export type ThemeVariant = ThemeMode | "system";

export const THEME_QUERY = "(prefers-color-scheme: dark)";

export interface ThemeOptions {
  variant?: string | null;
  palette?: string | null;
  onChange?: (variant: ThemeVariant) => void | Promise<void>;
}

export function isThemeVariant(value: unknown): value is ThemeVariant {
  return value === "light" || value === "dark" || value === "system";
}

export function getThemeVariant(value: unknown): ThemeVariant {
  return isThemeVariant(value) ? value : "system";
}

export function getSystemThemeMode(): ThemeMode {
  if (typeof window === "undefined") return "light";
  return window.matchMedia(THEME_QUERY).matches ? "dark" : "light";
}

export function resolveThemeVariant(variant: ThemeVariant): ThemeMode {
  return variant === "system" ? getSystemThemeMode() : variant;
}

export function applyThemeMode(mode: ThemeMode): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  root.setAttribute("data-theme", mode);
  root.classList.toggle("dark", mode === "dark");
}

export function applyThemePalette(palette: string | undefined): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  if (palette) root.setAttribute("data-mar-theme", palette);
  else root.removeAttribute("data-mar-theme");
}
