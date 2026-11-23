export interface MarDropdownOption {
  /** Text shown for the option in the list. */
  label: string;
  /** Second line under the label in the panel row, smaller and muted, wrapping; its presence on any option widens the panel. */
  description?: string;
  /** Value emitted when the option is selected. */
  value: string;
  /** Blocks selecting the option and shows a lock icon in multiple mode. */
  disabled?: boolean;
  /** Current number for the count field rendered at the start of the row; its presence adds the field. */
  count?: number;
  /** Lower clamp for the count field. */
  countMin?: number;
  /** Upper clamp for the count field. */
  countMax?: number;
  /** Text shown in an overlay tooltip anchored to the option row on hover; the consumer supplies every word of it. */
  tooltip?: string;
  /** Lifts the option into the panel head as a quick pick button; the consumer decides which option earns one. */
  quick?: boolean;
  /** Text for the quick pick button, falling back to the option label. */
  quickLabel?: string;
  /** Group the option is listed under; the panel shows each group under its own header in the order the groups first appear, options without a group first and with no header. */
  group?: string;
}
