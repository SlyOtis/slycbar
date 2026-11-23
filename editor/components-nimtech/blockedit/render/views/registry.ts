import { markRaw, type Component } from "vue";

export interface BlockViewDef {
  type: string;
  component: Component;
}

const views = new Map<string, BlockViewDef>();

export const registerBlockView = (def: BlockViewDef): void => {
  views.set(def.type, { ...def, component: markRaw(def.component) });
};

export const resolveBlockView = (type: string): BlockViewDef | undefined =>
  views.get(type);

export const hasBlockView = (type: string): boolean => views.has(type);
