export interface MarFuncEntry {
  /** Token written into the editor when the row is picked. */
  token: string;
  /** Code label shown on the row instead of the token, for a token too long to read in one line, such as a whole snippet. */
  label?: string;
  /** Muted text rendered after the token. */
  meta?: string;
  /** Second muted line under the token. */
  description?: string;
  /** Rows revealed when this one is opened. */
  children?: MarFuncEntry[];
  /** Label of the group the row sits under inside its section. */
  group?: string;
  /** Dims the row and blocks picking it, for a token that does not fit where the cursor is. */
  disabled?: boolean;
}

export interface MarFuncSection {
  /** Unique section id. */
  id: string;
  /** Section heading, rendered uppercase. */
  name: string;
  /** Muted text after the heading, naming where the entries come from. */
  meta?: string;
  /** Rows the section holds. */
  entries: MarFuncEntry[];
  /** Whether the section starts open; the heading toggles it and a search opens every section while the term stands. Defaults to true. */
  defaultExpanded?: boolean;
  /** Language the tokens are highlighted in, as MarCode names them; falls back to the list's `language`. */
  language?: string;
}
