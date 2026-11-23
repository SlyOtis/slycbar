import type { Awareness } from "y-protocols/awareness";
import type { Selection } from "../model/types";
import type { CollabUser } from "./provider";

export interface RemoteSelection {
  blockId: string;
  anchorOffset: number;
  headOffset: number;
}

export interface RemotePeer {
  clientId: number;
  user: CollabUser;
  selection: RemoteSelection | null;
}

export const selectionToAwareness = (selection: Selection | null): RemoteSelection | null => {
  if (!selection) return null;
  if (selection.kind === "text") {
    return {
      blockId: selection.head.blockId,
      anchorOffset: selection.anchor.offset,
      headOffset: selection.head.offset,
    };
  }
  if (selection.kind === "node") {
    return { blockId: selection.blockId, anchorOffset: 0, headOffset: 0 };
  }
  const last = selection.ids[selection.ids.length - 1];
  return last ? { blockId: last, anchorOffset: 0, headOffset: 0 } : null;
};

export const remotePeers = (awareness: Awareness): RemotePeer[] => {
  const peers: RemotePeer[] = [];
  awareness.getStates().forEach((state, clientId) => {
    if (clientId === awareness.clientID) return;
    const user = state?.user as CollabUser | undefined;
    if (!user) return;
    peers.push({
      clientId,
      user,
      selection: (state?.selection as RemoteSelection | null) ?? null,
    });
  });
  return peers;
};
