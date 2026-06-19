"use client"

import { useEffect, useState } from "react"
import { motion } from "framer-motion"
import { Switch } from "./ui/switch"
import { FolderOpen, Sun, Moon, Laptop } from "lucide-react"
import { invoke } from "@tauri-apps/api/core"
import { open as openDialog } from '@tauri-apps/plugin-dialog'
import { load } from '@tauri-apps/plugin-store'
import { useConfig, NotificationSettings } from "@/contexts/ConfigContext"
import { useTheme, Theme } from "@/contexts/ThemeContext"

const THEME_OPTIONS: { value: Theme; label: string; icon: typeof Sun }[] = [
  { value: 'light', label: 'Светлая', icon: Sun },
  { value: 'dark', label: 'Тёмная', icon: Moon },
  { value: 'auto', label: 'Авто', icon: Laptop },
]

const PREF_FILE = 'preferences.json'
const PREF_KEY_MD = 'save_summary_folder'

export function PreferenceSettings() {
  const {
    notificationSettings,
    storageLocations,
    isLoadingPreferences,
    loadPreferences,
    updateNotificationSettings
  } = useConfig();
  const { theme, setTheme } = useTheme();

  const [notificationsEnabled, setNotificationsEnabled] = useState<boolean | null>(null);
  const [isInitialLoad, setIsInitialLoad] = useState(true);
  const [previousNotificationsEnabled, setPreviousNotificationsEnabled] = useState<boolean | null>(null);
  const [mdFolder, setMdFolder] = useState<string | null>(null);

  useEffect(() => { loadPreferences(); }, [loadPreferences]);

  useEffect(() => {
    (async () => {
      try {
        const store = await load(PREF_FILE);
        const v = (await store.get(PREF_KEY_MD)) as string | null;
        setMdFolder(v ?? null);
      } catch (e) {
        console.error('Failed to load MD folder pref:', e);
      }
    })();
  }, []);

  useEffect(() => {
    if (notificationSettings) {
      const enabled =
        notificationSettings.notification_preferences.show_recording_started &&
        notificationSettings.notification_preferences.show_recording_stopped;
      setNotificationsEnabled(enabled);
      if (isInitialLoad) {
        setPreviousNotificationsEnabled(enabled);
        setIsInitialLoad(false);
      }
    } else if (!isLoadingPreferences) {
      setNotificationsEnabled(true);
      if (isInitialLoad) {
        setPreviousNotificationsEnabled(true);
        setIsInitialLoad(false);
      }
    }
  }, [notificationSettings, isLoadingPreferences, isInitialLoad])

  useEffect(() => {
    if (isInitialLoad || notificationsEnabled === null || notificationsEnabled === previousNotificationsEnabled) return;
    if (!notificationSettings) return;

    (async () => {
      try {
        const updatedSettings: NotificationSettings = {
          ...notificationSettings,
          notification_preferences: {
            ...notificationSettings.notification_preferences,
            show_recording_started: notificationsEnabled,
            show_recording_stopped: notificationsEnabled,
          }
        };
        await updateNotificationSettings(updatedSettings);
        setPreviousNotificationsEnabled(notificationsEnabled);
      } catch (error) {
        console.error('Failed to update notification settings:', error);
      }
    })();
  }, [notificationsEnabled, notificationSettings, isInitialLoad, previousNotificationsEnabled, updateNotificationSettings])

  const handleOpenFolder = async (folderType: 'database' | 'models' | 'recordings') => {
    try {
      switch (folderType) {
        case 'database':
          await invoke('open_database_folder');
          break;
        case 'models':
          await invoke('open_models_folder');
          break;
        case 'recordings':
          await invoke('open_recordings_folder');
          break;
      }
    } catch (error) {
      console.error(`Failed to open ${folderType} folder:`, error);
    }
  };

  const pickMdFolder = async () => {
    try {
      const picked = await openDialog({ directory: true, multiple: false });
      if (typeof picked === 'string') {
        const store = await load(PREF_FILE);
        await store.set(PREF_KEY_MD, picked);
        await store.save();
        setMdFolder(picked);
      }
    } catch (e) {
      console.error('Folder picker failed:', e);
    }
  };

  if (isLoadingPreferences && !notificationSettings && !storageLocations) {
    return <div className="max-w-2xl mx-auto p-6">Загрузка настроек...</div>
  }

  if (notificationsEnabled === null && !isLoadingPreferences) {
    return <div className="max-w-2xl mx-auto p-6">Загрузка настроек...</div>
  }

  const notificationsEnabledValue = notificationsEnabled ?? false;

  return (
    <div className="space-y-4">
      <div className="bg-elevated rounded-[14px] border border-line py-5 px-[22px]">
        <div className="flex items-center justify-between gap-5">
          <div>
            <h3 className="text-[15px] font-semibold text-fg">Тема</h3>
            <p className="text-[13px] text-fg-muted mt-1">Внешний вид приложения</p>
          </div>
          <div className="relative inline-flex items-center gap-[3px] rounded-[11px] bg-surface p-1">
            {THEME_OPTIONS.map((opt) => {
              const Icon = opt.icon;
              const isActive = theme === opt.value;
              return (
                <button
                  key={opt.value}
                  type="button"
                  onClick={() => setTheme(opt.value)}
                  aria-pressed={isActive}
                  className={`relative inline-flex items-center gap-[6px] px-[13px] py-[7px] rounded-[8px] text-[13px] transition-colors ${
                    isActive
                      ? 'text-fg font-medium'
                      : 'text-fg-muted hover:text-fg'
                  }`}
                >
                  {isActive && (
                    <motion.div
                      layoutId="theme-segment-indicator"
                      className="absolute inset-0 rounded-[8px] bg-elevated shadow-sm"
                      transition={{ type: 'spring', stiffness: 380, damping: 32 }}
                    />
                  )}
                  <Icon className="relative z-10 w-3.5 h-3.5" />
                  <span className="relative z-10">{opt.label}</span>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <div className="bg-elevated rounded-[14px] border border-line py-5 px-[22px]">
        <div className="flex items-center justify-between gap-5">
          <div>
            <h3 className="text-[15px] font-semibold text-fg">Уведомления</h3>
            <p className="text-[13px] text-fg-muted mt-1">Показывать уведомления о начале и конце записи</p>
          </div>
          <Switch checked={notificationsEnabledValue} onCheckedChange={setNotificationsEnabled} />
        </div>
      </div>

      <div className="bg-elevated rounded-[14px] border border-line py-5 px-[22px]">
        <h3 className="text-[15px] font-semibold text-fg">Экспорт саммари в Markdown</h3>
        <p className="text-[13px] text-fg-muted mt-1 mb-4">
          Папка, куда сохраняются файлы <code className="font-mono text-fg">.md</code> при экспорте саммари встречи.
        </p>
        <div className="flex items-center gap-3">
          <div className="flex-1 min-w-0 h-[42px] flex items-center px-3.5 rounded-[11px] bg-surface border border-line">
            <span className="text-[12.5px] text-fg-muted break-all font-mono truncate">
              {mdFolder || 'Не выбрана'}
            </span>
          </div>
          <button
            onClick={pickMdFolder}
            className="shrink-0 inline-flex items-center gap-[7px] px-4 h-[42px] text-[13px] font-medium rounded-[11px] bg-elevated border border-line-strong text-fg hover:bg-fg/[0.04] transition-colors"
          >
            <FolderOpen className="w-3.5 h-3.5" />
            Выбрать
          </button>
        </div>
      </div>

      <div className="bg-elevated rounded-[14px] border border-line py-5 px-[22px]">
        <h3 className="text-[15px] font-semibold text-fg mb-4">Расположение данных</h3>
        <div className="flex items-end gap-3">
          <div className="flex-1 min-w-0">
            <div className="font-mono text-[10px] uppercase tracking-[0.1em] text-fg-faint mb-1.5">Записи встреч</div>
            <div className="h-[42px] flex items-center px-3.5 rounded-[11px] bg-surface border border-line">
              <span className="text-[12.5px] text-fg-muted break-all font-mono truncate">
                {storageLocations?.recordings || 'Загрузка...'}
              </span>
            </div>
          </div>
          <button
            onClick={() => handleOpenFolder('recordings')}
            className="shrink-0 inline-flex items-center gap-[7px] px-4 h-[42px] text-[13px] font-medium rounded-[11px] bg-elevated border border-line-strong text-fg hover:bg-fg/[0.04] transition-colors"
          >
            <FolderOpen className="w-3.5 h-3.5" />
            Открыть
          </button>
        </div>
      </div>
    </div>
  )
}
