import { ref, type Ref } from "vue";
import {
  THEME_QUERY,
  applyThemeMode,
  applyThemePalette,
  getThemeVariant,
  resolveThemeVariant,
  type ThemeMode,
  type ThemeOptions,
  type ThemeVariant,
} from "@/utils/theme";

export {
  THEME_QUERY,
  applyThemeMode,
  getThemeVariant,
  resolveThemeVariant,
  type ThemeMode,
  type ThemeOptions,
  type ThemeVariant,
};

const variant = ref<ThemeVariant>("system");
const current = ref<ThemeMode>("light");
const palette = ref<string | undefined>(undefined);
let onChange: ThemeOptions["onChange"];
let listening = false;

function apply(next: ThemeVariant) {
  variant.value = next;
  current.value = resolveThemeVariant(next);
  applyThemeMode(current.value);
}

function onSystemChange() {
  if (variant.value === "system") apply("system");
}

function setPalette(next: string | undefined) {
  palette.value = next;
  applyThemePalette(next);
}

function init(options: ThemeOptions = {}) {
  onChange = options.onChange ?? onChange;
  apply(getThemeVariant(options.variant));
  setPalette(options.palette ?? undefined);
  if (!listening && typeof window !== "undefined") {
    window.matchMedia(THEME_QUERY).addEventListener("change", onSystemChange);
    listening = true;
  }
}

function setTheme(next: ThemeVariant) {
  apply(next);
  void Promise.resolve(onChange?.(next)).catch(() => {});
}

function toggle() {
  setTheme(current.value === "dark" ? "light" : "dark");
}

export function useTheme(): {
  variant: Ref<ThemeVariant>;
  current: Ref<ThemeMode>;
  palette: Ref<string | undefined>;
  init: (options?: ThemeOptions) => void;
  setTheme: (next: ThemeVariant) => void;
  toggle: () => void;
  setPalette: (next: string | undefined) => void;
} {
  return { variant, current, palette, init, setTheme, toggle, setPalette };
}
