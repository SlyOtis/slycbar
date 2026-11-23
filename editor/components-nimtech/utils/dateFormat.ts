export interface MarDateFormat {
  date: string;
  time: string;
  month: string;
  locale?: string;
}

export const DEFAULT_DATE_FORMAT: MarDateFormat = {
  date: "dd.MM.yyyy",
  time: "HH:mm",
  month: "MMMM yyyy",
};

export type MarDateFormatField =
  | "year"
  | "month"
  | "day"
  | "weekday"
  | "hour"
  | "minute"
  | "second"
  | "dayPeriod";

export interface MarDateFormatPart {
  field: MarDateFormatField | null;
  token: string;
  text: string;
}

export interface MarDateFormatOptions {
  locale?: string;
  timeZone?: string;
}

interface WallClock {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

const TOKEN_FIELDS: Record<string, MarDateFormatField> = {
  y: "year",
  M: "month",
  d: "day",
  E: "weekday",
  H: "hour",
  h: "hour",
  m: "minute",
  s: "second",
  a: "dayPeriod",
};

export function parseDateFormat(pattern: string): MarDateFormatPart[] {
  const parts: MarDateFormatPart[] = [];
  const literal = (text: string) => {
    if (!text) return;
    const last = parts[parts.length - 1];
    if (last && !last.field) last.text += text;
    else parts.push({ field: null, token: "", text });
  };
  let at = 0;
  while (at < pattern.length) {
    const char = pattern[at];
    if (char === "'") {
      if (pattern[at + 1] === "'") {
        literal("'");
        at += 2;
        continue;
      }
      let text = "";
      let end = at + 1;
      while (end < pattern.length) {
        if (pattern[end] === "'") {
          if (pattern[end + 1] !== "'") break;
          text += "'";
          end += 2;
          continue;
        }
        text += pattern[end];
        end += 1;
      }
      literal(text);
      at = end + 1;
      continue;
    }
    const field = TOKEN_FIELDS[char];
    if (!field) {
      literal(char);
      at += 1;
      continue;
    }
    let end = at + 1;
    while (pattern[end] === char) end += 1;
    parts.push({ field, token: pattern.slice(at, end), text: "" });
    at = end;
  }
  return parts;
}

export function isHour12Format(pattern: string): boolean {
  return parseDateFormat(pattern).some((part) => part.token.startsWith("h"));
}

const pad = (value: number, size: number): string => String(value).padStart(size, "0");

const wallClock = (date: Date, timeZone?: string): WallClock => {
  if (!timeZone) {
    return {
      year: date.getFullYear(),
      month: date.getMonth() + 1,
      day: date.getDate(),
      hour: date.getHours(),
      minute: date.getMinutes(),
      second: date.getSeconds(),
    };
  }
  const values: Partial<Record<Intl.DateTimeFormatPartTypes, number>> = {};
  for (const part of new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
  }).formatToParts(date)) {
    if (part.type !== "literal") values[part.type] = Number(part.value);
  }
  return {
    year: values.year ?? 0,
    month: values.month ?? 1,
    day: values.day ?? 1,
    hour: (values.hour ?? 0) % 24,
    minute: values.minute ?? 0,
    second: values.second ?? 0,
  };
};

const nameWidth = (size: number): "short" | "long" | "narrow" =>
  size >= 5 ? "narrow" : size === 4 ? "long" : "short";

const formatPart = (
  part: MarDateFormatPart,
  date: Date,
  clock: WallClock,
  options: MarDateFormatOptions,
): string => {
  const size = part.token.length;
  const { locale, timeZone } = options;
  if (part.field === "year") {
    if (size === 2) return pad(clock.year % 100, 2);
    return pad(clock.year, size);
  }
  if (part.field === "month") {
    if (size <= 2) return pad(clock.month, size);
    return new Intl.DateTimeFormat(locale, { month: nameWidth(size), timeZone }).format(date);
  }
  if (part.field === "day") return pad(clock.day, Math.min(size, 2));
  if (part.field === "weekday") {
    return new Intl.DateTimeFormat(locale, { weekday: nameWidth(size), timeZone }).format(date);
  }
  if (part.field === "hour") {
    const hour = part.token.startsWith("h") ? clock.hour % 12 || 12 : clock.hour;
    return pad(hour, Math.min(size, 2));
  }
  if (part.field === "minute") return pad(clock.minute, Math.min(size, 2));
  if (part.field === "second") return pad(clock.second, Math.min(size, 2));
  if (part.field === "dayPeriod") {
    const period = new Intl.DateTimeFormat(locale, { hour: "numeric", hour12: true, timeZone })
      .formatToParts(date)
      .find((entry) => entry.type === "dayPeriod");
    return period?.value ?? (clock.hour < 12 ? "AM" : "PM");
  }
  return part.text;
};

export function formatDate(
  value: Date | string | number | null | undefined,
  pattern: string,
  options: MarDateFormatOptions = {},
): string {
  if (value === null || value === undefined || value === "") return "";
  const day = typeof value === "string" ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(value) : null;
  const date =
    value instanceof Date
      ? value
      : day
        ? new Date(Number(day[1]), Number(day[2]) - 1, Number(day[3]))
        : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const clock = wallClock(date, options.timeZone);
  return parseDateFormat(pattern)
    .map((part) => formatPart(part, date, clock, options))
    .join("");
}

export function getDateWeek(date: Date, firstDayOfWeek: number): { start: Date; end: Date } {
  const start = new Date(
    date.getFullYear(),
    date.getMonth(),
    date.getDate() - ((date.getDay() - firstDayOfWeek + 7) % 7),
  );
  return { start, end: new Date(start.getFullYear(), start.getMonth(), start.getDate() + 6) };
}
