import { toValue, watch, type MaybeRefOrGetter } from "vue";

export interface DialogQuery {
  path: () => string;
  fullPath: () => string;
  query: () => Record<string, unknown>;
  replace: (path: string, query: Record<string, string>) => unknown;
  push: (path: string, query: Record<string, string>) => unknown;
  go: (delta: number) => unknown;
}

export const dialogKey = "dialog";

let source: DialogQuery | null = null;

let pending: { path: string; query: Record<string, string> } | null = null;

const changed = new Set<(name: string | null) => void>();

const ready = new Set<() => void>();

export const setDialogQuery = (query: DialogQuery): void => {
  source = query;
  watch(
    () => dialogParam(dialogKey),
    (name) => changed.forEach((handler) => handler(name))
  );
  ready.forEach((handler) => handler());
};

export const onDialogQuery = (handler: () => void): void => {
  if (source) handler();
  else ready.add(handler);
};

export const dialogQuery = (): DialogQuery => {
  if (!source) throw new Error("the dialog query needs setDialogQuery first");
  return source;
};

export const onDialogChange = (handler: (name: string | null) => void): void => {
  changed.add(handler);
};

export const hasDialogQuery = (): boolean => source !== null;

export const dialogParam = (key: string): string | null => {
  const value = dialogQuery().query()[key];
  return typeof value === "string" ? value : null;
};

const held = new Set<string>();

export const holdDialogName = (name: string): void => {
  held.add(name);
};

export const isDialogNameHeld = (name: string): boolean => held.has(name);

export const splitDialogNames = (value: string | null): string[] =>
  (value ?? "").split(",").filter(Boolean);

export const dialogNames = (): string[] => {
  const route = dialogQuery();
  if (pending && pending.path === route.path())
    return splitDialogNames(pending.query[dialogKey] ?? null);
  return splitDialogNames(dialogParam(dialogKey));
};

export const setDialogParams = (
  patch: Record<string, string | null>,
  mode: "replace" | "push" = "replace"
): void => {
  const route = dialogQuery();
  const path = route.path();
  const next: Record<string, string> = {};
  if (pending && pending.path === path) Object.assign(next, pending.query);
  else
    for (const [key, value] of Object.entries(route.query()))
      if (typeof value === "string") next[key] = value;
  for (const [key, value] of Object.entries(patch)) {
    if (value === null) delete next[key];
    else next[key] = value;
  }
  const target = { path, query: next };
  pending = target;
  void Promise.resolve(route[mode](path, next)).finally(() => {
    if (pending === target) pending = null;
  });
};

export function usePageBack(fallback?: MaybeRefOrGetter<string | undefined>) {
  const route = dialogQuery();

  const back = () => btoa(route.fullPath());

  const leave = () => {
    const held = dialogParam("back");
    const target = held ? atob(held) : toValue(fallback);
    if (!target) return;
    const url = new URL(target, "http://local");
    void route.push(url.pathname, Object.fromEntries(url.searchParams));
  };

  return { back, leave };
}
