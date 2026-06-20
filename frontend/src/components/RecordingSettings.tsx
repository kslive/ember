import React, { useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import { Switch } from '@/components/ui/switch';
import { FolderOpen, AlertTriangle } from 'lucide-react';
import { invoke } from '@tauri-apps/api/core';
import { DeviceSelection, SelectedDevices } from '@/components/DeviceSelection';
import Analytics from '@/lib/analytics';
import { toast } from 'sonner';

export interface RecordingPreferences {
  save_folder: string;
  auto_save: boolean;
  file_format: string;
  preferred_mic_device: string | null;
  preferred_system_device: string | null;
}

interface RecordingSettingsProps {
  onSave?: (preferences: RecordingPreferences) => void;
}

export function RecordingSettings({ onSave }: RecordingSettingsProps) {
  const { t } = useTranslation('recordingsettings');
  const [preferences, setPreferences] = useState<RecordingPreferences>({
    save_folder: '',
    auto_save: true,
    file_format: 'mp4',
    preferred_mic_device: null,
    preferred_system_device: null
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showRecordingNotification, setShowRecordingNotification] = useState(true);

  useEffect(() => {
    const loadPreferences = async () => {
      try {
        const prefs = await invoke<RecordingPreferences>('get_recording_preferences');
        setPreferences(prefs);
      } catch (error) {
        console.error('Failed to load recording preferences:', error);
        try {
          const defaultPath = await invoke<string>('get_default_recordings_folder_path');
          setPreferences(prev => ({ ...prev, save_folder: defaultPath }));
        } catch (defaultError) {
          console.error('Failed to get default folder path:', defaultError);
        }
      } finally {
        setLoading(false);
      }
    };

    loadPreferences();
  }, []);

  useEffect(() => {
    const loadNotificationPref = async () => {
      try {
        const { Store } = await import('@tauri-apps/plugin-store');
        const store = await Store.load('preferences.json');
        const show = await store.get<boolean>('show_recording_notification') ?? true;
        setShowRecordingNotification(show);
      } catch (error) {
        console.error('Failed to load notification preference:', error);
      }
    };
    loadNotificationPref();
  }, []);

  const handleAutoSaveToggle = async (enabled: boolean) => {
    const newPreferences = { ...preferences, auto_save: enabled };
    setPreferences(newPreferences);
    await savePreferences(newPreferences);

    await Analytics.track('auto_save_recording_toggled', {
      enabled: enabled.toString()
    });
  };

  const handleDeviceChange = async (devices: SelectedDevices) => {
    const newPreferences = {
      ...preferences,
      preferred_mic_device: devices.micDevice,
      preferred_system_device: devices.systemDevice
    };
    setPreferences(newPreferences);
    await savePreferences(newPreferences);

    await Analytics.track('default_devices_changed', {
      has_preferred_microphone: (!!devices.micDevice).toString(),
      has_preferred_system_audio: (!!devices.systemDevice).toString()
    });
  };

  const handleOpenFolder = async () => {
    try {
      await invoke('open_recordings_folder');
    } catch (error) {
      console.error('Failed to open recordings folder:', error);
    }
  };

  const handleNotificationToggle = async (enabled: boolean) => {
    try {
      setShowRecordingNotification(enabled);
      const { Store } = await import('@tauri-apps/plugin-store');
      const store = await Store.load('preferences.json');
      await store.set('show_recording_notification', enabled);
      await store.save();
      toast.success(t('toasts.notificationSaved'));
      await Analytics.track('recording_notification_preference_changed', {
        enabled: enabled.toString()
      });
    } catch (error) {
      console.error('Failed to save notification preference:', error);
      toast.error(t('toasts.notificationSaveFailed'));
    }
  };

  const savePreferences = async (prefs: RecordingPreferences) => {
    setSaving(true);
    try {
      await invoke('set_recording_preferences', { preferences: prefs });
      onSave?.(prefs);

      const micDevice = prefs.preferred_mic_device || t('toasts.defaultDevice');
      const systemDevice = prefs.preferred_system_device || t('toasts.defaultDevice');
      toast.success(t('toasts.devicesSaved'), {
        description: t('toasts.devicesSavedDescription', { mic: micDevice, system: systemDevice })
      });
    } catch (error) {
      console.error('Failed to save recording preferences:', error);
      toast.error(t('toasts.devicesSaveFailed'), {
        description: error instanceof Error ? error.message : String(error)
      });
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="animate-pulse space-y-4">
        <div className="h-[72px] bg-surface rounded-[14px]"></div>
        <div className="h-[72px] bg-surface rounded-[14px]"></div>
      </div>
    );
  }

  return (
    <div className="space-y-3.5">
      {}
      <div className="flex items-center justify-between gap-5 bg-elevated border border-line rounded-[14px] py-[18px] px-[22px]">
        <div>
          <div className="text-[15px] font-semibold text-fg">{t('autoSave.title')}</div>
          <div className="text-[13px] text-fg-muted mt-1">
            {t('autoSave.description')}
          </div>
        </div>
        <Switch
          checked={preferences.auto_save}
          onCheckedChange={handleAutoSaveToggle}
          disabled={saving}
        />
      </div>

      {}
      {preferences.auto_save && (
        <div className="bg-elevated border border-line rounded-[14px] py-[18px] px-[22px]">
          <div className="text-[15px] font-semibold text-fg">{t('saveFolder.title')}</div>
          <div className="text-[13px] text-fg-muted mt-1 mb-4">
            {t('saveFolder.description', { format: preferences.file_format.toUpperCase() })}<code className="font-mono text-fg">{t('saveFolder.filenameExample', { format: preferences.file_format })}</code>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex-1 min-w-0 h-[42px] flex items-center px-3.5 rounded-[11px] bg-surface border border-line">
              <span className="text-[12.5px] text-fg-muted break-all font-mono truncate">
                {preferences.save_folder || t('saveFolder.defaultFolder')}
              </span>
            </div>
            <button
              onClick={handleOpenFolder}
              className="shrink-0 inline-flex items-center gap-[7px] px-4 h-[42px] text-[13px] font-medium rounded-[11px] bg-elevated border border-line-strong text-fg hover:bg-fg/[0.04] transition-colors"
            >
              <FolderOpen className="w-3.5 h-3.5" />
              {t('saveFolder.open')}
            </button>
          </div>
        </div>
      )}

      {}
      {!preferences.auto_save && (
        <div
          className="flex items-start gap-[11px] rounded-[14px] px-[18px] py-3.5"
          style={{ background: 'rgba(180,83,9,.1)', border: '1px solid rgba(180,83,9,.25)' }}
        >
          <AlertTriangle className="w-[17px] h-[17px] shrink-0 mt-px text-warn" strokeWidth={1.8} />
          <span className="text-[13px] leading-[1.55] text-warn">
            {t('disabledAlert')}
          </span>
        </div>
      )}

      {}
      <div className="flex items-center justify-between gap-5 bg-elevated border border-line rounded-[14px] py-[18px] px-[22px]">
        <div>
          <div className="text-[15px] font-semibold text-fg">{t('notification.title')}</div>
          <div className="text-[13px] text-fg-muted mt-1">
            {t('notification.description')}
          </div>
        </div>
        <Switch
          checked={showRecordingNotification}
          onCheckedChange={handleNotificationToggle}
        />
      </div>

      {}
      <div className="bg-elevated border border-line rounded-[14px] py-[18px] px-[22px]">
        <h4 className="text-[15px] font-semibold text-fg">{t('devices.title')}</h4>
        <p className="text-[13px] text-fg-muted mt-1 mb-4">
          {t('devices.description')}
        </p>

        <DeviceSelection
          selectedDevices={{
            micDevice: preferences.preferred_mic_device,
            systemDevice: preferences.preferred_system_device
          }}
          onDeviceChange={handleDeviceChange}
          disabled={saving}
        />
      </div>
    </div>
  );
}