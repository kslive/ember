import React from 'react';
import { Check, ArrowRight } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { OnboardingContainer } from '../OnboardingContainer';
import { useOnboarding } from '@/contexts/OnboardingContext';
import { useLocale } from '@/contexts/LocaleContext';
import type { Locale } from '@/lib/preferences';

const OPTIONS: { value: Locale; name: string; native: string }[] = [
  { value: 'en', name: 'English', native: 'English' },
  { value: 'zh', name: '中文', native: '简体中文' },
  { value: 'ru', name: 'Русский', native: 'Русский' },
];

export function LanguageSelectionStep() {
  const { t } = useTranslation('onboarding');
  const { locale, setLocale } = useLocale();
  const { goNext } = useOnboarding();

  return (
    <OnboardingContainer title={t('language.title')} description={t('language.subtitle')} step={1} hideProgress className="max-w-md">
      <div className="flex w-full flex-col gap-3">
        {OPTIONS.map((opt) => {
          const isActive = locale === opt.value;
          return (
            <button
              key={opt.value}
              type="button"
              onClick={() => setLocale(opt.value)}
              aria-pressed={isActive}
              className={`flex items-center justify-between gap-3 rounded-[14px] border p-[18px] text-left transition-colors ${
                isActive
                  ? 'border-accent bg-accent-weak'
                  : 'border-line bg-elevated hover:bg-fg/[0.04]'
              }`}
            >
              <div className="min-w-0">
                <div className="text-[16px] font-semibold text-fg">{opt.name}</div>
                {opt.native !== opt.name && (
                  <div className="text-[12.5px] text-fg-faint">{opt.native}</div>
                )}
              </div>
              <span
                className={`flex h-[22px] w-[22px] flex-none items-center justify-center rounded-full transition-colors ${
                  isActive ? 'bg-accent text-white' : 'border border-line-strong text-transparent'
                }`}
              >
                <Check className="h-3.5 w-3.5" strokeWidth={3} />
              </span>
            </button>
          );
        })}
      </div>

      <button
        type="button"
        onClick={goNext}
        style={{ boxShadow: '0 8px 24px rgba(249,115,22,.32)' }}
        className="mt-6 inline-flex h-[46px] w-full items-center justify-center gap-[9px] rounded-md bg-accent text-[15px] font-medium text-white transition-opacity hover:opacity-90"
      >
        {t('common:continue')}
        <ArrowRight className="h-4 w-4" strokeWidth={2} />
      </button>
    </OnboardingContainer>
  );
}
