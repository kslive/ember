import React from 'react';
import { cn } from '@/lib/utils';
import { ProgressIndicator } from './shared/ProgressIndicator';
import { useOnboarding } from '@/contexts/OnboardingContext';
import type { OnboardingContainerProps } from '@/types/onboarding';

interface ExtraProps {
  stepLabel?: string;
  variant?: 'centered' | 'step';
  footer?: React.ReactNode;
}

export function OnboardingContainer({
  title,
  description,
  children,
  step,
  totalSteps = 3,
  stepOffset = 0,
  hideProgress = false,
  className,
  stepLabel,
  variant = 'centered',
  footer,
}: OnboardingContainerProps & ExtraProps) {
  const { goToStep } = useOnboarding();

  const handleStepClick = (s: number) => {
    goToStep(s + stepOffset);
  };

  if (variant === 'step') {
    return (
      <div className="fixed inset-0 z-50 flex flex-col overflow-hidden bg-canvas text-fg">
        {}
        <div className="flex-none px-20 pt-[54px] pb-6">
          <div className="mx-auto w-full max-w-[660px]">
            {stepLabel && (
              <span className="font-mono text-[11px] uppercase tracking-[0.1em] text-accent-text">
                {stepLabel}
              </span>
            )}
            <h1 className="mt-3 mb-2 text-[28px] font-semibold tracking-[-0.02em] text-fg animate-fade-in-up">
              {title}
            </h1>
            {description && (
              <p className="mb-0 text-[14.5px] leading-[1.6] text-fg-muted">{description}</p>
            )}
          </div>
        </div>

        {}
        <div className="flex-1 min-h-0 overflow-y-auto px-20 pt-1 pb-8 [mask-image:linear-gradient(to_bottom,transparent,#000_22px)]">
          <div className={cn('mx-auto w-full max-w-[660px] space-y-3', className)}>{children}</div>
        </div>

        {footer && (
          <div className="flex-none border-t border-line">
            <div className="flex w-full items-center justify-between px-20 py-[18px]">
              {footer}
            </div>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-hidden bg-canvas text-fg">
      <div className={cn('flex w-full max-w-md flex-col items-center px-8 py-10', className)}>
        <div className="w-full text-center">
          <h1 className="text-[28px] font-semibold tracking-[-0.02em] text-fg animate-fade-in-up">
            {title}
          </h1>
          {description && (
            <p className="mx-auto mt-3 max-w-md text-[14.5px] leading-[1.6] text-fg-muted animate-fade-in-up delay-75">
              {description}
            </p>
          )}
        </div>

        <div className="mt-7 w-full">{children}</div>

        {step && !hideProgress && (
          <div className="mt-2">
            <ProgressIndicator current={step} total={totalSteps} onStepClick={handleStepClick} />
          </div>
        )}
      </div>
    </div>
  );
}
