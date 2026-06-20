import React from 'react';
import { Lock, Zap, FileText, ArrowRight } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { useOnboarding } from '@/contexts/OnboardingContext';
import { StepDots } from '../shared';

export function WelcomeStep() {
  const { goNext } = useOnboarding();
  const { t } = useTranslation('onboarding');

  const features = [
    {
      icon: Lock,
      title: t('welcome.features.local.title'),
      caption: t('welcome.features.local.caption'),
    },
    {
      icon: Zap,
      title: t('welcome.features.offline.title'),
      caption: t('welcome.features.offline.caption'),
    },
    {
      icon: FileText,
      title: t('welcome.features.export.title'),
      caption: t('welcome.features.export.caption'),
    },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-hidden bg-canvas px-8 text-fg">
      <div className="flex w-full max-w-[440px] flex-col items-center gap-3.5">
        {}
        <div
          className="mb-2 flex h-[60px] w-[60px] items-center justify-center rounded-[18px]"
          style={{
            background:
              'radial-gradient(circle at 36% 30%,#fdba74,#f97316 58%,#ea580c)',
            boxShadow: '0 12px 36px rgba(249,115,22,.4)',
          }}
        >
          <svg
            width="30"
            height="30"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#fff"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <rect x="9" y="3" width="6" height="11" rx="3" />
            <path d="M5 11a7 7 0 0 0 14 0" />
            <line x1="12" y1="18" x2="12" y2="21" />
          </svg>
        </div>

        <h1 className="m-0 text-center text-[32px] font-semibold tracking-[-0.025em] text-fg animate-fade-in-up">
          {t('welcome.title')}
        </h1>
        <p className="m-0 mb-3.5 text-center text-[15px] leading-[1.6] text-fg-muted">
          {t('welcome.description')}
        </p>

        {}
        <div className="mb-[18px] flex w-full flex-col gap-3.5">
          {features.map((feature) => {
            const Icon = feature.icon;
            return (
              <div key={feature.title} className="flex items-center gap-[13px]">
                <div className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-[11px] bg-surface text-accent-text">
                  <Icon className="h-[17px] w-[17px]" strokeWidth={1.8} />
                </div>
                <div>
                  <div className="text-[14px] font-medium text-fg">{feature.title}</div>
                  <div className="text-[12.5px] text-fg-faint">{feature.caption}</div>
                </div>
              </div>
            );
          })}
        </div>

        {}
        <button
          type="button"
          onClick={goNext}
          style={{ boxShadow: '0 8px 24px rgba(249,115,22,.32)' }}
          className="inline-flex h-[46px] w-full items-center justify-center gap-[9px] rounded-md bg-accent text-[15px] font-medium text-white transition-opacity hover:opacity-90"
        >
          {t('welcome.cta')}
          <ArrowRight className="h-4 w-4" strokeWidth={2} />
        </button>

        {}
        <StepDots current={1} total={3} showLabel className="mt-2" />
      </div>
    </div>
  );
}
