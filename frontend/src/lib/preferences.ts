
const PREF_FILE = 'preferences.json';

export type Theme = 'light' | 'dark' | 'auto';

export interface Preferences {
  show_recording_notification: boolean;
  theme: Theme;
}

export type PrefKey = keyof Preferences;

export const PREF_KEYS = {
  showRecordingNotification: 'show_recording_notification',
  theme: 'theme',
} as const satisfies Record<string, PrefKey>;

export const PREF_DEFAULTS: Preferences = {
  show_recording_notification: true,
  theme: 'auto',
};

async function loadStore() {
  const { Store } = await import('@tauri-apps/plugin-store');
  return Store.load(PREF_FILE);
}

export async function getPref<K extends PrefKey>(key: K): Promise<Preferences[K]> {
  const store = await loadStore();
  const value = await store.get<Preferences[K]>(key);
  return value ?? PREF_DEFAULTS[key];
}

export async function setPref<K extends PrefKey>(
  key: K,
  value: Preferences[K],
): Promise<void> {
  const store = await loadStore();
  await store.set(key, value);
  await store.save();
}
