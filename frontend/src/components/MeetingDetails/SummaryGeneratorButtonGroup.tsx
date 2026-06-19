"use client";

import { ModelConfig, ModelSettingsModal } from '@/components/ModelSettingsModal';
import {
  Dialog,
  DialogContent,
  DialogTrigger,
  DialogTitle,
} from "@/components/ui/dialog"
import { VisuallyHidden } from "@/components/ui/visually-hidden"
import { Button } from '@/components/ui/button';
import { ButtonGroup } from '@/components/ui/button-group';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Settings, Loader2, Square } from 'lucide-react';
import Analytics from '@/lib/analytics';
import { invoke } from '@tauri-apps/api/core';
import { toast } from 'sonner';
import { useState, useEffect, useRef } from 'react';
import { isOllamaNotInstalledError } from '@/lib/utils';
import { BuiltInModelInfo } from '@/lib/builtin-ai';

interface SummaryGeneratorButtonGroupProps {
  modelConfig: ModelConfig;
  setModelConfig: (config: ModelConfig | ((prev: ModelConfig) => ModelConfig)) => void;
  onSaveModelConfig: (config?: ModelConfig) => Promise<void>;
  onGenerateSummary: (customPrompt: string) => Promise<void>;
  onStopGeneration: () => void;
  customPrompt: string;
  summaryStatus: 'idle' | 'processing' | 'summarizing' | 'regenerating' | 'completed' | 'error';
  availableTemplates: Array<{ id: string, name: string, description: string }>;
  selectedTemplate: string;
  onTemplateSelect: (templateId: string, templateName: string) => void;
  hasTranscripts?: boolean;
  hasSummary?: boolean;
  isModelConfigLoading?: boolean;
  onOpenModelSettings?: (openFn: () => void) => void;
}

export function SummaryGeneratorButtonGroup({
  modelConfig,
  setModelConfig,
  onSaveModelConfig,
  onGenerateSummary,
  onStopGeneration,
  customPrompt,
  summaryStatus,
  availableTemplates,
  selectedTemplate,
  onTemplateSelect,
  hasTranscripts = true,
  hasSummary = false,
  isModelConfigLoading = false,
  onOpenModelSettings
}: SummaryGeneratorButtonGroupProps) {
  const [isCheckingModels, setIsCheckingModels] = useState(false);
  const [settingsDialogOpen, setSettingsDialogOpen] = useState(false);

  useEffect(() => {
    if (onOpenModelSettings) {
      const openDialog = () => {
        console.log('📱 Opening model settings dialog via callback');
        setSettingsDialogOpen(true);
      };

      onOpenModelSettings(openDialog);
    }
  }, [onOpenModelSettings]);

  if (!hasTranscripts) {
    return null;
  }

  const checkBuiltInAIModelsAndGenerate = async () => {
    setIsCheckingModels(true);
    try {
      const selectedModel = modelConfig.model;

      if (!selectedModel) {
        toast.error('No built-in AI model selected', {
          description: 'Please select a model in settings',
          duration: 5000,
        });
        setSettingsDialogOpen(true);
        return;
      }

      const isReady = await invoke<boolean>('builtin_ai_is_model_ready', {
        modelName: selectedModel,
        refresh: true,
      });

      if (isReady) {
        onGenerateSummary(customPrompt);
        return;
      }

      const modelInfo = await invoke<BuiltInModelInfo | null>('builtin_ai_get_model_info', {
        modelName: selectedModel,
      });

      if (!modelInfo) {
        toast.error('Модель не найдена', {
          description: `Не удалось найти информацию о модели: ${selectedModel}`,
          duration: 5000,
        });
        setSettingsDialogOpen(true);
        return;
      }

      const status = modelInfo.status;

      if (status.type === 'downloading') {
        toast.info('Модель скачивается', {
          description: `${selectedModel} загружается (${status.progress}%). Дождитесь завершения загрузки.`,
          duration: 5000,
        });
        return;
      }

      if (status.type === 'not_downloaded') {
        toast.error('Модель не скачана', {
          description: `${selectedModel} нужно скачать перед использованием. Открываю настройки модели…`,
          duration: 5000,
        });
        setSettingsDialogOpen(true);
        return;
      }

      if (status.type === 'corrupted') {
        toast.error('Файл модели повреждён', {
          description: `Файл модели ${selectedModel} повреждён. Удалите и скачайте заново.`,
          duration: 7000,
        });
        setSettingsDialogOpen(true);
        return;
      }

      if (status.type === 'error') {
        toast.error('Ошибка модели', {
          description: status.Error || 'Произошла ошибка с моделью',
          duration: 5000,
        });
        setSettingsDialogOpen(true);
        return;
      }

      toast.error('Модель недоступна', {
        description: 'Выбранная модель не готова к использованию',
        duration: 5000,
      });
      setSettingsDialogOpen(true);

    } catch (error) {
      console.error('Error checking built-in AI models:', error);
      toast.error('Не удалось проверить статус модели', {
        description: error instanceof Error ? error.message : String(error),
        duration: 5000,
      });
    } finally {
      setIsCheckingModels(false);
    }
  };

  const checkOllamaModelsAndGenerate = async () => {
    if (modelConfig.provider === 'builtin-ai') {
      await checkBuiltInAIModelsAndGenerate();
      return;
    }

    if (modelConfig.provider !== 'ollama') {
      onGenerateSummary(customPrompt);
      return;
    }

    setIsCheckingModels(true);
    try {
      const endpoint = modelConfig.ollamaEndpoint || null;
      const models = await invoke('get_ollama_models', { endpoint }) as any[];

      if (!models || models.length === 0) {
        toast.error(
          'No Ollama models found. Please download gemma2:2b from Model Settings.',
          { duration: 5000 }
        );
        setSettingsDialogOpen(true);
        return;
      }

      onGenerateSummary(customPrompt);
    } catch (error) {
      console.error('Error checking Ollama models:', error);
      const errorMessage = error instanceof Error ? error.message : String(error);

      if (isOllamaNotInstalledError(errorMessage)) {
        toast.error(
          'Ollama is not installed',
          {
            description: 'Please download and install Ollama to use local models.',
            duration: 7000,
            action: {
              label: 'Download',
              onClick: () => invoke('open_external_url', { url: 'https://ollama.com/download' })
            }
          }
        );
      } else {
        toast.error(
          'Failed to check Ollama models. Please check if Ollama is running and download a model.',
          { duration: 5000 }
        );
      }
      setSettingsDialogOpen(true);
    } finally {
      setIsCheckingModels(false);
    }
  };

  const isGenerating = summaryStatus === 'processing' || summaryStatus === 'summarizing' || summaryStatus === 'regenerating';

  const generateLabel = hasSummary ? 'Перегенерировать' : 'Сгенерировать';

  return (
    <div className="flex items-center gap-2">
      <Dialog open={settingsDialogOpen} onOpenChange={setSettingsDialogOpen}>
        <DialogTrigger asChild>
          <button
            type="button"
            className="inline-flex items-center gap-[7px] h-[34px] px-[13px] rounded-md text-[13px] text-fg-muted bg-elevated border border-line hover:bg-fg/[0.04] transition-colors"
            title="Модель"
          >
            <Settings size={14} />
            <span className="hidden lg:inline">Модель</span>
          </button>
        </DialogTrigger>
        <DialogContent aria-describedby={undefined}>
          <VisuallyHidden>
            <DialogTitle>Настройки модели</DialogTitle>
          </VisuallyHidden>
          <ModelSettingsModal
            onSave={async (config) => {
              await onSaveModelConfig(config);
              setSettingsDialogOpen(false);
            }}
            modelConfig={modelConfig}
            setModelConfig={setModelConfig}
            skipInitialFetch={true}
          />
        </DialogContent>
      </Dialog>

      {isGenerating ? (
        <button
          type="button"
          onClick={() => {
            Analytics.trackButtonClick('stop_summary_generation', 'meeting_details');
            onStopGeneration();
          }}
          className="inline-flex items-center gap-[7px] h-[34px] px-[14px] rounded-md text-[13px] bg-rec/10 hover:bg-rec/15 text-rec border border-rec/20 transition-colors"
          title="Остановить генерацию"
        >
          <Square size={14} fill="currentColor" />
          <span className="hidden lg:inline">Остановить</span>
        </button>
      ) : (
        <button
          type="button"
          onClick={() => {
            Analytics.trackButtonClick('generate_summary', 'meeting_details');
            checkOllamaModelsAndGenerate();
          }}
          disabled={isCheckingModels || isModelConfigLoading}
          className="inline-flex items-center gap-[7px] h-[34px] px-[14px] rounded-md text-[13px] font-medium bg-accent hover:opacity-90 text-white shadow-glow transition-opacity disabled:opacity-50"
          title={isModelConfigLoading ? 'Загрузка модели…' : isCheckingModels ? 'Проверка модели…' : `${generateLabel} саммари`}
        >
          {isCheckingModels || isModelConfigLoading ? (
            <>
              <Loader2 className="animate-spin" size={14} />
              <span className="hidden lg:inline">Обработка…</span>
            </>
          ) : (
            <>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8z" />
              </svg>
              <span className="hidden lg:inline">{generateLabel}</span>
            </>
          )}
        </button>
      )}
    </div>
  );
}
