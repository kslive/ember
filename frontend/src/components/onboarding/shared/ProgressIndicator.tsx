import React from 'react';
import { StepDots } from './StepDots';

interface ProgressIndicatorProps {
  current: number;
  total: number;
  onStepClick?: (step: number) => void;
}

export function ProgressIndicator({ current, total, onStepClick }: ProgressIndicatorProps) {
  return (
    <div className="mb-8 flex items-center justify-center">
      <StepDots current={current} total={total} onStepClick={onStepClick} />
    </div>
  );
}
