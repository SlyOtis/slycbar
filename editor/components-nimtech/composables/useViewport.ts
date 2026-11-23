import { onBeforeUnmount, onMounted, ref, type Ref } from "vue";
import { MOBILE_BREAKPOINT, MOBILE_QUERY } from "@/utils/viewport";

export { MOBILE_BREAKPOINT, MOBILE_QUERY };

export function useViewport(): { mobile: Ref<boolean> } {
  const query =
    typeof window === "undefined" ? null : window.matchMedia(MOBILE_QUERY);
  const mobile = ref(query?.matches ?? false);
  const onChange = (event: MediaQueryListEvent) => {
    mobile.value = event.matches;
  };

  onMounted(() => {
    if (!query) return;
    mobile.value = query.matches;
    query.addEventListener("change", onChange);
  });

  onBeforeUnmount(() => {
    query?.removeEventListener("change", onChange);
  });

  return { mobile };
}
