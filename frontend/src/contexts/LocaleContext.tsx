'use client';

import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  ReactNode,
} from 'react';
import { getPref, setPref, hasPref, PREF_KEYS, type Locale } from '@/lib/preferences';
import i18n, { detectInitialLocale, LOCALES } from '@/i18n';

export type { Locale };

interface LocaleContextType {
  locale: Locale;
  setLocale: (locale: Locale) => void;
}

const LocaleContext = createContext<LocaleContextType | undefined>(undefined);

const isValidLocale = (v: unknown): v is Locale =>
  typeof v === 'string' && (LOCALES as string[]).includes(v);

function applyLocale(locale: Locale) {
  if (i18n.language !== locale) i18n.changeLanguage(locale);
  if (typeof document !== 'undefined') document.documentElement.lang = locale;
}

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(detectInitialLocale());

  // Load the stored locale on mount; if none stored yet (first run), keep the
  // system-detected one so onboarding shows in the user's language.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const stored = await hasPref(PREF_KEYS.locale);
        const value = stored ? await getPref(PREF_KEYS.locale) : detectInitialLocale();
        if (!cancelled && isValidLocale(value)) {
          setLocaleState(value);
          applyLocale(value);
        }
      } catch (e) {
        console.error('[LocaleProvider] Failed to load locale preference:', e);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    applyLocale(locale);
  }, [locale]);

  const setLocale = useCallback((next: Locale) => {
    setLocaleState(next);
    applyLocale(next);
    (async () => {
      try {
        await setPref(PREF_KEYS.locale, next);
      } catch (e) {
        console.error('[LocaleProvider] Failed to persist locale:', e);
      }
      // Notify the Rust side (tray menu, default meeting name) to re-localize.
      try {
        const { emit } = await import('@tauri-apps/api/event');
        await emit('locale-changed', next);
      } catch {
        /* not in Tauri runtime — ignore */
      }
    })();
  }, []);

  return (
    <LocaleContext.Provider value={{ locale, setLocale }}>
      {children}
    </LocaleContext.Provider>
  );
}

export function useLocale(): LocaleContextType {
  const ctx = useContext(LocaleContext);
  if (!ctx) {
    throw new Error('useLocale must be used within a LocaleProvider');
  }
  return ctx;
}
