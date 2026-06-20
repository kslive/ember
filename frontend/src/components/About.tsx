import React, { useState, useEffect } from "react";
import { getVersion } from '@tauri-apps/api/app';
import { useTranslation } from 'react-i18next';


export function About() {
    const { t } = useTranslation('about');
    const [currentVersion, setCurrentVersion] = useState<string>('0.3.0');

    useEffect(() => {
        getVersion().then(setCurrentVersion).catch(console.error);
    }, []);

    return (
        <div className="p-4 space-y-6 h-[80vh] overflow-y-auto">
            <div className="text-center">
                <div className="inline-flex items-center gap-2.5 mb-2">
                    <span
                        className="w-[9px] h-[9px] rounded-full bg-accent"
                        style={{ boxShadow: '0 0 10px rgba(249,115,22,.7)' }}
                    />
                    <span className="text-[17px] font-medium tracking-[-0.01em] text-fg">Ember</span>
                </div>
                <div className="font-mono text-[11px] text-fg-faint">v{currentVersion}</div>
                <p className="text-[13px] text-fg-muted mt-2 leading-relaxed max-w-xs mx-auto">
                    {t('description')}
                </p>
            </div>

            <div className="space-y-3">
                <h2 className="font-mono text-[10px] uppercase tracking-[0.1em] text-fg-faint">{t('features')}</h2>
                <div className="grid grid-cols-2 gap-2.5">
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">{t('tiles.privacy.title')}</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">{t('tiles.privacy.desc')}</p>
                    </div>
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">{t('tiles.localModels.title')}</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">{t('tiles.localModels.desc')}</p>
                    </div>
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">{t('tiles.noSubscriptions.title')}</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">{t('tiles.noSubscriptions.desc')}</p>
                    </div>
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">{t('tiles.anyMeetings.title')}</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">{t('tiles.anyMeetings.desc')}</p>
                    </div>
                </div>
            </div>
        </div>
    )
}
