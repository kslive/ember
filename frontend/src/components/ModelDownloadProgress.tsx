import React from 'react';
import { ModelStatus } from '../lib/whisper';

interface ModelDownloadProgressProps {
  status: ModelStatus;
  modelName: string;
  onCancel?: () => void;
}

export function ModelDownloadProgress({ status, modelName, onCancel }: ModelDownloadProgressProps) {
  if (typeof status !== 'object' || !('Downloading' in status)) {
    return null;
  }

  const progress = status.Downloading;
  const isCompleted = progress >= 100;

  return (
    <div className="rounded-[14px] border border-accent bg-accent-weak p-4">
      <div className="mb-2 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-accent-weak border-t-accent" />
          <span className="font-mono text-[12px] text-accent-text">
            {isCompleted ? 'Завершение…' : `Скачивание ${modelName}`}
          </span>
        </div>
        {onCancel && !isCompleted && (
          <button
            onClick={onCancel}
            className="font-mono text-[11px] text-fg-faint transition-colors hover:text-rec"
          >
            Отменить
          </button>
        )}
      </div>

      <div className="relative">
        <div className="h-[5px] w-full overflow-hidden rounded-[3px] bg-surface">
          <div
            className="h-full rounded-[3px] bg-accent transition-[width] duration-300 ease-out"
            style={{ width: `${Math.min(progress, 100)}%` }}
          />
        </div>
        <div className="mt-1 flex justify-between font-mono text-[11px] text-accent-text">
          <span>{Math.round(progress)}%</span>
          {!isCompleted && <span className="animate-shimmer">Скачивание…</span>}
        </div>
      </div>

      {isCompleted && (
        <div className="mt-2 flex items-center gap-1.5 text-[12px] text-good">
          <span className="h-1.5 w-1.5 rounded-full bg-good" />
          Загрузка завершена, загружаем модель…
        </div>
      )}
    </div>
  );
}

interface ProgressRingProps {
  progress: number;
  size?: number;
  strokeWidth?: number;
}

export function ProgressRing({ progress, size = 40, strokeWidth = 3 }: ProgressRingProps) {
  const radius = (size - strokeWidth) / 2;
  const circumference = radius * 2 * Math.PI;
  const strokeDasharray = circumference;
  const strokeDashoffset = circumference - (progress / 100) * circumference;

  return (
    <div className="relative inline-flex items-center justify-center">
      <svg width={size} height={size} className="-rotate-90 transform">
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke="var(--surface)"
          strokeWidth={strokeWidth}
          fill="transparent"
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke="var(--accent)"
          strokeWidth={strokeWidth}
          strokeDasharray={strokeDasharray}
          strokeDashoffset={strokeDashoffset}
          strokeLinecap="round"
          fill="transparent"
          className="transition-all duration-300 ease-in-out"
        />
      </svg>
      <span className="absolute font-mono text-[11px] text-accent-text">
        {Math.round(progress)}%
      </span>
    </div>
  );
}

interface DownloadSummaryProps {
  totalModels: number;
  downloadedModels: number;
  totalSizeMb: number;
}

export function DownloadSummary({ totalModels, downloadedModels, totalSizeMb }: DownloadSummaryProps) {
  const formatSize = (mb: number) => {
    if (mb >= 1000) return `${(mb / 1000).toFixed(1)} ГБ`;
    return `${mb} МБ`;
  };

  return (
    <div className="rounded-[14px] bg-surface p-3.5">
      <div className="flex items-center justify-between font-mono text-[11.5px] text-fg-muted">
        <span>{downloadedModels} из {totalModels} моделей готовы</span>
        <span>{formatSize(totalSizeMb)} всего</span>
      </div>
      {downloadedModels > 0 && (
        <div className="mt-1.5 flex items-center gap-1.5 text-[12px] text-good">
          <span className="h-1.5 w-1.5 rounded-full bg-good" />
          Модели работают локально — для транскрипции интернет не нужен
        </div>
      )}
    </div>
  );
}
