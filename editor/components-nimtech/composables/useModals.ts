import {
  dialogKey,
  dialogNames,
  dialogQuery,
  hasDialogQuery,
  isDialogNameHeld,
  onDialogChange,
  onDialogQuery,
  dialogParam,
  splitDialogNames,
  setDialogParams,
} from "@/composables/dialogQuery";
import {
  type Component,
  markRaw,
  reactive,
  ref,
  shallowReactive,
  type Ref,
  type VNodeChild,
} from "vue";

export type ModalKind =
  | "dialog"
  | "dropdown"
  | "popup"
  | "tooltip"
  | "notification";

export type ModalBackdrop = "blur" | "dim" | "shadow" | "invisible" | "none";

const TOOLTIP_ID = "mar-tooltip";

export type ModalAlign = "start" | "center" | "end";

export type ModalSide = "top" | "bottom" | "left" | "right";

export interface ModalAnchorRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
  width: number;
  height: number;
}

export type ModalAnchorTarget =
  | HTMLElement
  | DOMRect
  | ModalAnchorRect
  | (() => HTMLElement | DOMRect | ModalAnchorRect | null);

export interface ModalAnchor {
  target: ModalAnchorTarget;
}

export interface ModalPlacement {
  side?: ModalSide;
  align?: ModalAlign;
  offset?: number;
  margin?: number;
  flip?: boolean;
  matchAnchorWidth?: boolean;
  matchAnchorMinWidth?: boolean;
  minWidth?: number | string;
  maxWidth?: number | string;
  maxHeight?: number | string;
}

export { submenuAnchor, submenuPlacement } from "@/utils/submenuAnchor";

export interface ModalPosition {
  left?: number;
  top?: number;
  right?: number;
  bottom?: number;
}

export type ModalPropValue =
  | unknown
  | Ref<unknown>
  | (() => unknown);

export type ModalEventHandler = (...args: unknown[]) => void;

export type ModalSlot = () => VNodeChild;

export interface ModalEntry {
  id: string;
  kind: ModalKind;
  component?: Component;
  text?: string;
  props: Record<string, ModalPropValue>;
  refs: Record<string, Ref<unknown>>;
  on: Record<string, ModalEventHandler>;
  slots: Record<string, ModalSlot>;
  position?: ModalPosition;
  anchor?: ModalAnchor;
  placement?: ModalPlacement;
  align?: ModalAlign;
  backdrop: ModalBackdrop;
  dismissOnBackdrop: boolean;
  dismissOnEscape: boolean;
  closable?: () => boolean | Promise<boolean>;
  historyKey?: string;
  name?: string;
  routeKeys: string[];
  onRoutePop?: (topKey: string | null) => void;
  mounting: boolean;
  closing: boolean;
  returnFocus?: HTMLElement;
  resolve: (value: unknown) => void;
}

export interface OpenModalConfig<T = unknown> {
  component?: Component;
  text?: string;
  props?: Record<string, ModalPropValue>;
  refs?: Record<string, Ref<unknown>>;
  on?: Record<string, ModalEventHandler>;
  slots?: Record<string, ModalSlot>;
  kind?: ModalKind;
  position?: ModalPosition;
  anchor?: ModalAnchor | ModalAnchorTarget;
  placement?: ModalPlacement;
  align?: ModalAlign;
  backdrop?: ModalBackdrop;
  dismissOnBackdrop?: boolean;
  dismissOnEscape?: boolean;
  historyKey?: string;
  name?: string;
  id?: string;
  _typeMarker?: T;
}

export interface ModalHandle<T = unknown> extends Promise<T | undefined> {
  id: string;
  close: (result?: unknown) => void;
  setText?: (text: string) => void;
  el: () => HTMLElement | null;
}

const stack = reactive<ModalEntry[]>([]);
export const notifications = reactive<ModalEntry[]>([]);

let counter = 0;

const defaultBackdrop = (kind: ModalKind): ModalBackdrop => {
  if (kind === "dropdown") return "shadow";
  if (kind === "popup") return "invisible";
  if (kind === "tooltip") return "none";
  if (kind === "notification") return "none";
  return "dim";
};

const normalizeAnchor = (
  anchor: ModalAnchor | ModalAnchorTarget | undefined
): ModalAnchor | undefined => {
  if (!anchor) return undefined;
  if (typeof anchor === "function") return { target: anchor };
  if (anchor instanceof Element || anchor instanceof DOMRect) {
    return { target: anchor };
  }
  if ("target" in anchor) return anchor;
  return { target: anchor as ModalAnchorTarget };
};

let dialogChangeBound = false;

const onDialogName = (value: string | null) => {
  const names = splitDialogNames(value);
  for (let i = stack.length - 1; i >= 0; i--) {
    const entry = stack[i];
    if (!entry) continue;
    if (entry.routeKeys.length === 0) continue;
    if (names.includes(entry.routeKeys[entry.routeKeys.length - 1] ?? "")) return;
    if (entry.routeKeys.length > 1) {
      entry.routeKeys.pop();
      const top = entry.routeKeys[entry.routeKeys.length - 1] ?? null;
      entry.onRoutePop?.(top);
      return;
    }
    entry.routeKeys.length = 0;
    closeModal(entry.id);
    return;
  }
};

const ensureDialogChangeBound = () => {
  if (dialogChangeBound) return;
  dialogChangeBound = true;
  onDialogChange(onDialogName);
};

const popModalHistory = (entry: ModalEntry) => {
  const n = entry.routeKeys.length;
  if (n === 0) return;
  entry.routeKeys.length = 0;
  dialogQuery().go(-n);
};

export const pushModalRoute = (id: string, key: string): void => {
  const entry = stack.find((m) => m.id === id);
  if (!entry) return;
  entry.routeKeys.push(key);
  ensureDialogChangeBound();
  setDialogParams(
    { [dialogKey]: [...dialogNames().filter((held) => held !== key), key].join(",") },
    "push"
  );
};

export const replaceModalRoute = (id: string, key: string): void => {
  const entry = stack.find((m) => m.id === id);
  if (!entry) return;
  if (entry.routeKeys.length === 0) {
    pushModalRoute(id, key);
    return;
  }
  const top = entry.routeKeys[entry.routeKeys.length - 1];
  entry.routeKeys[entry.routeKeys.length - 1] = key;
  ensureDialogChangeBound();
  setDialogParams(
    { [dialogKey]: [...dialogNames().filter((held) => held !== top && held !== key), key].join(",") },
    "replace"
  );
};

export const setModalRoutePopHandler = (
  id: string,
  handler: ((topKey: string | null) => void) | null
): void => {
  const entry = stack.find((m) => m.id === id);
  if (!entry) return;
  entry.onRoutePop = handler ?? undefined;
};

const dialogs = new Map<string, Component>();

const dialogRequires = new Map<string, string[]>();

type DialogRestore = (result: unknown, props: Record<string, unknown>) => unknown;

const dialogRestores = new Map<string, DialogRestore>();

const DIALOG_VALUE_LIMIT = 200;

const dialogKeys = (name: string): string[] =>
  Object.keys(dialogQuery().query()).filter((key) => key.startsWith(`${name}.`));

type DeclaredProp = { type?: unknown; required?: boolean } | null;

const declaredProps = (component: Component): Record<string, DeclaredProp> => {
  const declared = (component as { props?: Record<string, unknown> | string[] }).props;
  if (Array.isArray(declared))
    return Object.fromEntries(declared.map((name) => [name, null]));
  const props: Record<string, DeclaredProp> = {};
  for (const [name, value] of Object.entries(declared ?? {}))
    props[name] =
      value !== null && typeof value === "object" && !Array.isArray(value)
        ? (value as DeclaredProp)
        : { type: value };
  return props;
};

const encodeDialogValue = (value: unknown): string | null => {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (value === null || typeof value !== "object") return null;
  if (!Array.isArray(value) && Object.getPrototypeOf(value) !== Object.prototype) return null;
  const json = JSON.stringify(value);
  return json.length <= DIALOG_VALUE_LIMIT ? json : null;
};

const decodeDialogValue = (declared: DeclaredProp, value: string): unknown => {
  const types = ([] as unknown[]).concat(declared?.type ?? []);
  if (types.includes(Boolean) && (value === "true" || value === "false")) return value === "true";
  if (types.includes(String)) return value;
  if (types.includes(Number) && Number.isFinite(Number(value))) return Number(value);
  if (types.includes(Array) || types.includes(Object)) {
    try {
      return JSON.parse(value);
    } catch {
      return value;
    }
  }
  return value;
};

const dialogProps = (name: string, component: Component): Record<string, unknown> | null => {
  const declared = declaredProps(component);
  const props: Record<string, unknown> = {};
  for (const key of dialogKeys(name)) {
    const prop = key.slice(name.length + 1);
    const value = dialogParam(key);
    if (prop in declared && value !== null)
      props[prop] = decodeDialogValue(declared[prop] ?? null, value);
  }
  for (const [prop, rule] of Object.entries(declared))
    if (rule?.required && !(prop in props)) return null;
  for (const prop of dialogRequires.get(name) ?? []) if (!(prop in props)) return null;
  return props;
};

const dialogName = (config: OpenModalConfig<unknown>): string | undefined => {
  if (!hasDialogQuery() || (config.kind ?? "dialog") !== "dialog") return undefined;
  let name = config.name;
  if (!name && config.component)
    for (const [key, component] of dialogs) if (component === config.component) name = key;
  if (!name || stack.some((entry) => entry.name === name && !entry.closing)) return undefined;
  for (const prop of dialogRequires.get(name) ?? [])
    if (encodeDialogValue(config.props?.[prop]) === null) return undefined;
  return name;
};

const dialogPatch = (names: string[]): Record<string, string | null> => {
  const patch: Record<string, string | null> = {
    [dialogKey]: names.length ? names.join(",") : null,
  };
  for (const name of dialogNames())
    if (!names.includes(name)) for (const key of dialogKeys(name)) patch[key] = null;
  return patch;
};

const writeDialog = (entry: ModalEntry) => {
  const name = entry.name;
  if (!name || dialogNames().includes(name)) return;
  const names = dialogNames().filter(
    (held) =>
      isDialogNameHeld(held) ||
      stack.some(
        (open) => (open.name === held || open.routeKeys.includes(held)) && !open.closing
      )
  );
  const patch = dialogPatch([...names, name]);
  const component = dialogs.get(name);
  if (component && component === entry.component) {
    const declared = declaredProps(component);
    for (const [key, value] of Object.entries(entry.props)) {
      const encoded = key in declared ? encodeDialogValue(value) : null;
      if (encoded !== null) patch[`${name}.${key}`] = encoded;
    }
  }
  setDialogParams(patch);
};

const clearDialog = (name: string) => {
  if (!dialogNames().includes(name)) return;
  setDialogParams(dialogPatch(dialogNames().filter((held) => held !== name)));
};

const onNamedDialog = () => {
  const names = dialogNames();
  for (const entry of [...stack])
    if (entry.name && !names.includes(entry.name) && !entry.closing) closeModal(entry.id);
  for (const name of names) {
    const component = dialogs.get(name);
    if (!component || stack.some((entry) => entry.name === name)) continue;
    const props = dialogProps(name, component);
    if (!props) {
      clearDialog(name);
      continue;
    }
    void openModal({ kind: "dialog", name, component, props }).then((result) =>
      dialogRestores.get(name)?.(result, props)
    );
  }
};

export const setDialogs = (named: Record<string, Component>, requires: string[] = []): void => {
  for (const [name, component] of Object.entries(named)) {
    dialogs.set(name, markRaw(component));
    if (requires.length) dialogRequires.set(name, requires);
  }
  if (hasDialogQuery()) onNamedDialog();
};

export const onDialogRestore = (name: string, restore: DialogRestore): void => {
  dialogRestores.set(name, restore);
  if (hasDialogQuery()) onNamedDialog();
};

onDialogQuery(() => {
  onDialogChange(onNamedDialog);
  onNamedDialog();
});

export const LEAVE_DURATION_MS = 260;

const closeTimers = new Map<string, ReturnType<typeof setTimeout>>();

const cancelCloseTimer = (id: string) => {
  const t = closeTimers.get(id);
  if (t == null) return;
  clearTimeout(t);
  closeTimers.delete(id);
};

const anchorElement = (entry: ModalEntry): Element | null => {
  const target = entry.anchor?.target;
  const value = typeof target === "function" ? target() : target;
  return value instanceof Element ? value : null;
};

export const modalAnchorElement = (id: string): Element | null => {
  const entry = stack.find((m) => m.id === id);
  return entry ? anchorElement(entry) : null;
};

let tooltipActivationBound = false;

const onTooltipActivation = (e: Event) => {
  const entry = stack.find((m) => m.id === TOOLTIP_ID);
  if (!entry || entry.closing) return;
  const anchor = anchorElement(entry);
  const target = e.target;
  if (!anchor || !(target instanceof Node) || !anchor.contains(target)) return;
  closeModal(TOOLTIP_ID);
};

const ensureTooltipActivationBound = () => {
  if (tooltipActivationBound) return;
  if (typeof document === "undefined") return;
  tooltipActivationBound = true;
  document.addEventListener("click", onTooltipActivation, true);
};

const focusTaker = (kind: ModalKind): HTMLElement | undefined => {
  if (kind === "tooltip" || kind === "notification") return undefined;
  if (typeof document === "undefined") return undefined;
  const active = document.activeElement;
  return active instanceof HTMLElement && active !== document.body
    ? active
    : undefined;
};

const returnFocusTo = (entry: ModalEntry): void => {
  const target = entry.returnFocus;
  if (!target || !target.isConnected) return;
  const active = document.activeElement;
  const shell = document.querySelector(`[data-modal-id="${entry.id}"]`);
  const inside = active instanceof Node && shell?.contains(active);
  if (active !== document.body && !inside) return;
  target.focus();
};

export const openModal = <T = unknown>(
  config: OpenModalConfig<T>
): ModalHandle<T> => {
  const kind = config.kind ?? "dialog";
  if (kind === "tooltip") ensureTooltipActivationBound();
  const id =
    config.id ?? (kind === "tooltip" ? TOOLTIP_ID : `${kind}:${(counter += 1)}`);
  const list = kind === "notification" ? notifications : stack;
  const promise = new Promise<T | undefined>((resolve) => {
    const existing = list.find((m) => m.id === id);
    if (existing) {
      cancelCloseTimer(id);
      existing.closing = false;
      existing.resolve = resolve as (value: unknown) => void;
      if (config.anchor !== undefined) existing.anchor = normalizeAnchor(config.anchor);
      if (config.placement !== undefined) existing.placement = config.placement;
      if (config.text !== undefined) existing.text = config.text;
      if (config.props) Object.assign(existing.props, config.props);
      if (config.on) Object.assign(existing.on, config.on);
      if (config.slots) Object.assign(existing.slots, config.slots);
      return;
    }
    const entry: ModalEntry = {
      id,
      kind,
      component: config.component ? markRaw(config.component) : undefined,
      text: config.text,
      props: shallowReactive({ ...(config.props ?? {}) }),
      refs: shallowReactive({ ...(config.refs ?? {}) }),
      on: shallowReactive({ ...(config.on ?? {}) }),
      slots: shallowReactive({ ...(config.slots ?? {}) }),
      position: config.position,
      anchor: normalizeAnchor(config.anchor),
      placement: config.placement,
      align: config.align,
      backdrop: config.backdrop ?? defaultBackdrop(kind),
      dismissOnBackdrop: config.dismissOnBackdrop ?? kind !== "tooltip",
      dismissOnEscape: config.dismissOnEscape ?? kind !== "tooltip",
      historyKey: config.historyKey,
      name: dialogName(config as OpenModalConfig<unknown>),
      routeKeys: [],
      mounting: true,
      closing: false,
      returnFocus: focusTaker(kind),
      resolve: resolve as (value: unknown) => void,
    };
    list.push(entry);
    if (config.historyKey) pushModalRoute(id, config.historyKey);
    writeDialog(entry);
  });
  const handle = promise as ModalHandle<T>;
  handle.id = id;
  handle.close = (result?: unknown) => closeModal(id, result);
  if (kind === "tooltip") {
    handle.setText = (text: string) => {
      const entry = stack.find((m) => m.id === id);
      if (entry) entry.text = text;
    };
  }
  handle.el = () =>
    typeof document === "undefined"
      ? null
      : (document.querySelector(`[data-modal-id="${id}"]`) as HTMLElement | null);
  return handle;
};

export const clearModalMounting = (id: string): void => {
  const entry = stack.find((m) => m.id === id);
  if (!entry) return;
  entry.mounting = false;
};

export const closeModal = (id?: string, result?: unknown): void => {
  let entry: ModalEntry | undefined;
  let list: ModalEntry[] = stack;
  if (id) {
    entry = stack.find((m) => m.id === id);
    if (entry) list = stack;
    else {
      entry = notifications.find((m) => m.id === id);
      if (entry) list = notifications;
    }
  } else {
    entry = stack[stack.length - 1];
    list = stack;
  }
  if (!entry) return;
  if (entry.closing) return;
  entry.closing = true;
  if (entry.name) clearDialog(entry.name);
  returnFocusTo(entry);
  cancelCloseTimer(entry.id);
  const target = entry;
  const targetList = list;
  const timer = setTimeout(() => {
    closeTimers.delete(target.id);
    const at = targetList.indexOf(target);
    if (at < 0) return;
    popModalHistory(target);
    targetList.splice(at, 1);
    target.resolve(result);
  }, LEAVE_DURATION_MS);
  closeTimers.set(target.id, timer);
};

export const setModalHistory = (
  id: string,
  historyKey: string | null
): void => {
  const entry = stack.find((m) => m.id === id);
  if (!entry) return;
  if (historyKey == null) {
    popModalHistory(entry);
    entry.historyKey = undefined;
    return;
  }
  entry.historyKey = historyKey;
  if (entry.routeKeys.length === 0) {
    pushModalRoute(id, historyKey);
    return;
  }
  replaceModalRoute(id, historyKey);
};

export const useModalStack = () => stack;

export type MarNotificationSeverity = "success" | "info" | "warning" | "error";

export interface MarNotificationAction {
  label: string;
  icon?: string;
  onClick: () => void;
}

export interface MarNotificationItem {
  id: string;
  severity: MarNotificationSeverity;
  summary?: string;
  detail?: string;
  progress?: number;
  action?: MarNotificationAction;
  onClick?: () => void;
  onDismiss?: (anchor?: HTMLElement) => void;
}

export interface MarNotificationHooks {
  onClick?: () => void;
  onDismiss?: (anchor?: HTMLElement) => void;
}

export type MarNotificationCorner =
  | "top-left"
  | "top-right"
  | "bottom-left"
  | "bottom-right";

const notificationCorner = ref<MarNotificationCorner>("bottom-right");

export const useNotificationCorner = () => notificationCorner;

export const setNotificationCorner = (corner: MarNotificationCorner): void => {
  notificationCorner.value = corner;
};

const notificationTimers = new Map<string, ReturnType<typeof setTimeout>>();

const armNotificationTimer = (id: string, timeoutMs: number): void => {
  const existing = notificationTimers.get(id);
  if (existing != null) clearTimeout(existing);
  if (timeoutMs > 0) {
    notificationTimers.set(
      id,
      setTimeout(() => dismiss(id), timeoutMs),
    );
  }
};

export const notify = (
  severity: MarNotificationSeverity,
  summary?: string,
  detail?: string,
  timeoutMs = 4000,
  action?: MarNotificationAction,
  hooks?: MarNotificationHooks,
): string => {
  const duplicate = notifications.find(
    (m) =>
      m.kind === "notification" &&
      !m.closing &&
      m.props.severity === severity &&
      m.props.summary === summary &&
      m.props.detail === detail &&
      !m.props.action,
  );
  if (duplicate && !action) {
    armNotificationTimer(duplicate.id, timeoutMs);
    return duplicate.id;
  }
  counter += 1;
  const id = `notification:${counter}`;
  openModal({
    id,
    kind: "notification",
    props: { severity, summary, detail, action, clickable: !!hooks?.onClick },
    on: {
      action: () => action?.onClick(),
      cardClick: () => hooks?.onClick?.(),
      close: (anchor?: unknown) => {
        if (hooks?.onDismiss) hooks.onDismiss(anchor as HTMLElement | undefined);
        else dismiss(id);
      },
    },
  });
  armNotificationTimer(id, timeoutMs);
  return id;
};

export const updateNotification = (
  id: string,
  patch: Partial<Omit<MarNotificationItem, "id">>,
  timeoutMs?: number,
): void => {
  const entry = notifications.find((m) => m.id === id);
  if (!entry) return;
  Object.assign(entry.props, patch);
  if (timeoutMs !== undefined) armNotificationTimer(id, timeoutMs);
};

export const dismiss = (id: string): void => {
  const t = notificationTimers.get(id);
  if (t != null) {
    clearTimeout(t);
    notificationTimers.delete(id);
  }
  closeModal(id);
};

export const clearNotifications = (): void => {
  for (const t of notificationTimers.values()) clearTimeout(t);
  notificationTimers.clear();
  for (const entry of [...notifications]) {
    closeModal(entry.id);
  }
};
