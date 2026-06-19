import React, { useState, useEffect } from "react";
import { getVersion } from '@tauri-apps/api/app';


export function About() {
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
                    Локальные заметки и саммари встреч — ничего не уходит с вашего Mac.
                </p>
            </div>

            <div className="space-y-3">
                <h2 className="font-mono text-[10px] uppercase tracking-[0.1em] text-fg-faint">Возможности</h2>
                <div className="grid grid-cols-2 gap-2.5">
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">Приватность</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">Все данные и обработка остаются локально. Без облака.</p>
                    </div>
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">Локальные модели</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">Whisper и встроенные LLM, никаких внешних API.</p>
                    </div>
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">Без подписок</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">Бесплатно, без оплат за минуты.</p>
                    </div>
                    <div className="bg-surface rounded-[11px] p-3.5">
                        <h3 className="font-semibold text-[13px] text-fg mb-1">Любые встречи</h3>
                        <p className="text-[12px] text-fg-muted leading-relaxed">Meet, Zoom, Teams — онлайн и офлайн.</p>
                    </div>
                </div>
            </div>
        </div>
    )
}
