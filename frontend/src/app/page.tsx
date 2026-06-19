'use client';

import { useState, useEffect, useRef } from 'react';
import { motion } from 'framer-motion';
import { listen } from '@tauri-apps/api/event';
import { RecordingControls } from '@/components/RecordingControls';
import { useSidebar } from '@/components/Sidebar/SidebarProvider';
import { usePermissionCheck } from '@/hooks/usePermissionCheck';
import { useRecordingState, RecordingStatus } from '@/contexts/RecordingStateContext';
import { useTranscripts } from '@/contexts/TranscriptContext';
import { useConfig } from '@/contexts/ConfigContext';
import { StatusOverlays } from '@/app/_components/StatusOverlays';
import Analytics from '@/lib/analytics';
import { SettingsModals } from './_components/SettingsModal';
import { TranscriptPanel } from './_components/TranscriptPanel';
import { useModalState } from '@/hooks/useModalState';
import { useRecordingStateSync } from '@/hooks/useRecordingStateSync';
import { useRecordingStart } from '@/hooks/useRecordingStart';
import { useRecordingStop } from '@/hooks/useRecordingStop';
import { useTranscriptRecovery } from '@/hooks/useTranscriptRecovery';
import { TranscriptRecovery } from '@/components/TranscriptRecovery';
import { indexedDBService } from '@/services/indexedDBService';
import { toast } from 'sonner';
import { useRouter } from 'next/navigation';

export default function Home() {
  const [isRecording, setIsRecordingState] = useState(false);
  const IDLE_BAR_HEIGHTS = [
    '10px', '20px', '32px', '14px', '26px',
    '38px', '18px', '30px', '12px', '24px',
    '34px', '16px', '28px', '10px', '22px',
  ];
  const [barHeights, setBarHeights] = useState<string[]>(IDLE_BAR_HEIGHTS);
  const [showRecoveryDialog, setShowRecoveryDialog] = useState(false);

  const { meetingTitle } = useTranscripts();
  const { transcriptModelConfig, selectedDevices } = useConfig();
  const recordingState = useRecordingState();

  const { status, isStopping, isProcessing, isSaving, isFinalizing } = recordingState;

  const { hasMicrophone } = usePermissionCheck();
  const { setIsMeetingActive, isCollapsed: sidebarCollapsed, refetchMeetings } = useSidebar();
  const { modals, messages, showModal, hideModal } = useModalState(transcriptModelConfig);
  const { isRecordingDisabled, setIsRecordingDisabled } = useRecordingStateSync(isRecording, setIsRecordingState, setIsMeetingActive);
  const { handleRecordingStart } = useRecordingStart(isRecording, setIsRecordingState, showModal);

  const { handleRecordingStop, setIsStopping } = useRecordingStop(
    setIsRecordingState,
    setIsRecordingDisabled
  );

  const {
    recoverableMeetings,
    isLoading: isLoadingRecovery,
    isRecovering,
    checkForRecoverableTranscripts,
    recoverMeeting,
    loadMeetingTranscripts,
    deleteRecoverableMeeting
  } = useTranscriptRecovery();

  const router = useRouter();

  useEffect(() => {
    Analytics.trackPageView('home');
  }, []);

  useEffect(() => {
    const performStartupChecks = async () => {
      try {
        if (recordingState.isRecording ||
          status === RecordingStatus.STOPPING ||
          status === RecordingStatus.PROCESSING_TRANSCRIPTS ||
          status === RecordingStatus.SAVING) {
          console.log('Skipping recovery check - recording in progress or processing');
          return;
        }

        try {
          await indexedDBService.deleteOldMeetings(7);
        } catch (error) {
          console.warn('⚠️ Failed to clean up old meetings:', error);
        }

        try {
          await indexedDBService.deleteSavedMeetings(24);
        } catch (error) {
          console.warn('⚠️ Failed to clean up saved meetings:', error);
        }

        await checkForRecoverableTranscripts();
      } catch (error) {
        console.error('Failed to perform startup checks:', error);
      }
    };

    performStartupChecks();
  }, [checkForRecoverableTranscripts, recordingState.isRecording, status]);

  useEffect(() => {
    if (recoverableMeetings.length > 0) {
      const shownThisSession = sessionStorage.getItem('recovery_dialog_shown');
      if (!shownThisSession) {
        setShowRecoveryDialog(true);
        sessionStorage.setItem('recovery_dialog_shown', 'true');
      }
    }
  }, [recoverableMeetings]);

  const handleRecovery = async (meetingId: string) => {
    try {
      const result = await recoverMeeting(meetingId);

      if (result.success) {
        toast.success('Встреча восстановлена!', {
          description: result.audioRecoveryStatus?.status === 'success'
            ? 'Транскрипты и аудио восстановлены'
            : 'Транскрипты восстановлены (аудио недоступно)',
          action: result.meetingId ? {
            label: 'Открыть встречу',
            onClick: () => {
              router.push(`/meeting-details?id=${result.meetingId}`);
            }
          } : undefined,
          duration: 10000,
        });

        await refetchMeetings();

        if (recoverableMeetings.length === 0) {
          sessionStorage.removeItem('recovery_dialog_shown');
        }

        if (result.meetingId) {
          setTimeout(() => {
            router.push(`/meeting-details?id=${result.meetingId}`);
          }, 2000);
        }
      }
    } catch (error) {
      toast.error('Не удалось восстановить встречу', {
        description: error instanceof Error ? error.message : 'Произошла неизвестная ошибка',
      });
      throw error;
    }
  };

  const handleDialogClose = () => {
    setShowRecoveryDialog(false);
    if (recoverableMeetings.length === 0) {
      sessionStorage.removeItem('recovery_dialog_shown');
    }
  };

  const targetLevelRef = useRef(0);
  useEffect(() => {
    if (!isRecording) {
      setBarHeights(IDLE_BAR_HEIGHTS);
      targetLevelRef.current = 0;
      return;
    }

    const unlistenP = listen<{ microphone?: { rms?: number; peak?: number }; system?: { rms?: number; peak?: number } }>(
      'audio-levels',
      (event) => {
        const mic = event.payload?.microphone;
        const sys = event.payload?.system;
        const m = mic?.peak ?? mic?.rms ?? 0;
        const s = sys?.peak ?? sys?.rms ?? 0;
        const level = Math.max(m, s);
        targetLevelRef.current = Math.min(1, Math.pow(level, 0.55) * 2.4);
      },
    );

    const BAR_WEIGHTS = [0.45, 0.6, 0.85, 0.55, 0.75, 1.0, 0.6, 0.8, 0.4, 0.7, 0.9, 0.5, 0.8, 0.4, 0.65];
    let raf = 0;
    const cur = new Array<number>(BAR_WEIGHTS.length).fill(0);
    const tick = () => {
      const t = targetLevelRef.current;
      const px = (v: number) => `${Math.max(10, Math.min(38, 10 + v * 28))}px`;
      const next = cur.map((c, i) => {
        const target = t * BAR_WEIGHTS[i];
        const v = c + (target - c) * 0.35;
        cur[i] = v;
        return px(v);
      });
      setBarHeights(next);
      raf = window.requestAnimationFrame(tick);
    };
    raf = window.requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      unlistenP.then((u) => u()).catch(() => {});
    };
  }, [isRecording]);

  const isProcessingStop = status === RecordingStatus.PROCESSING_TRANSCRIPTS || isProcessing;

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, ease: 'easeOut' }}
      className="flex flex-col h-screen bg-canvas"
    >
      {}
      <SettingsModals
        modals={modals}
        messages={messages}
        onClose={hideModal}
      />

      {}
      <TranscriptRecovery
        isOpen={showRecoveryDialog}
        onClose={handleDialogClose}
        recoverableMeetings={recoverableMeetings}
        onRecover={handleRecovery}
        onDelete={deleteRecoverableMeeting}
        onLoadPreview={loadMeetingTranscripts}
      />
      <div className="flex flex-1 overflow-hidden">
        {}
        {(() => {
          const controlsVisible =
            (hasMicrophone || isRecording) &&
            status !== RecordingStatus.PROCESSING_TRANSCRIPTS &&
            status !== RecordingStatus.SAVING;

          const sharedControlProps = {
            isRecording: recordingState.isRecording,
            onRecordingStop: (callApi = true) => handleRecordingStop(callApi),
            onRecordingStart: handleRecordingStart,
            onTranscriptReceived: () => { },
            onStopInitiated: () => setIsStopping(true),
            barHeights,
            onTranscriptionError: (message: string) => {
              showModal('errorAlert', message);
            },
            isRecordingDisabled,
            isParentProcessing: isProcessingStop,
            selectedDevices,
            meetingName: meetingTitle,
          };

          const recordingControls = controlsVisible ? (
            <RecordingControls {...sharedControlProps} variant="transport" />
          ) : null;

          const recordingPauseControl = controlsVisible ? (
            <RecordingControls {...sharedControlProps} variant="pause" />
          ) : null;

          return (
            <TranscriptPanel
              isProcessingStop={isProcessingStop}
              isStopping={isStopping}
              showModal={showModal}
              recordingControls={recordingControls}
              recordingPauseControl={recordingPauseControl}
            />
          );
        })()}

        {}
        <StatusOverlays
          isProcessing={!isFinalizing && status === RecordingStatus.PROCESSING_TRANSCRIPTS && !recordingState.isRecording}
          isSaving={!isFinalizing && status === RecordingStatus.SAVING}
          sidebarCollapsed={sidebarCollapsed}
        />
      </div>
    </motion.div>
  );
}
