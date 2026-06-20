'use client';

import { motion } from 'framer-motion';
import { useRecordingState } from '@/contexts/RecordingStateContext';
import { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';

interface RecordingStatusBarProps {
  isPaused?: boolean;
}

export const RecordingStatusBar: React.FC<RecordingStatusBarProps> = ({ isPaused = false }) => {
  const { t } = useTranslation('recording');
  const { activeDuration, isRecording } = useRecordingState();

  const [displaySeconds, setDisplaySeconds] = useState(0);

  useEffect(() => {
    if (activeDuration !== null) {
      setDisplaySeconds(Math.floor(activeDuration));
    }
  }, [activeDuration]);

  const formatDuration = (seconds: number): string => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: -10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ duration: 0.2 }}
      className={`inline-flex items-center h-[34px] px-[14px] rounded-full ${isPaused ? 'bg-[color-mix(in_srgb,var(--warn)_12%,transparent)] text-warn' : 'bg-[color-mix(in_srgb,var(--rec)_12%,transparent)] text-rec'}`}
    >
      <div className={`w-[9px] h-[9px] rounded-full mr-[9px] ${isPaused ? 'bg-warn' : 'bg-rec animate-rec-pulse'}`} />
      <span className="font-sans text-[13px] font-medium">
        {isPaused ? t('statusBar.paused') : t('statusBar.recording')}
      </span>
      <span className="font-mono text-[13px] tabular-nums ml-[9px]">
        {formatDuration(displaySeconds)}
      </span>
    </motion.div>
  );
};
