import { VirtualizedTranscriptView } from '@/components/VirtualizedTranscriptView';
import { PermissionWarning } from '@/components/PermissionWarning';
import { GlobeIcon } from 'lucide-react';
import { useTranscripts } from '@/contexts/TranscriptContext';
import { useConfig } from '@/contexts/ConfigContext';
import { useRecordingState } from '@/contexts/RecordingStateContext';
import { RecordingStatusBar } from '@/components/RecordingStatusBar';
import { usePermissionCheck } from '@/hooks/usePermissionCheck';
import { ModalType } from '@/hooks/useModalState';
import { useIsLinux } from '@/hooks/usePlatform';
import { TranscriptLabel } from '@/components/transcript/TranscriptLabel';
import { useMemo, type ReactNode } from 'react';

interface TranscriptPanelProps {
  isProcessingStop: boolean;
  isStopping: boolean;
  showModal: (name: ModalType, message?: string) => void;
  recordingControls?: ReactNode;
  recordingPauseControl?: ReactNode;
}

export function TranscriptPanel({
  isProcessingStop,
  isStopping,
  showModal,
  recordingControls,
  recordingPauseControl,
}: TranscriptPanelProps) {
  const { transcripts, transcriptContainerRef, copyTranscript } = useTranscripts();
  const { transcriptModelConfig } = useConfig();
  const { isRecording, isPaused, isFinalizing } = useRecordingState();
  const { checkPermissions, isChecking, hasSystemAudio, hasMicrophone } = usePermissionCheck();
  const isLinux = useIsLinux();

  const segments = useMemo(() =>
    transcripts.map(t => ({
      id: t.id,
      timestamp: t.audio_start_time ?? 0,
      endTime: t.audio_end_time,
      text: t.text,
      confidence: t.confidence,
    })),
    [transcripts]
  );

  const languageChip = transcriptModelConfig.provider === 'localWhisper' ? (
    <button
      type="button"
      onClick={() => showModal('languageSettings')}
      className="titlebar-no-drag inline-flex items-center gap-[7px] px-[14px] h-[34px] rounded-[9px] text-[13px] text-fg-muted hover:bg-surface border border-line transition-colors"
      title="Язык"
    >
      <GlobeIcon size={14} />
      <span>Русский</span>
    </button>
  ) : null;

  if (isFinalizing) {
    return (
      <main ref={transcriptContainerRef} className="w-full bg-canvas flex flex-col min-w-0 overflow-hidden">
        {}
        <div className="flex-1 flex flex-col items-center justify-center gap-[14px]">
          <div className="w-[18px] h-[18px] border-2 border-accent/30 border-t-accent rounded-full animate-spin" />
          <span className="text-[15px] text-fg-muted">Завершаем расшифровку…</span>
        </div>
      </main>
    );
  }

  return (
    <main ref={transcriptContainerRef} className="w-full bg-canvas flex flex-col min-w-0 overflow-hidden">
      {isRecording ? (
        <>
          {}
          <div className="titlebar-drag h-[60px] flex items-center justify-between px-[26px] border-b border-line">
            <RecordingStatusBar isPaused={isPaused} />
            <div className="titlebar-no-drag flex items-center gap-2">
              {}
              {recordingPauseControl}
              {languageChip}
            </div>
          </div>

          {}
          <div className="flex-1 min-h-0 flex flex-col px-[40px] py-[28px]">
            <TranscriptLabel className="mb-[22px] select-none">
              Транскрипт · в реальном времени
            </TranscriptLabel>
            <div className="flex-1 min-h-0">
              <VirtualizedTranscriptView
                segments={segments}
                isRecording={isRecording}
                isPaused={isPaused}
                isProcessing={isProcessingStop}
                isStopping={isStopping}
                enableStreaming={isRecording}
                showConfidence={true}
              />
            </div>
          </div>

          {}
          <div className="border-t border-line h-[104px] flex items-center justify-center gap-[24px]">
            {recordingControls}
          </div>
        </>
      ) : (
        <>
          {}
          <div className="titlebar-drag h-[60px] flex items-center justify-end px-[26px]">
            <div className="titlebar-no-drag">{languageChip}</div>
          </div>

          {}
          {!isChecking && !isLinux && (
            <div className="flex justify-center px-4 pt-4">
              <PermissionWarning
                hasMicrophone={hasMicrophone}
                hasSystemAudio={hasSystemAudio}
                onRecheck={checkPermissions}
                isRechecking={isChecking}
              />
            </div>
          )}

          {segments.length > 0 ? (
            <div className="flex-1 min-h-0 flex flex-col px-[40px] py-[28px]">
              <div className="flex items-center justify-between mb-[22px]">
                <TranscriptLabel className="select-none">
                  Транскрипт
                </TranscriptLabel>
                {transcripts?.length > 0 && (
                  <button
                    type="button"
                    onClick={copyTranscript}
                    className="titlebar-no-drag inline-flex items-center gap-[7px] px-3.5 h-[34px] rounded-[9px] text-[13px] text-fg-muted hover:bg-surface border border-line transition-colors"
                    title="Скопировать"
                  >
                    Копировать
                  </button>
                )}
              </div>
              <div className="flex-1 min-h-0">
                <VirtualizedTranscriptView
                  segments={segments}
                  isRecording={isRecording}
                  isPaused={isPaused}
                  isProcessing={isProcessingStop}
                  isStopping={isStopping}
                  enableStreaming={false}
                  showConfidence={true}
                />
              </div>
            </div>
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center gap-[14px] pb-[40px]">
              <h1 className="text-[38px] font-light tracking-[-0.02em] text-fg">
                Готов к записи
              </h1>
              <p className="text-[15px] text-fg-muted">
                Начните запись — транскрипт появится здесь в реальном времени
              </p>
              {}
              {recordingControls}
            </div>
          )}
        </>
      )}
    </main>
  );
}
