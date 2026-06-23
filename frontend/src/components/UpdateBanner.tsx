'use client';

import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Download, X, Loader2 } from 'lucide-react';
import { useUpdater } from '@/hooks/useUpdater';

export function UpdateBanner() {
  const { t } = useTranslation('common');
  const { updateInfo, isInstalling, installUpdate } = useUpdater();
  const [dismissed, setDismissed] = useState(false);

  if (!updateInfo?.available || dismissed) return null;

  return (
    <div className="flex items-start gap-3 mx-9 mt-4 rounded-[12px] border border-line bg-elevated px-4 py-3">
      <Download className="w-4 h-4 mt-0.5 shrink-0 text-accent" />
      <div className="min-w-0 flex-1">
        <p className="text-[13.5px] font-medium text-fg">
          {t('updates.newVersionAvailable', { version: updateInfo.version })}
        </p>
        {updateInfo.notes && (
          <p className="mt-1 text-[12.5px] text-fg-muted line-clamp-2 whitespace-pre-line">
            {updateInfo.notes}
          </p>
        )}
      </div>
      <button
        onClick={installUpdate}
        disabled={isInstalling}
        className="shrink-0 inline-flex items-center gap-[6px] px-3.5 h-[34px] text-[12.5px] font-medium rounded-[9px] bg-accent text-white hover:opacity-90 disabled:opacity-60 transition-colors"
      >
        {isInstalling ? (
          <>
            <Loader2 className="w-3.5 h-3.5 animate-spin" />
            {t('updates.installing')}
          </>
        ) : (
          t('updates.installNow')
        )}
      </button>
      <button
        onClick={() => setDismissed(true)}
        aria-label={t('close')}
        className="shrink-0 inline-flex items-center justify-center w-[34px] h-[34px] rounded-[9px] text-fg-muted hover:bg-fg/[0.05] transition-colors"
      >
        <X className="w-4 h-4" />
      </button>
    </div>
  );
}
