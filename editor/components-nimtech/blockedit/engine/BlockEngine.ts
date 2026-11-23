import { ref, shallowRef, triggerRef, type Ref, type ShallowRef } from "vue";
import type { BlockId, MarDocument, Selection } from "../model/types";
import { marDocumentToHtml } from "../serialize/htmlSerialize";
import { marDocumentToMarkdown } from "../serialize/markdown";
import { marDocumentFromContent } from "../serialize/json";
import { normalize } from "../model/normalize";
import { deltaText } from "../model/delta";
import { childIds } from "../model/tree";
import type { EditorConfig } from "./config";
import {
  createHistory,
  record,
  redo as redoHistory,
  undo as undoHistory,
  type HistoryEntry,
} from "./history";

export interface DispatchMeta {
  addToHistory?: boolean;
  coalesce?: boolean;
  emit?: boolean;
}

export type Mutator = (
  doc: MarDocument,
  selection: Selection | null,
) => { doc: MarDocument; selection?: Selection | null };

export interface CollabBinding {
  onLocalChange: (nextDoc: MarDocument) => void;
  onSelectionChange: (selection: Selection | null) => void;
  undo: () => void;
  redo: () => void;
  canUndo: () => boolean;
  canRedo: () => boolean;
}

export interface BlockEngine {
  doc: ShallowRef<MarDocument>;
  selection: ShallowRef<Selection | null>;
  editable: Ref<boolean>;
  config: EditorConfig;
  numbering: Ref<{ enabled: boolean; startLevel: number; startId: string | null }>;
  dispatch: (mutator: Mutator, meta?: DispatchMeta) => void;
  setSelection: (selection: Selection | null) => void;
  setContent: (value: MarDocument | string, emit?: boolean) => void;
  setEditable: (value: boolean) => void;
  setNumbering: (enabled: boolean, startLevel: number, startId?: string | null) => void;
  currentBlockId: () => BlockId | null;
  getValue: () => string;
  getJSON: () => string;
  getHTML: () => string;
  getMarkdown: () => string;
  getText: () => string;
  undo: () => void;
  redo: () => void;
  canUndo: () => boolean;
  canRedo: () => boolean;
  attachCollab: (binding: CollabBinding) => void;
  detachCollab: () => void;
  applyRemoteDoc: (doc: MarDocument, selection?: Selection | null) => void;
}

const textOfDoc = (doc: MarDocument): string => {
  let out = "";
  const walk = (ids: BlockId[]): void => {
    for (const id of ids) {
      const block = doc.blocks[id];
      if (!block) continue;
      if (Array.isArray(block.content)) out += `${deltaText(block.content)}\n`;
      else walk(childIds(block));
    }
  };
  walk(doc.root);
  return out;
};

export const createBlockEngine = (
  initialValue: MarDocument | string,
  config: EditorConfig = {},
  editable = true,
): BlockEngine => {
  const contentType = config.contentType ?? "json";
  const settle = (doc: MarDocument): MarDocument =>
    normalize(config.type ? { ...doc, type: config.type } : doc);
  const parse = (value: MarDocument | string): MarDocument => settle(marDocumentFromContent(value, contentType));
  const serialize = (d: MarDocument): string => {
    if (contentType === "markdown") return marDocumentToMarkdown(d);
    if (contentType === "html") return marDocumentToHtml(d);
    return JSON.stringify(d);
  };

  const doc = shallowRef<MarDocument>(parse(initialValue));
  const selection = shallowRef<Selection | null>(null);
  const editableRef = ref(editable);
  const numbering = ref<{ enabled: boolean; startLevel: number; startId: string | null }>({
    enabled: false,
    startLevel: 2,
    startId: null,
  });
  const history = createHistory();
  let collab: CollabBinding | null = null;
  let lastEmitted = serialize(doc.value);
  let lastCharCount = textOfDoc(doc.value).length;

  const emit = (): void => {
    const value = serialize(doc.value);
    if (value === lastEmitted) return;
    lastEmitted = value;
    config.onUpdate?.(value);
    const count = textOfDoc(doc.value).length;
    if (count !== lastCharCount) {
      config.onCharDiff?.(count - lastCharCount);
      lastCharCount = count;
    }
  };

  const dispatch: BlockEngine["dispatch"] = (mutator, meta = {}) => {
    const prev: HistoryEntry = { doc: doc.value, selection: selection.value };
    const result = mutator(doc.value, selection.value);
    const nextDoc = settle(result.doc);
    if (!collab && meta.addToHistory !== false) {
      record(history, prev, Date.now(), meta.coalesce === true);
    }
    doc.value = nextDoc;
    if (result.selection !== undefined) selection.value = result.selection;
    triggerRef(doc);
    collab?.onLocalChange(nextDoc);
    if (meta.emit !== false) emit();
  };

  const setSelection: BlockEngine["setSelection"] = (next) => {
    selection.value = next;
    triggerRef(selection);
    collab?.onSelectionChange(next);
  };

  const setContent: BlockEngine["setContent"] = (value, doEmit = false) => {
    if (collab) return;
    doc.value = parse(value);
    selection.value = null;
    lastEmitted = serialize(doc.value);
    history.past = [];
    history.future = [];
    triggerRef(doc);
    if (doEmit) emit();
  };

  const applyRemoteDoc: BlockEngine["applyRemoteDoc"] = (remoteDoc, nextSelection) => {
    doc.value = settle(remoteDoc);
    if (nextSelection !== undefined) selection.value = nextSelection;
    triggerRef(doc);
    emit();
  };

  const restore = (entry: HistoryEntry | null): void => {
    if (!entry) return;
    doc.value = entry.doc;
    selection.value = entry.selection;
    triggerRef(doc);
    emit();
  };

  const currentBlockId = (): BlockId | null => {
    const sel = selection.value;
    if (!sel) return null;
    if (sel.kind === "text") return sel.head.blockId;
    if (sel.kind === "node") return sel.blockId;
    return sel.ids[sel.ids.length - 1] ?? null;
  };

  return {
    doc,
    selection,
    editable: editableRef,
    config,
    numbering,
    setNumbering: (enabled, startLevel, startId = null) => {
      numbering.value = { enabled, startLevel, startId };
    },
    dispatch,
    setSelection,
    setContent,
    setEditable: (value) => {
      editableRef.value = value;
    },
    currentBlockId,
    getValue: () => serialize(doc.value),
    getJSON: () => JSON.stringify(doc.value),
    getHTML: () => marDocumentToHtml(doc.value),
    getMarkdown: () => marDocumentToMarkdown(doc.value),
    getText: () => textOfDoc(doc.value),
    undo: () => {
      if (collab) {
        collab.undo();
        return;
      }
      restore(undoHistory(history, { doc: doc.value, selection: selection.value }));
    },
    redo: () => {
      if (collab) {
        collab.redo();
        return;
      }
      restore(redoHistory(history, { doc: doc.value, selection: selection.value }));
    },
    canUndo: () => (collab ? collab.canUndo() : history.past.length > 0),
    canRedo: () => (collab ? collab.canRedo() : history.future.length > 0),
    attachCollab: (binding) => {
      collab = binding;
      history.past = [];
      history.future = [];
    },
    detachCollab: () => {
      collab = null;
    },
    applyRemoteDoc,
  };
};
