import type { MarDocument, Selection } from "../model/types";

export interface HistoryEntry {
  doc: MarDocument;
  selection: Selection | null;
}

export interface HistoryState {
  past: HistoryEntry[];
  future: HistoryEntry[];
  lastAt: number;
  coalescing: boolean;
}

const LIMIT = 200;
const COALESCE_MS = 400;

export const createHistory = (): HistoryState => ({
  past: [],
  future: [],
  lastAt: 0,
  coalescing: false,
});

export const record = (
  history: HistoryState,
  prev: HistoryEntry,
  now: number,
  coalesce: boolean,
): void => {
  const mergeable =
    coalesce && history.coalescing && now - history.lastAt < COALESCE_MS;
  history.coalescing = coalesce;
  history.lastAt = now;
  history.future = [];
  if (mergeable) return;
  history.past.push(prev);
  if (history.past.length > LIMIT) history.past.shift();
};

export const undo = (
  history: HistoryState,
  current: HistoryEntry,
): HistoryEntry | null => {
  const entry = history.past.pop();
  if (!entry) return null;
  history.future.push(current);
  history.coalescing = false;
  return entry;
};

export const redo = (
  history: HistoryState,
  current: HistoryEntry,
): HistoryEntry | null => {
  const entry = history.future.pop();
  if (!entry) return null;
  history.past.push(current);
  history.coalescing = false;
  return entry;
};
