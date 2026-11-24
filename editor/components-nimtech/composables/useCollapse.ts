import {
  computed,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
  type CSSProperties,
  type Ref,
} from "vue";

export interface UseCollapse {
  body: Ref<HTMLElement | null>;
  size: Ref<number>;
  style: Ref<CSSProperties>;
  observe: () => void;
  onTransitionEnd: (event: TransitionEvent) => void;
}

export const COLLAPSE_TRANSITION =
  "max-height var(--mar-collapse-duration) var(--mar-collapse-ease)";

export function useCollapse(
  open: () => boolean,
  closed: () => number = () => 0,
  onResize?: () => void,
): UseCollapse {
  const body = ref<HTMLElement | null>(null);
  const size = ref(0);
  const moving = ref(false);
  let observer: ResizeObserver | null = null;

  const measure = () => {
    if (body.value) size.value = body.value.scrollHeight;
    onResize?.();
  };

  const observe = () => {
    observer?.disconnect();
    if (!body.value) return;
    observer = observer ?? new ResizeObserver(measure);
    observer.observe(body.value);
    if (body.value.firstElementChild) observer.observe(body.value.firstElementChild);
    measure();
  };

  onMounted(observe);

  onBeforeUnmount(() => {
    observer?.disconnect();
    observer = null;
  });

  watch(open, (value) => {
    if (!value && !moving.value && body.value) {
      body.value.style.maxHeight = `${body.value.scrollHeight}px`;
      void body.value.offsetHeight;
    }
    moving.value = size.value !== closed();
  });

  const onTransitionEnd = (event: TransitionEvent) => {
    if (event.target !== body.value || event.propertyName !== "max-height") return;
    moving.value = false;
  };

  const style = computed<CSSProperties>(() => ({
    maxHeight: open() ? (moving.value && size.value ? `${size.value}px` : "none") : `${closed()}px`,
    overflow: open() && !moving.value ? undefined : "clip",
    transition: COLLAPSE_TRANSITION,
  }));

  return { body, size, style, observe, onTransitionEnd };
}

export function useCollapseTransition(): {
  onBeforeEnter: (el: Element) => void;
  onEnter: (el: Element, done: () => void) => void;
  onAfterEnter: (el: Element) => void;
  onBeforeLeave: (el: Element) => void;
  onLeave: (el: Element, done: () => void) => void;
} {
  const settle = (node: HTMLElement, done: () => void) => {
    const finish = (event: TransitionEvent) => {
      if (event.target !== node || event.propertyName !== "max-height") return;
      node.removeEventListener("transitionend", finish);
      done();
    };
    node.addEventListener("transitionend", finish);
  };

  const onBeforeEnter = (el: Element) => {
    const node = el as HTMLElement;
    node.style.overflow = "clip";
    node.style.maxHeight = "0px";
    node.style.transition = COLLAPSE_TRANSITION;
  };

  const onEnter = (el: Element, done: () => void) => {
    const node = el as HTMLElement;
    const target = node.scrollHeight;
    void node.offsetHeight;
    node.style.maxHeight = `${target}px`;
    if (!target) done();
    else settle(node, done);
  };

  const onAfterEnter = (el: Element) => {
    const node = el as HTMLElement;
    node.style.maxHeight = "";
    node.style.overflow = "";
    node.style.transition = "";
  };

  const onBeforeLeave = (el: Element) => {
    const node = el as HTMLElement;
    node.style.overflow = "clip";
    node.style.transition = COLLAPSE_TRANSITION;
    node.style.maxHeight = `${node.scrollHeight}px`;
    void node.offsetHeight;
  };

  const onLeave = (el: Element, done: () => void) => {
    const node = el as HTMLElement;
    if (!node.scrollHeight) {
      done();
      return;
    }
    node.style.maxHeight = "0px";
    settle(node, done);
  };

  return { onBeforeEnter, onEnter, onAfterEnter, onBeforeLeave, onLeave };
}
