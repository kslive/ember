'use client';

import { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
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
import { useTranslation } from 'react-i18next';

export default function Home() {
  const { t } = useTranslation('recording');
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
        toast.success(t('recovery.restoredTitle'), {
          description: result.audioRecoveryStatus?.status === 'success'
            ? t('recovery.restoredWithAudio')
            : t('recovery.restoredWithoutAudio'),
          action: result.meetingId ? {
            label: t('recovery.openMeeting'),
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
      toast.error(t('recovery.failedTitle'), {
        description: error instanceof Error ? error.message : t('recovery.unknownError'),
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

  useEffect(() => {
    if (!recordingState.isRecording) {
      setBarHeights(IDLE_BAR_HEIGHTS);
      return;
    }

    const BARS = 15;
    const cur = new Array<number>(BARS).fill(0.15);
    const px = (v: number) => `${Math.round(Math.max(6, Math.min(40, 6 + v * 34)))}px`;

    let raf = 0;
    let stopped = false;
    let stream: MediaStream | null = null;
    let audioCtx: AudioContext | null = null;
    let analyser: AnalyserNode | null = null;
    let freq: Uint8Array<ArrayBuffer> | null = null;

    (async () => {
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        if (stopped) { stream.getTracks().forEach((tr) => tr.stop()); return; }
        const Ctx = window.AudioContext || (window as any).webkitAudioContext;
        audioCtx = new Ctx();
        await audioCtx.resume().catch(() => {});
        const node = audioCtx.createAnalyser();
        node.fftSize = 64;
        node.smoothingTimeConstant = 0.75;
        audioCtx.createMediaStreamSource(stream).connect(node);
        freq = new Uint8Array(node.frequencyBinCount);
        analyser = node;
      } catch (e) {
        console.warn('[rec-anim] mic visualizer unavailable, using synthetic animation:', e);
      }
    })();

    const start = performance.now();
    const tick = () => {
      let next: string[];
      if (analyser && freq) {
        analyser.getByteFrequencyData(freq);
        next = cur.map((c, i) => {
          const target = (freq![i + 1] ?? 0) / 255;
          const v = c + (target - c) * 0.45;
          cur[i] = v;
          return px(v);
        });
      } else {
        const tms = (performance.now() - start) / 1000;
        next = cur.map((c, i) => {
          const target = 0.3 + 0.45 * (0.5 + 0.5 * Math.sin(tms * (4 + (i % 5) * 0.7) + i * 0.9));
          const v = c + (target - c) * 0.3;
          cur[i] = v;
          return px(v);
        });
      }
      setBarHeights(next);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => {
      stopped = true;
      cancelAnimationFrame(raf);
      if (stream) stream.getTracks().forEach((tr) => tr.stop());
      if (audioCtx) audioCtx.close().catch(() => {});
    };
  }, [recordingState.isRecording]);

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
