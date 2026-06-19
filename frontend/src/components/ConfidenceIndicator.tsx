'use client';

interface ConfidenceIndicatorProps {
  confidence: number;
  showIndicator?: boolean;
}

export const ConfidenceIndicator: React.FC<ConfidenceIndicatorProps> = ({
  confidence,
  showIndicator = true,
}) => {
  if (!showIndicator) {
    return null;
  }

  const getColorClass = (conf: number): string => {
    if (conf >= 0.8) return 'bg-green-500';
    if (conf >= 0.7) return 'bg-yellow-500';
    if (conf >= 0.4) return 'bg-orange-500';
    return 'bg-red-500';
  };

  const getConfidenceLabel = (conf: number): string => {
    if (conf >= 0.8) return 'High confidence';
    if (conf >= 0.7) return 'Good confidence';
    if (conf >= 0.4) return 'Medium confidence';
    return 'Low confidence';
  };

  const confidencePercent = (confidence * 100).toFixed(0);
  const colorClass = getColorClass(confidence);
  const label = getConfidenceLabel(confidence);

  return (
    <div
      className="flex items-center gap-1"
      title={`${confidencePercent}% confidence - ${label}`}
      aria-label={`Transcription confidence: ${confidencePercent}%`}
    >
      <div
        className={`w-2 h-2 rounded-full ${colorClass} transition-colors duration-200`}
        role="status"
      />
    </div>
  );
};
