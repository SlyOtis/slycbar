import { ref } from "vue";
import {
  DEFAULT_DATE_FORMAT,
  formatDate,
  isHour12Format,
  parseDateFormat,
  type MarDateFormat,
  type MarDateFormatField,
  type MarDateFormatOptions,
  type MarDateFormatPart,
} from "@/utils/dateFormat";

export {
  DEFAULT_DATE_FORMAT,
  formatDate,
  isHour12Format,
  parseDateFormat,
  type MarDateFormat,
  type MarDateFormatField,
  type MarDateFormatOptions,
  type MarDateFormatPart,
};

const dateFormat = ref<MarDateFormat>({ ...DEFAULT_DATE_FORMAT });

export const useDateFormat = () => dateFormat;

export const setDateFormat = (format: Partial<MarDateFormat>): void => {
  dateFormat.value = {
    date: format.date || DEFAULT_DATE_FORMAT.date,
    time: format.time || DEFAULT_DATE_FORMAT.time,
    month: format.month || DEFAULT_DATE_FORMAT.month,
    locale: format.locale || undefined,
  };
};
