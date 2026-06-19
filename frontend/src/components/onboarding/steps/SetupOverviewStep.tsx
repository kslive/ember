import React, { useEffect, useState } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { Info, Mic, Sparkles, ArrowRight } from 'lucide-react';
import { OnboardingContainer } from '../OnboardingContainer';
import { useOnboarding } from '@/contexts/OnboardingContext';
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

export function SetupOverviewStep() {
  const { goNext } = useOnboarding();
  const [recommendedModel, setRecommendedModel] = useState<string>('gemma3:1b');
  const [modelSize, setModelSize] = useState<string>('~806 MB');
  const [isMac, setIsMac] = useState(false);

  useEffect(() => {
    const fetchRecommendedModel = async () => {
      try {
        const model = await invoke<string>('builtin_ai_get_recommended_model');
        setRecommendedModel(model);
        setModelSize(model === 'gemma3:4b' ? '~2.5 GB' : '~806 MB');
      } catch (error) {
        console.error('Failed to get recommended model:', error);
      }
    };
    fetchRecommendedModel();

    const checkPlatform = async () => {
      try {
        const { platform } = await import('@tauri-apps/plugin-os');
        setIsMac(platform() === 'macos');
      } catch (e) {
        setIsMac(navigator.userAgent.includes('Mac'));
      }
    };
    checkPlatform();
  }, []);

  const steps = [
    {
      number: 1,
      type: 'transcription' as const,
      icon: Mic,
      title: 'Движок распознавания речи',
      caption: 'Whisper расшифровывает аудио в текст — локально',
    },
    {
      number: 2,
      type: 'summarization' as const,
      icon: Sparkles,
      title: 'ИИ для конспектов',
      caption: 'Превращает транскрипт в структурированное саммари',
    },
  ];

  const handleContinue = () => {
    goNext();
  };

  return (
    <OnboardingContainer
      title="Подготовка"
      description="Для работы Ember нужно загрузить ИИ-модели для распознавания речи и создания конспектов."
      step={2}
      totalSteps={isMac ? 4 : 3}
    >
      <div className="flex w-full flex-col items-center gap-7">
        {}
        <div className="w-full space-y-3">
          {steps.map((step) => {
            const Icon = step.icon;
            return (
              <div
                key={step.number}
                className="flex items-start gap-3.5 rounded-[14px] border border-line bg-elevated p-[18px]"
              >
                <div className="flex h-[38px] w-[38px] flex-none items-center justify-center rounded-[11px] bg-surface text-accent-text">
                  <Icon className="h-[17px] w-[17px]" strokeWidth={1.8} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-[10.5px] uppercase tracking-[0.1em] text-fg-faint">
                      Шаг {step.number}
                    </span>
                    {step.type === 'summarization' && (
                      <TooltipProvider>
                        <Tooltip>
                          <TooltipTrigger asChild>
                            <button className="text-fg-faint transition-colors hover:text-fg-muted">
                              <Info className="h-3.5 w-3.5" />
                            </button>
                          </TooltipTrigger>
                          <TooltipContent className="max-w-xs text-sm">
                            Также можно выбрать внешних ИИ-провайдеров (OpenAI, Claude, Ollama) в настройках.
                          </TooltipContent>
                        </Tooltip>
                      </TooltipProvider>
                    )}
                  </div>
                  <div className="mt-1 text-[14px] font-medium text-fg">{step.title}</div>
                  <div className="text-[12.5px] text-fg-faint">{step.caption}</div>
                </div>
              </div>
            );
          })}
        </div>

        {}
        <div className="w-full space-y-3.5">
          <button
            type="button"
            onClick={handleContinue}
            style={{ boxShadow: '0 8px 24px rgba(249,115,22,.32)' }}
            className="inline-flex h-[46px] w-full items-center justify-center gap-[9px] rounded-md bg-accent text-[15px] font-medium text-white transition-opacity hover:opacity-90"
          >
            Начать
            <ArrowRight className="h-4 w-4" strokeWidth={2} />
          </button>
        </div>
      </div>
    </OnboardingContainer>
  );
}
