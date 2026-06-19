import React from 'react';

interface AudioLevelMeterProps {
  rmsLevel: number;
  peakLevel: number;
  isActive: boolean;
  deviceName: string;
  className?: string;
  size?: 'small' | 'medium' | 'large';
}

export function AudioLevelMeter({
  rmsLevel,
  peakLevel,
  isActive,
  deviceName,
  className = '',
  size = 'medium'
}: AudioLevelMeterProps) {
  const normalizedRms = Math.max(0, Math.min(1, rmsLevel));
  const normalizedPeak = Math.max(0, Math.min(1, peakLevel));

  const logRms = normalizedRms > 0 ? Math.log10(normalizedRms * 9 + 1) : 0;
  const logPeak = normalizedPeak > 0 ? Math.log10(normalizedPeak * 9 + 1) : 0;

  const rmsPercent = Math.round(logRms * 100);
  const peakPercent = Math.round(logPeak * 100);

  const getLevelColor = (level: number) => {
    if (level < 0.3) return 'bg-good';
    if (level < 0.7) return 'bg-warn';
    return 'bg-rec';
  };

  const rmsColor = getLevelColor(logRms);
  const peakColor = getLevelColor(logPeak);

  const sizeClasses = {
    small: {
      container: 'h-2',
      text: 'text-xs',
      meter: 'h-1.5'
    },
    medium: {
      container: 'h-3',
      text: 'text-sm',
      meter: 'h-2'
    },
    large: {
      container: 'h-4',
      text: 'text-base',
      meter: 'h-3'
    }
  };

  const sizes = sizeClasses[size];

  return (
    <div className={`flex items-center space-x-2 ${className}`}>
      {}
      <div className={`w-2 h-2 rounded-full ${
        isActive ? 'bg-good animate-pulse' : 'bg-elevated'
      }`} title={`${deviceName} - ${isActive ? 'Active' : 'Inactive'}`} />

      {}
      <div className={`flex-1 ${sizes.container} relative`}>
        {}
        <div className="w-full h-full bg-surface rounded-sm overflow-hidden">
          {}
          <div
            className={`${sizes.meter} ${rmsColor} transition-all duration-150 ease-out rounded-sm`}
            style={{ width: `${rmsPercent}%` }}
          />

          {}
          {peakPercent > rmsPercent && (
            <div
              className={`absolute top-0 bottom-0 w-0.5 ${peakColor} transition-all duration-75`}
              style={{ left: `${peakPercent}%` }}
            />
          )}
        </div>

        {}
        <div className="absolute inset-0 flex justify-between items-center px-1 pointer-events-none">
          {}
          <div className="w-px h-full bg-elevated opacity-30" style={{ marginLeft: '25%' }} />
          {}
          <div className="w-px h-full bg-elevated opacity-30" style={{ marginLeft: '50%' }} />
          {}
          <div className="w-px h-full bg-elevated opacity-30" style={{ marginLeft: '75%' }} />
        </div>
      </div>

      {}
      <div className={`${sizes.text} text-fg-muted font-mono min-w-[3rem] text-right`}>
        {rmsPercent}%
      </div>
    </div>
  );
}

interface CompactAudioLevelMeterProps {
  rmsLevel: number;
  peakLevel: number;
  isActive: boolean;
  className?: string;
}

export function CompactAudioLevelMeter({
  rmsLevel,
  peakLevel,
  isActive,
  className = ''
}: CompactAudioLevelMeterProps) {
  const normalizedRms = Math.max(0, Math.min(1, rmsLevel));
  const logRms = normalizedRms > 0 ? Math.log10(normalizedRms * 9 + 1) : 0;
  const rmsPercent = Math.round(logRms * 100);

  const getLevelColor = (level: number) => {
    if (level < 0.3) return 'bg-good';
    if (level < 0.7) return 'bg-warn';
    return 'bg-rec';
  };

  return (
    <div className={`flex items-center space-x-1 ${className}`}>
      {}
      <div className={`w-1.5 h-1.5 rounded-full ${
        isActive ? 'bg-good' : 'bg-elevated'
      }`} />

      {}
      <div className="w-8 h-1.5 bg-surface rounded-sm overflow-hidden">
        <div
          className={`h-full ${getLevelColor(logRms)} transition-all duration-150`}
          style={{ width: `${rmsPercent}%` }}
        />
      </div>
    </div>
  );
}