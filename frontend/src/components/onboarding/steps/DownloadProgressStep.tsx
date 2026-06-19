import React, { useState } from 'react';
import { Check } from 'lucide-react';
import { OnboardingContainer } from '../OnboardingContainer';
import { StepDots } from '../shared';
import { useOnboarding } from '@/contexts/OnboardingContext';
import { ModelManager } from '@/components/WhisperModelManager';
import { BuiltInModelManager } from '@/components/BuiltInModelManager';

export function DownloadProgressStep() {
  const {
    goNext,
    goPrevious,
    selectedSummaryModel,
    setSelectedSummaryModel,
    parakeetDownloaded,
    setParakeetDownloaded,
    summaryModelDownloaded,
    setSummaryModelDownloaded,
  } = useOnboarding();

  const [selectedWhisper, setSelectedWhisper] = useState<string>('large-v3-q5_0');
  const [isCompleting, setIsCompleting] = useState(false);

  const canContinue = parakeetDownloaded && summaryModelDownloaded;

  const handleContinue = async () => {
    if (!canContinue) return;
    setIsCompleting(true);
    try {
      goNext();
    } finally {
      setIsCompleting(false);
    }
  };

  const footer = (
    <>
      <button
        type="button"
        onClick={goPrevious}
        className="inline-flex h-[42px] items-center rounded-md border border-line bg-transparent px-[18px] text-[14px] font-medium text-fg-muted transition-colors hover:bg-fg/[0.04]"
      >
        Назад
      </button>

      <StepDots current={3} total={3} />

      <button
        type="button"
        onClick={handleContinue}
        disabled={!canContinue || isCompleting}
        className="inline-flex h-[42px] items-center gap-2 rounded-md bg-accent px-[22px] text-[14px] font-medium text-white transition-opacity hover:opacity-90 disabled:opacity-50"
      >
        {isCompleting ? 'Готовлю…' : 'Готово'}
        {!isCompleting && <Check className="h-[15px] w-[15px]" strokeWidth={2.4} />}
      </button>
    </>
  );

  return (
    <OnboardingContainer
      variant="step"
      stepLabel="Шаг 3 из 3"
      title="Загрузка моделей"
      description="Выберите модель Whisper для распознавания речи и локальную ИИ-модель для конспектов, затем дождитесь загрузки."
      step={3}
      footer={footer}
    >
      <div className="space-y-7">
        <section className="space-y-3">
          <div className="font-mono text-[11px] uppercase tracking-[0.1em] text-accent-text">
            Модель распознавания речи (Whisper)
          </div>
          <ModelManager
            selectedModel={selectedWhisper}
            onModelSelect={(name) => {
              setSelectedWhisper(name);
              setParakeetDownloaded(true);
            }}
            autoSave={true}
          />
        </section>

        <section className="space-y-3">
          <div className="font-mono text-[11px] uppercase tracking-[0.1em] text-accent-text">
            Модель для конспектов (локальный ИИ)
          </div>
          <p className="text-[13px] leading-[1.55] text-fg-muted">
            Выберите и скачайте любую модель. Qwen2.5 7B заметно умнее Gemma и
            лучше знает русский — рекомендуется, если хватает памяти (~6 ГБ).
          </p>
          <BuiltInModelManager
            selectedModel={selectedSummaryModel || ''}
            onModelSelect={(name) => {
              setSelectedSummaryModel(name);
              setSummaryModelDownloaded(true);
            }}
          />
        </section>
      </div>
    </OnboardingContainer>
  );
}
