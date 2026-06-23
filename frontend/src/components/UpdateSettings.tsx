'use client';

import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Download, RefreshCw, Loader2 } from 'lucide-react';
import { Switch } from './ui/switch';
import { load } from '@tauri-apps/plugin-store';
import { useUpdater } from '@/hooks/useUpdater';

const PREF_FILE = 'preferences.json';
const PREF_KEY_AUTO_CHECK = 'auto_check_updates';

export function UpdateSettings() {
  const { t } = useTranslation('common');
  const { updateInfo, isChecking, isInstalling, checkForUpdates, installUpdate } = useUpdater();
  const [autoCheck, setAutoCheck] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const store = await load(PREF_FILE);
        const v = (await store.get(PREF_KEY_AUTO_CHECK)) as boolean | null;
        setAutoCheck(v ?? true);
      } catch (e) {
        console.error('Failed to load auto-check pref:', e);
      }
    })();
  }, []);

  const handleAutoCheckChange = async (value: boolean) => {
    setAutoCheck(value);
    try {
      const store = await load(PREF_FILE);
      await store.set(PREF_KEY_AUTO_CHECK, value);
      await store.save();
    } catch (e) {
      console.error('Failed to save auto-check pref:', e);
    }
  };

  const available = updateInfo?.available ?? false;

  return (
    <div className="space-y-4">
      <div className="bg-elevated rounded-[14px] border border-line py-5 px-[22px]">
        <div className="flex items-center justify-between gap-5">
          <div className="min-w-0">
            <h3 className="text-[15px] font-semibold text-fg">
              {available
                ? t('updates.versionAvailable', { version: updateInfo?.version })
                : t('updates.upToDate')}
            </h3>
            {available && updateInfo?.notes && (
              <p className="mt-1 text-[13px] text-fg-muted line-clamp-3 whitespace-pre-line">
                {updateInfo.notes}
              </p>
            )}
          </div>
          {available ? (
            <button
              onClick={installUpdate}
              disabled={isInstalling}
              className="shrink-0 inline-flex items-center gap-[7px] px-4 h-[42px] text-[13px] font-medium rounded-[11px] bg-accent text-white hover:opacity-90 disabled:opacity-60 transition-colors"
            >
              {isInstalling ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  {t('updates.installing')}
                </>
              ) : (
                <>
                  <Download className="w-3.5 h-3.5" />
                  {t('updates.installNow')}
                </>
              )}
            </button>
          ) : (
            <button
              onClick={() => checkForUpdates(true)}
              disabled={isChecking}
              className="shrink-0 inline-flex items-center gap-[7px] px-4 h-[42px] text-[13px] font-medium rounded-[11px] bg-elevated border border-line-strong text-fg hover:bg-fg/[0.04] disabled:opacity-60 transition-colors"
            >
              {isChecking ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  {t('updates.checking')}
                </>
              ) : (
                <>
                  <RefreshCw className="w-3.5 h-3.5" />
                  {t('updates.checkNow')}
                </>
              )}
            </button>
          )}
        </div>
      </div>

      <div className="bg-elevated rounded-[14px] border border-line py-5 px-[22px]">
        <div className="flex items-center justify-between gap-5">
          <div>
            <h3 className="text-[15px] font-semibold text-fg">{t('updates.autoCheck')}</h3>
          </div>
          <Switch checked={autoCheck} onCheckedChange={handleAutoCheckChange} />
        </div>
      </div>
    </div>
  );
}
