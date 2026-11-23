import { defineAsyncComponent } from "vue";
import { registerBlockView } from "./registry";

let registered = false;

export const registerDefaultViews = (): void => {
  if (registered) return;
  registered = true;
  registerBlockView({
    type: "codeBlock",
    component: defineAsyncComponent(() => import("./CodeBlockView.vue")),
  });
  registerBlockView({
    type: "callout",
    component: defineAsyncComponent(
      () => import("@/components/MarCalloutBlock"),
    ),
  });
  registerBlockView({
    type: "image",
    component: defineAsyncComponent(() => import("@/components/MarImageBlock")),
  });
  registerBlockView({
    type: "html",
    component: defineAsyncComponent(() => import("@/components/MarHTMLBlock")),
  });
};
