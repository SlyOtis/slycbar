import { onBeforeUnmount, onMounted, ref, watch, type Ref } from "vue";
import {
  generateOrganicPath,
  resolveOrganicOptions,
  type OrganicPathOptions,
} from "@/utils/organicPath";

export interface OrganicClipOptions {
  active: () => boolean;
  path: () => OrganicPathOptions;
  seed?: () => number | undefined;
}

export const useOrganicClip = (
  el: Ref<HTMLElement | null>,
  options: OrganicClipOptions,
): Ref<string> => {
  const clipPath = ref("");
  let observer: ResizeObserver | null = null;
  let randomSeed = 1;

  const applyClip = () => {
    const target = el.value;
    if (!target || !options.active()) {
      clipPath.value = "";
      return;
    }
    const w = target.offsetWidth;
    const h = target.offsetHeight;
    if (!w || !h) return;
    const seed = options.seed?.() ?? randomSeed;
    clipPath.value = generateOrganicPath(seed, w, h, resolveOrganicOptions(options.path()));
  };

  onMounted(() => {
    randomSeed = Math.floor(1 + Math.random() * 2147483646);
    observer = new ResizeObserver(applyClip);
    if (el.value) observer.observe(el.value);
    applyClip();
  });

  watch(
    () => {
      const p = options.path();
      return [
        options.active(),
        options.seed?.(),
        p.wobble,
        p.inset,
        p.points,
        p.rectangular,
        Array.isArray(p.edges) ? p.edges.join(",") : p.edges,
      ];
    },
    () => applyClip(),
  );

  onBeforeUnmount(() => observer?.disconnect());

  return clipPath;
};
