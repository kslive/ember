'use client';

import React, {
  createContext,
  useContext,
  useState,
  useEffect,
  useCallback,
  ReactNode,
} from 'react';
import {
  getPref,
  setPref,
  PREF_DEFAULTS,
  PREF_KEYS,
  type Theme,
} from '@/lib/preferences';

export type { Theme };

const DEFAULT_THEME: Theme = PREF_DEFAULTS.theme;

interface ThemeContextType {
  theme: Theme;
  setTheme: (theme: Theme) => void;
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined);

const isValidTheme = (v: unknown): v is Theme =>
  v === 'light' || v === 'dark' || v === 'auto';

function applyTheme(theme: Theme) {
  if (typeof document !== 'undefined') {
    document.documentElement.dataset.theme = theme;
  }
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(DEFAULT_THEME);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const saved = await getPref(PREF_KEYS.theme);
        if (!cancelled && isValidTheme(saved)) {
          setThemeState(saved);
          applyTheme(saved);
        }
      } catch (e) {
        console.error('[ThemeProvider] Failed to load theme preference:', e);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    applyTheme(theme);
  }, [theme]);

  const setTheme = useCallback((next: Theme) => {
    setThemeState(next);
    applyTheme(next);
    (async () => {
      try {
        await setPref(PREF_KEYS.theme, next);
      } catch (e) {
        console.error('[ThemeProvider] Failed to persist theme preference:', e);
      }
    })();
  }, []);

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextType {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return ctx;
}
