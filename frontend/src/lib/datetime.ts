import { BCP47 } from '@/i18n';
import type { Locale } from '@/lib/preferences';

const DEFAULT_DATE_OPTS: Intl.DateTimeFormatOptions = {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
};

/** Locale-aware date (defaults to "20 June 2026" style in the active locale). */
export function formatDate(
  date: string | number | Date,
  locale: Locale,
  opts: Intl.DateTimeFormatOptions = DEFAULT_DATE_OPTS,
): string {
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString(BCP47[locale], opts);
}

/** Locale-aware date + time. */
export function formatDateTime(
  date: string | number | Date,
  locale: Locale,
  opts?: Intl.DateTimeFormatOptions,
): string {
  const d = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString(BCP47[locale], opts);
}
