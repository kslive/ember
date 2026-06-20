import React from 'react';
import { motion, AnimatePresence, LayoutGroup } from 'framer-motion';
import { useTranslation } from 'react-i18next';

interface StepDotsProps {
  current: number;
  total: number;
  showLabel?: boolean;
  onStepClick?: (step: number) => void;
  className?: string;
}

const DOT_TRANSITION = { duration: 0.25, ease: [0.22, 1, 0.36, 1] as const };

export function StepDots({
  current,
  total,
  showLabel = false,
  onStepClick,
  className,
}: StepDotsProps) {
  const { t } = useTranslation('onboarding');
  const steps = Array.from({ length: total }, (_, i) => i + 1);

  return (
    <LayoutGroup>
      <div className={`flex items-center gap-2 ${className ?? ''}`}>
        {steps.map((step) => {
          const isActive = step === current;
          const isCompleted = step < current;
          const isClickable = isCompleted && !!onStepClick;

          return (
            <motion.button
              key={step}
              type="button"
              layout
              onClick={() => isClickable && onStepClick?.(step)}
              disabled={!isClickable}
              aria-label={t('stepDotAria', { step })}
              aria-current={isActive ? 'step' : undefined}
              animate={{
                width: isActive ? 18 : 6,
                backgroundColor: isActive
                  ? 'var(--accent)'
                  : isCompleted
                    ? 'var(--accent-text)'
                    : 'var(--border-strong)',
              }}
              transition={DOT_TRANSITION}
              className={`h-1.5 rounded-[3px] ${
                isClickable ? 'cursor-pointer hover:opacity-80' : 'cursor-default'
              }`}
            />
          );
        })}

        {showLabel && (
          <span className="relative ml-1.5 inline-flex font-mono text-[11px] text-fg-faint">
            <AnimatePresence mode="wait" initial={false}>
              <motion.span
                key={current}
                initial={{ opacity: 0, y: 2 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -2 }}
                transition={DOT_TRANSITION}
              >
                {t('stepShort', { current, total })}
              </motion.span>
            </AnimatePresence>
          </span>
        )}
      </div>
    </LayoutGroup>
  );
}
