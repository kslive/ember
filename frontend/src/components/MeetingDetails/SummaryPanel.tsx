"use client";

import React from 'react';
import { Summary, Transcript } from '@/types';
import { SummaryObsidianCard } from './SummaryObsidianCard';
import { ModelConfig } from '@/components/ModelSettingsModal';

const SparkleIcon = ({ size = 14 }: { size?: number }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8z" />
  </svg>
);

interface SummaryPanelProps {
  meeting: { id: string; title: string; created_at: string };
  meetingTitle: string;
  aiSummary: Summary | null;
  summaryStatus: 'idle' | 'processing' | 'summarizing' | 'regenerating' | 'completed' | 'error';
  transcripts: Transcript[];
  modelConfig: ModelConfig;
  onGenerateSummary: (customPrompt: string) => Promise<void>;
  customPrompt: string;
  onPromptChange?: (value: string) => void;
}

export function SummaryPanel({
  meeting,
  meetingTitle,
  aiSummary,
  summaryStatus,
  transcripts,
  modelConfig,
  onGenerateSummary,
  customPrompt,
  onPromptChange,
}: SummaryPanelProps) {
  const isSummaryLoading =
    summaryStatus === 'processing' ||
    summaryStatus === 'summarizing' ||
    summaryStatus === 'regenerating';

  const modelLabel = modelConfig?.model || modelConfig?.provider || '';

  return (
    <div className="flex-1 min-w-0 flex flex-col bg-canvas">
      {}
      <div className="px-[30px] pt-6 pb-[18px] flex items-center gap-2 text-accent">
        <SparkleIcon />
        <span className="font-mono text-[10.5px] tracking-[0.12em] uppercase text-fg-faint">
          Саммари
        </span>
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto custom-scrollbar">
        {isSummaryLoading ? (
          <SummaryGeneratingState modelLabel={modelLabel} />
        ) : (
          <div className="px-[30px] pb-6 max-w-[820px] mx-auto">
            <SummaryObsidianCard
              meeting={{ id: meeting.id, title: meetingTitle, created_at: meeting.created_at }}
              aiSummary={aiSummary}
              customPrompt={customPrompt}
              onPromptChange={onPromptChange}
              onGenerate={onGenerateSummary}
              isGenerating={isSummaryLoading}
              canGenerate={transcripts.length > 0}
            />
          </div>
        )}
      </div>
    </div>
  );
}

function SummaryGeneratingState({ modelLabel }: { modelLabel: string }) {
  return (
    <div className="px-[30px] py-6 max-w-[820px] mx-auto flex flex-col">
      {}
      <div className="flex items-center gap-[10px] mb-[20px]">
        <div className="w-[15px] h-[15px] rounded-full border-2 border-accent/30 border-t-accent animate-spin shrink-0" />
        <span className="text-[15px] font-semibold text-fg">Создаём саммари</span>
        {modelLabel && (
          <span className="font-mono text-[11.5px] text-fg-faint ml-auto">{modelLabel}</span>
        )}
      </div>

      {}
      <div className="flex flex-col gap-[13px] mb-[24px]">
        <div className="flex items-center gap-[10px] text-[13.5px] text-fg-muted">
          <svg
            width="15"
            height="15"
            viewBox="0 0 24 24"
            fill="none"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="stroke-good stroke-[2.4] shrink-0"
          >
            <path d="M5 12l5 5L20 6" />
          </svg>
          Анализ транскрипта
        </div>
        <div className="flex items-center gap-[10px] text-[13.5px] font-medium text-accent-text">
          <div className="w-[15px] h-[15px] rounded-full border-2 border-accent/30 border-t-accent animate-spin shrink-0" />
          Выделение решений
        </div>
        <div className="flex items-center gap-[10px] text-[13.5px] text-fg-faint">
          <div className="w-[15px] h-[15px] rounded-full border-[1.5px] border-line-strong shrink-0" />
          Формирование задач
        </div>
      </div>

      {}
      <div className="h-[5px] rounded-[3px] bg-surface overflow-hidden mb-[26px]">
        <div className="h-full rounded-[3px] bg-accent" style={{ width: '60%' }} />
      </div>

      {}
      <div className="flex flex-col gap-[11px]">
        <div className="h-[13px] w-[40%] rounded-[5px] bg-surface animate-shimmer" />
        <div className="h-[12px] w-[96%] rounded-[5px] bg-surface animate-shimmer" />
        <div className="h-[12px] w-[88%] rounded-[5px] bg-surface animate-shimmer" />
        <div className="h-[12px] w-[92%] rounded-[5px] bg-surface animate-shimmer" />
      </div>
    </div>
  );
}
