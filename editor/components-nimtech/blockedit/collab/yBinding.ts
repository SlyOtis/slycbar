import * as Y from "yjs";
import { ref, type Ref } from "vue";
import type { MarDocument, Selection } from "../model/types";
import type { BlockEngine, CollabBinding } from "../engine/BlockEngine";
import { applyDocDiff } from "./diff";
import { docToY, yToDoc, LOCAL_ORIGIN } from "./yDoc";
import { remotePeers, selectionToAwareness, type RemotePeer } from "./awareness";
import type { CollabProvider, CollabUser } from "./provider";

export interface YBindingOptions {
  ydoc: Y.Doc;
  field?: string;
  provider?: CollabProvider | null;
  user?: CollabUser;
}

export interface YBinding extends CollabBinding {
  peers: Ref<RemotePeer[]>;
  destroy: () => void;
}

const rebaseSelection = (selection: Selection | null, doc: MarDocument): Selection | null => {
  if (!selection) return null;
  const ids = new Set<string>(Object.keys(doc.blocks));
  if (selection.kind === "text") {
    return ids.has(selection.head.blockId) && ids.has(selection.anchor.blockId)
      ? selection
      : null;
  }
  if (selection.kind === "node") {
    return ids.has(selection.blockId) ? selection : null;
  }
  const kept = selection.ids.filter((id) => ids.has(id));
  return kept.length ? { kind: "blocks", ids: kept } : null;
};

export const createYBinding = (engine: BlockEngine, options: YBindingOptions): YBinding => {
  const field = options.field ?? "default";
  const root = options.ydoc.getArray<Y.Map<unknown>>(field);
  const peers = ref<RemotePeer[]>([]);
  const awareness = options.provider?.awareness ?? null;

  let shadow: MarDocument = engine.doc.value;
  let applyingRemote = false;

  const undoManager = new Y.UndoManager(root, {
    trackedOrigins: new Set([LOCAL_ORIGIN]),
  });

  const applyFromY = (): void => {
    const nextDoc = yToDoc(root);
    shadow = nextDoc;
    applyingRemote = true;
    try {
      engine.applyRemoteDoc(nextDoc, rebaseSelection(engine.selection.value, nextDoc));
    } finally {
      applyingRemote = false;
    }
  };

  const observer = (_events: Y.YEvent<Y.Map<unknown>>[], transaction: Y.Transaction): void => {
    if (transaction.origin === LOCAL_ORIGIN) return;
    applyFromY();
  };
  root.observeDeep(observer);

  const seed = (): void => {
    if (root.length === 0) {
      options.ydoc.transact(() => docToY(engine.doc.value, root), LOCAL_ORIGIN);
      shadow = engine.doc.value;
    } else {
      applyFromY();
    }
  };

  let removeSyncHandler: (() => void) | null = null;
  if (options.provider && !options.provider.synced) {
    const onSynced = (): void => seed();
    options.provider.on("synced", onSynced);
    removeSyncHandler = () => options.provider?.off("synced", onSynced);
  } else {
    seed();
  }

  const updatePeers = (): void => {
    if (awareness) peers.value = remotePeers(awareness);
  };
  if (awareness) {
    if (options.user) awareness.setLocalStateField("user", options.user);
    awareness.on("change", updatePeers);
    updatePeers();
  }

  const binding: YBinding = {
    peers,
    onLocalChange: (nextDoc: MarDocument): void => {
      if (applyingRemote) return;
      const prev = shadow;
      shadow = nextDoc;
      options.ydoc.transact(() => applyDocDiff(root, prev, nextDoc), LOCAL_ORIGIN);
    },
    onSelectionChange: (selection: Selection | null): void => {
      awareness?.setLocalStateField("selection", selectionToAwareness(selection));
    },
    undo: (): void => {
      undoManager.undo();
    },
    redo: (): void => {
      undoManager.redo();
    },
    canUndo: (): boolean => undoManager.canUndo(),
    canRedo: (): boolean => undoManager.canRedo(),
    destroy: (): void => {
      removeSyncHandler?.();
      root.unobserveDeep(observer);
      awareness?.off("change", updatePeers);
      undoManager.destroy();
      engine.detachCollab();
    },
  };

  engine.attachCollab(binding);
  return binding;
};
