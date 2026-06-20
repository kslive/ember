"use client";
import { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import { useTranslation } from 'react-i18next';
import { Summary, SummaryResponse, Transcript } from '@/types';
import { useSidebar } from '@/components/Sidebar/SidebarProvider';
import Analytics from '@/lib/analytics';
import { invoke } from '@tauri-apps/api/core';
import { toast } from 'sonner';
import { TranscriptPanel } from '@/components/MeetingDetails/TranscriptPanel';
import { SummaryPanel } from '@/components/MeetingDetails/SummaryPanel';
import { SummaryGeneratorButtonGroup } from '@/components/MeetingDetails/SummaryGeneratorButtonGroup';
import { EditableTitle } from '@/components/EditableTitle';
import { ModelConfig } from '@/components/ModelSettingsModal';
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';
import { formatDate } from '@/lib/datetime';
import { useLocale } from '@/contexts/LocaleContext';
import type { Locale } from '@/lib/preferences';
import type { TFunction } from 'i18next';

function formatMeetingMeta(
  createdAt: string,
  locale: Locale,
  t: TFunction,
  durationSeconds?: number,
  participantCount?: number
): string {
  const parts: string[] = [];

  if (createdAt) {
    const formatted = formatDate(createdAt, locale);
    if (formatted) parts.push(formatted);
  }

  if (durationSeconds !== undefined && durationSeconds > 0) {
    const minutes = Math.max(1, Math.round(durationSeconds / 60));
    parts.push(t('meta.minutes', { count: minutes }));
  }

  if (participantCount !== undefined && participantCount > 0) {
    parts.push(t('meta.participants', { count: participantCount }));
  }

  return parts.join(' · ');
}

function displayMeetingTitle(title: string, t: TFunction): string {
  const raw = (title || '').trim();
  const isAuto =
    raw === '' ||
    /^meeting\b/i.test(raw) ||
    /^(запись|recording|录音)[\s_-]*\d/i.test(raw) ||
    /^(\+\s*)?new call$/i.test(raw) ||
    raw === 'intro-call';
  return isAuto ? t('untitled') : raw;
}

function deriveMeetingDuration(transcripts: Transcript[]): number | undefined {
  let max = 0;
  for (const t of transcripts) {
    const end = t.audio_end_time ?? t.audio_start_time;
    if (typeof end === 'number' && end > max) max = end;
  }
  return max > 0 ? max : undefined;
}

const CopyIcon = ({ size = 14 }: { size?: number }) => (
  <svg
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.8"
    strokeLinecap="round"
    strokeLinejoin="round"
    aria-hidden="true"
  >
    <rect x="9" y="9" width="11" height="11" rx="2" />
    <path d="M5 15V5a2 2 0 0 1 2-2h8" />
  </svg>
);

import { useMeetingData } from '@/hooks/meeting-details/useMeetingData';
import { useSummaryGeneration } from '@/hooks/meeting-details/useSummaryGeneration';
import { useTemplates } from '@/hooks/meeting-details/useTemplates';
import { useCopyOperations } from '@/hooks/meeting-details/useCopyOperations';
import { useMeetingOperations } from '@/hooks/meeting-details/useMeetingOperations';
import { useConfig } from '@/contexts/ConfigContext';

export default function PageContent({
  meeting,
  summaryData,
  shouldAutoGenerate = false,
  onAutoGenerateComplete,
  onMeetingUpdated,
  onRefetchTranscripts,
  segments,
  hasMore,
  isLoadingMore,
  totalCount,
  loadedCount,
  onLoadMore,
}: {
  meeting: any;
  summaryData: Summary | null;
  shouldAutoGenerate?: boolean;
  onAutoGenerateComplete?: () => void;
  onMeetingUpdated?: () => Promise<void>;
  onRefetchTranscripts?: () => Promise<void>;
  segments?: any[];
  hasMore?: boolean;
  isLoadingMore?: boolean;
  totalCount?: number;
  loadedCount?: number;
  onLoadMore?: () => void;
}) {
  console.log('📄 PAGE CONTENT: Initializing with data:', {
    meetingId: meeting.id,
    summaryDataKeys: summaryData ? Object.keys(summaryData) : null,
    transcriptsCount: meeting.transcripts?.length
  });

  const { t } = useTranslation('meeting');
  const { locale } = useLocale();

  const [customPrompt, setCustomPrompt] = useState<string>('');
  const [isRecording] = useState(false);
  const [summaryResponse] = useState<SummaryResponse | null>(null);

  const openModelSettingsRef = useRef<(() => void) | null>(null);

  const { serverAddress } = useSidebar();

  const { modelConfig, setModelConfig } = useConfig();

  const meetingData = useMeetingData({ meeting, summaryData, onMeetingUpdated });
  const templates = useTemplates();

  const handleRegisterModalOpen = (openFn: () => void) => {
    console.log('📝 Registering modal open function in PageContent');
    openModelSettingsRef.current = openFn;
  };

  const handleOpenModelSettings = () => {
    console.log('🔔 Opening model settings from PageContent');
    if (openModelSettingsRef.current) {
      openModelSettingsRef.current();
    } else {
      console.warn('⚠️ Modal open function not yet registered');
    }
  };

  const handleSaveModelConfig = async (config?: ModelConfig) => {
    if (!config) return;
    try {
      await invoke('api_save_model_config', {
        provider: config.provider,
        model: config.model,
        whisperModel: config.whisperModel,
        apiKey: config.apiKey ?? null,
        ollamaEndpoint: config.ollamaEndpoint ?? null,
      });

      const { emit } = await import('@tauri-apps/api/event');
      await emit('model-config-updated', config);

      toast.success(t('toasts.modelConfigSaved'));
    } catch (error) {
      console.error('Failed to save model config:', error);
      toast.error(t('toasts.modelConfigSaveFailed'));
    }
  };

  const summaryGeneration = useSummaryGeneration({
    meeting,
    transcripts: meetingData.transcripts,
    modelConfig: modelConfig,
    isModelConfigLoading: false,
    selectedTemplate: templates.selectedTemplate,
    onMeetingUpdated,
    updateMeetingTitle: meetingData.updateMeetingTitle,
    setAiSummary: meetingData.setAiSummary,
    onOpenModelSettings: handleOpenModelSettings,
  });

  const copyOperations = useCopyOperations({
    meeting,
    transcripts: meetingData.transcripts,
    meetingTitle: meetingData.meetingTitle,
    aiSummary: meetingData.aiSummary,
  });

  const meetingOperations = useMeetingOperations({
    meeting,
  });

  useEffect(() => {
    Analytics.trackPageView('meeting_details');
  }, []);

  useEffect(() => {
    let cancelled = false;

    const autoGenerate = async () => {
      if (shouldAutoGenerate && meetingData.transcripts.length > 0 && !cancelled) {
        const status = String(summaryGeneration.summaryStatus || 'idle');
        if (status !== 'idle' || meetingData.aiSummary) {
          console.log('🤖 Auto-summary skipped — already running or present');
          if (onAutoGenerateComplete && !cancelled) onAutoGenerateComplete();
          return;
        }
        console.log(`🤖 Auto-generating summary with ${modelConfig.provider}/${modelConfig.model}...`);
        await summaryGeneration.handleGenerateSummary('');

        if (onAutoGenerateComplete && !cancelled) {
          onAutoGenerateComplete();
        }
      }
    };

    autoGenerate();

    return () => {
      cancelled = true;
    };
  }, [shouldAutoGenerate, meeting.id]);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, ease: 'easeOut' }}
      className="flex flex-col h-full bg-canvas overflow-hidden"
    >
      {}
      <header className="flex-none px-[30px] pt-[22px] pb-[18px] border-b border-line flex items-start justify-between gap-5">
        <div className="flex flex-col gap-1.5 min-w-0">
          <EditableTitle
            title={displayMeetingTitle(meetingData.meetingTitle, t)}
            isEditing={meetingData.isEditingTitle}
            onStartEditing={() => meetingData.setIsEditingTitle(true)}
            onFinishEditing={() => meetingData.setIsEditingTitle(false)}
            onChange={meetingData.handleTitleChange}
          />
          <span className="font-mono text-[12px] text-fg-faint">
            {formatMeetingMeta(
              meeting.created_at,
              locale,
              t,
              deriveMeetingDuration(meetingData.transcripts),
              undefined
            )}
          </span>
        </div>
        <div className="shrink-0 flex items-center gap-2 pt-0.5">
          <button
            type="button"
            onClick={copyOperations.handleCopySummary}
            className="inline-flex items-center gap-[7px] h-[34px] px-[13px] rounded-md text-[13px] text-fg-muted bg-elevated border border-line hover:bg-fg/[0.04] transition-colors"
            title={t('actions.copyTitle')}
          >
            <CopyIcon />
            <span className="hidden lg:inline">{t('actions.copy')}</span>
          </button>
          <SummaryGeneratorButtonGroup
            modelConfig={modelConfig}
            setModelConfig={setModelConfig}
            onSaveModelConfig={handleSaveModelConfig}
            onGenerateSummary={summaryGeneration.handleGenerateSummary}
            onStopGeneration={summaryGeneration.handleStopGeneration}
            customPrompt={customPrompt}
            summaryStatus={summaryGeneration.summaryStatus}
            availableTemplates={templates.availableTemplates}
            selectedTemplate={templates.selectedTemplate}
            onTemplateSelect={templates.handleTemplateSelection}
            hasTranscripts={meetingData.transcripts.length > 0}
            hasSummary={!!meetingData.aiSummary}
            isModelConfigLoading={false}
            onOpenModelSettings={handleRegisterModalOpen}
          />
        </div>
      </header>

      <div className="flex flex-1 min-h-0 overflow-hidden">
        <PanelGroup direction="horizontal" autoSaveId="ember-meeting" className="h-full">
          <Panel defaultSize={55} minSize={35} className="flex min-w-0">
            <TranscriptPanel
              transcripts={meetingData.transcripts}
              customPrompt={customPrompt}
              onPromptChange={setCustomPrompt}
              onCopyTranscript={copyOperations.handleCopyTranscript}
              onOpenMeetingFolder={meetingOperations.handleOpenMeetingFolder}
              isRecording={isRecording}
              disableAutoScroll={true}
              usePagination={true}
              segments={segments}
              hasMore={hasMore}
              isLoadingMore={isLoadingMore}
              totalCount={totalCount}
              loadedCount={loadedCount}
              onLoadMore={onLoadMore}
              meetingId={meeting.id}
              meetingFolderPath={meeting.folder_path}
              onRefetchTranscripts={onRefetchTranscripts}
            />
          </Panel>
          <PanelResizeHandle className="w-px bg-line data-[resize-handle-state=hover]:bg-accent/50 data-[resize-handle-state=drag]:bg-accent transition-colors relative before:absolute before:inset-y-0 before:-left-1 before:-right-1 before:content-[''] cursor-col-resize" />
          <Panel defaultSize={45} minSize={28} className="flex min-w-0">
            <SummaryPanel
              meeting={meeting}
              meetingTitle={meetingData.meetingTitle}
              aiSummary={meetingData.aiSummary}
              summaryStatus={summaryGeneration.summaryStatus}
              transcripts={meetingData.transcripts}
              modelConfig={modelConfig}
              onGenerateSummary={summaryGeneration.handleGenerateSummary}
              customPrompt={customPrompt}
              onPromptChange={setCustomPrompt}
            />
          </Panel>
        </PanelGroup>
      </div>
    </motion.div>
  );
}
