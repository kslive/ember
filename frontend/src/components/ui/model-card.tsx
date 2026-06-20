'use client';

import * as React from 'react';
import { Download, Check } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { cn } from '@/lib/utils';

export type ModelCardState = 'download' | 'downloading' | 'ready' | 'selected';

export interface ModelCardProps {
  name: string;
  description?: string;
  meta?: string;
  badge?: string;
  state: ModelCardState;
  progress?: number;
  onDownload?: () => void;
  onSelect?: () => void;
  onCardClick?: () => void;
  disabled?: boolean;
  className?: string;
}

export function ModelCard({
  name, description, meta, badge, state, progress = 0,
  onDownload, onSelect, onCardClick, disabled, className,
}: ModelCardProps) {
  const { t } = useTranslation('models');
  const selected = state === 'selected';
  const pct = `${Math.round(progress)}%`;
  const cardClickable = !!onCardClick && state !== 'downloading';

  return (
    <div
      onClick={cardClickable ? onCardClick : undefined}
      className={cn(
        'flex items-start gap-[18px] rounded-[14px] border p-[18px] px-5 w-full box-border transition-colors',
        selected ? 'border-accent bg-accent-weak' : 'border-line bg-elevated',
        cardClickable && 'cursor-pointer hover:bg-fg/[0.04]',
        className,
      )}
    >
      <div className="flex-1 min-w-0 flex flex-col gap-[7px]">
        <div className="flex items-center gap-[9px] flex-wrap">
          <span className="text-[15px] font-semibold tracking-[-0.01em] text-fg">{name}</span>
          {badge && (
            <span className="font-mono text-[9.5px] tracking-[0.08em] uppercase px-2 py-[3px] rounded-[6px] bg-accent-weak text-accent-text">
              {badge}
            </span>
          )}
          {state === 'ready' && (
            <span className="inline-flex items-center gap-1.5 text-[11px] text-good">
              <span className="w-1.5 h-1.5 rounded-full bg-good" />{t('card.ready')}
            </span>
          )}
          {selected && (
            <span className="inline-flex items-center gap-1.5 text-[11px] text-good">
              <span className="w-1.5 h-1.5 rounded-full bg-good" />{t('card.selected')}
            </span>
          )}
        </div>
        {description && (
          <span className="text-[13px] leading-[1.55] text-fg-muted">{description}</span>
        )}
        {meta && (
          <span className="font-mono text-[11.5px] text-fg-faint mt-0.5">{meta}</span>
        )}
      </div>

      <div className="flex-none flex items-center pt-0.5">
        {state === 'download' && (
          <button
            type="button"
            onClick={onDownload}
            disabled={disabled}
            className="inline-flex items-center gap-[7px] h-[34px] px-3.5 rounded-[11px] bg-surface border border-line text-fg text-[13px] font-medium hover:bg-fg/[0.04] disabled:opacity-50 whitespace-nowrap"
          >
            <Download className="w-3.5 h-3.5" />{t('card.download')}
          </button>
        )}
        {state === 'ready' && !onCardClick && (
          <button
            type="button"
            onClick={onSelect}
            disabled={disabled}
            className="h-[34px] px-4 rounded-[11px] bg-transparent border border-line-strong text-fg text-[13px] font-medium hover:bg-fg/[0.04] disabled:opacity-50 whitespace-nowrap"
          >
            {t('card.select')}
          </button>
        )}
        {selected && (
          <div className="w-[26px] h-[26px] rounded-full bg-accent flex items-center justify-center">
            <Check className="w-3.5 h-3.5 text-white" strokeWidth={2.6} />
          </div>
        )}
        {state === 'downloading' && (
          <div className="flex flex-col items-end gap-[7px] w-32">
            <span className="font-mono text-[12px] text-accent-text">{t('card.downloading', { percent: Math.round(progress) })}</span>
            <div className="w-full h-[5px] rounded-[3px] bg-surface overflow-hidden">
              <div className="h-full rounded-[3px] bg-accent transition-[width]" style={{ width: pct }} />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default ModelCard;
