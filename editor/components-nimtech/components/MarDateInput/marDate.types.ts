export type MarDateMode = "single" | "range" | "week";

export interface MarDateRange {
  /** Start of the range, null while unset. */
  start: Date | null;
  /** End of the range, null while unset. */
  end: Date | null;
}

export type MarDateValue = Date | MarDateRange | null;

export type MarDateField = "day" | "month" | "year" | "hour" | "minute";

export interface MarDateMaskToken {
  /** Field the slot carries, null for a literal separator. */
  field: MarDateField | null;
  /** Literal text of a separator slot. */
  text: string;
  /** Digits the slot holds when full. */
  size: number;
  /** Range edge the slot belongs to. */
  edge: "start" | "end";
  /** The slot is the year or the separator beside it, left out when both edges share the year and the field is narrow. */
  year: boolean;
  /** The slot is part of the date of its edge, left out when both edges share the day and the field is narrow. */
  date: boolean;
  /** Format token of a field slot, the part of the date or time format the slot renders through `formatDate`; empty for a separator. */
  pattern: string;
  /** The month slot shows and takes the month name rather than its number. */
  named: boolean;
}

export interface MarDateLabels {
  /** Label of the panel confirm action. */
  confirm: string;
  /** Label of the panel cancel action. */
  cancel: string;
  /** Label of the panel today action. */
  today: string;
  /** Label of the panel clear action and the trigger clear cross. */
  clear: string;
  /** Head text while no date is drafted in single mode. */
  selectDate: string;
  /** Head text while no range is drafted in range or week mode. */
  selectRange: string;
  /** Head mode text in single mode. */
  date: string;
  /** Head mode text in week mode. */
  week: string;
  /** Head mode text in range mode. */
  range: string;
  /** Accessible label of the previous month button. */
  previousMonth: string;
  /** Accessible label of the next month button. */
  nextMonth: string;
  /** Label of the time row in single mode. */
  time: string;
  /** Label of the start time row in range mode. */
  start: string;
  /** Label of the end time row in range mode. */
  end: string;
  /** Accessible label of the start hour input. */
  hour: string;
  /** Accessible label of the start hour up button. */
  hourUp: string;
  /** Accessible label of the start hour down button. */
  hourDown: string;
  /** Accessible label of the start minute input. */
  minute: string;
  /** Accessible label of the start minute up button. */
  minuteUp: string;
  /** Accessible label of the start minute down button. */
  minuteDown: string;
  /** Accessible label of the end hour input. */
  endHour: string;
  /** Accessible label of the end hour up button. */
  endHourUp: string;
  /** Accessible label of the end hour down button. */
  endHourDown: string;
  /** Accessible label of the end minute input. */
  endMinute: string;
  /** Accessible label of the end minute up button. */
  endMinuteUp: string;
  /** Accessible label of the end minute down button. */
  endMinuteDown: string;
}

export const MAR_DATE_LABELS: Required<MarDateLabels> = {
  confirm: "OK",
  cancel: "Cancel",
  today: "Today",
  clear: "Clear",
  selectDate: "Select date",
  selectRange: "Select range",
  date: "Date",
  week: "Week",
  range: "Range",
  previousMonth: "Previous month",
  nextMonth: "Next month",
  time: "Time",
  start: "Start",
  end: "End",
  hour: "Hour",
  hourUp: "Hour up",
  hourDown: "Hour down",
  minute: "Minute",
  minuteUp: "Minute up",
  minuteDown: "Minute down",
  endHour: "End hour",
  endHourUp: "End hour up",
  endHourDown: "End hour down",
  endMinute: "End minute",
  endMinuteUp: "End minute up",
  endMinuteDown: "End minute down",
};

export interface MarDatePreset {
  /** Text of the preset button. */
  label: string;
  /** A date in single mode or a range otherwise, or a function of today at midnight returning one. */
  value: Exclude<MarDateValue, null> | ((today: Date) => Exclude<MarDateValue, null>);
}
