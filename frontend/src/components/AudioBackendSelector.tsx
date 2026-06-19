import React, { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Info } from 'lucide-react';

export interface BackendInfo {
  id: string;
  name: string;
  description: string;
}

interface AudioBackendSelectorProps {
  currentBackend?: string;
  onBackendChange?: (backend: string) => void;
  disabled?: boolean;
}

export function AudioBackendSelector({
  currentBackend: propBackend,
  onBackendChange,
  disabled = false,
}: AudioBackendSelectorProps) {
  const [backends, setBackends] = useState<BackendInfo[]>([]);
  const [currentBackend, setCurrentBackend] = useState<string>('coreaudio');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showTooltip, setShowTooltip] = useState(false);

  useEffect(() => {
    const loadBackends = async () => {
      try {
        setLoading(true);
        setError(null);

        const backendInfo = await invoke<BackendInfo[]>('get_audio_backend_info');
        setBackends(backendInfo);

        if (!propBackend) {
          const current = await invoke<string>('get_current_audio_backend');
          setCurrentBackend(current);
        } else {
          setCurrentBackend(propBackend);
        }
      } catch (err) {
        console.error('Failed to load audio backends:', err);
        setError('Не удалось загрузить доступные способы захвата');
      } finally {
        setLoading(false);
      }
    };

    loadBackends();
  }, [propBackend]);

  const handleBackendChange = async (backendId: string) => {
    try {
      setError(null);
      await invoke('set_audio_backend', { backend: backendId });
      setCurrentBackend(backendId);

      if (onBackendChange) {
        onBackendChange(backendId);
      }

      console.log(`Audio backend changed to: ${backendId}`);
    } catch (err) {
      console.error('Failed to set audio backend:', err);
      setError('Не удалось сменить способ захвата. Попробуйте ещё раз.');
    }
  };

  if (loading) {
    return (
      <div className="animate-pulse">
        <div className="h-3 bg-surface rounded w-32 mb-2"></div>
        <div className="h-[42px] bg-surface rounded-[11px]"></div>
      </div>
    );
  }

  if (backends.length <= 1) {
    return null;
  }

  return (
    <div className="space-y-2.5">
      <div className="flex items-center gap-2">
        <label className="font-mono text-[10px] uppercase tracking-[0.1em] text-fg-faint">
          Захват системного звука
        </label>
        <div className="relative">
          <button
            type="button"
            onMouseEnter={() => setShowTooltip(true)}
            onMouseLeave={() => setShowTooltip(false)}
            className="text-fg-faint hover:text-fg-muted transition-colors"
          >
            <Info className="h-3.5 w-3.5" />
          </button>
          {showTooltip && (
            <div className="absolute z-10 left-6 top-0 w-64 p-3 text-xs bg-elevated border border-line-strong text-fg rounded-[11px] shadow-ember">
              <p className="font-semibold mb-1">Способы захвата звука:</p>
              <ul className="space-y-1">
                {backends.map((backend) => (
                  <li key={backend.id}>
                    <span className="font-medium">{backend.name}:</span> {backend.description}
                  </li>
                ))}
              </ul>
              <p className="mt-2 text-fg-faint">
                Попробуйте разные способы, чтобы найти лучший для вашей системы.
              </p>
            </div>
          )}
        </div>
      </div>

      {error && (
        <div
          className="flex items-start gap-3 rounded-[11px] px-3.5 py-3 text-[12px] text-warn"
          style={{ background: 'rgba(180,83,9,.1)', border: '1px solid rgba(180,83,9,.25)' }}
        >
          {error}
        </div>
      )}

      <div className="space-y-2">
        {backends.map((backend) => {
          const isCoreAudio = backend.id === 'screencapturekit';
          const isDisabled = disabled || isCoreAudio;

          return (
            <label
              key={backend.id}
              className={`flex items-start p-3.5 border rounded-[11px] transition-all ${
                currentBackend === backend.id
                  ? 'border-accent bg-accent-weak'
                  : 'border-line hover:border-line-strong bg-elevated'
              } ${isDisabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}`}
            >
              <input
                type="radio"
                name="audioBackend"
                value={backend.id}
                checked={currentBackend === backend.id}
                onChange={() => handleBackendChange(backend.id)}
                disabled={isDisabled}
                className="mt-1 h-4 w-4 accent-accent focus:ring-accent border-line"
              />
              <div className="ml-3 flex-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-[13.5px] font-medium text-fg">
                    {backend.name}
                  </span>
                  {currentBackend === backend.id && (
                    <span className="font-mono text-[9.5px] uppercase tracking-wide font-medium text-accent-text bg-accent-weak px-2 py-0.5 rounded-md">
                      Включён
                    </span>
                  )}
                  {isCoreAudio && (
                    <span className="font-mono text-[9.5px] uppercase tracking-wide font-medium text-fg-muted bg-surface px-2 py-0.5 rounded-md">
                      Выключен
                    </span>
                  )}
                </div>
                <p className="mt-1 text-[12px] text-fg-muted">{backend.description}</p>
              </div>
            </label>
          );
        })}
      </div>

      <div className="text-[11px] text-fg-muted space-y-1">
        <p>• Выбор способа влияет только на захват системного звука</p>
        <p>• Микрофон всегда использует способ по умолчанию</p>
        <p>• Изменения применяются к новым сессиям записи</p>
      </div>
    </div>
  );
}