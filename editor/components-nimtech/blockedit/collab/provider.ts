import type { Awareness } from "y-protocols/awareness";

export type CollabProviderEvent = "synced" | "status";

export interface CollabProvider {
  awareness: Awareness;
  connected: boolean;
  synced: boolean;
  on(event: CollabProviderEvent, handler: (payload?: unknown) => void): void;
  off(event: CollabProviderEvent, handler: (payload?: unknown) => void): void;
  destroy(): void;
}

export interface CollabUser {
  name: string;
  color: string;
}
