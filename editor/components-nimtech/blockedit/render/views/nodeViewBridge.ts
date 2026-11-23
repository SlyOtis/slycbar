import { defineComponent, h, inject, type InjectionKey, type VNode } from "vue";

export const BLOCK_CHILDREN: InjectionKey<() => VNode | VNode[] | null> =
  Symbol("blockChildren");

export const NodeViewWrapper = defineComponent({
  name: "NodeViewWrapper",
  props: { as: { type: String, default: "div" } },
  setup(props, { slots, attrs }) {
    return () =>
      h(props.as, { ...attrs, "data-node-view-wrapper": "" }, slots.default?.());
  },
});

export const NodeViewContent = defineComponent({
  name: "NodeViewContent",
  props: { as: { type: String, default: "div" } },
  setup(props, { slots }) {
    const children = inject(BLOCK_CHILDREN, null);
    return () => {
      const content = children ? children() : slots.default?.();
      const normalized = Array.isArray(content)
        ? content
        : content == null
          ? undefined
          : [content];
      return h(props.as, { "data-node-view-content": "" }, normalized);
    };
  },
});
