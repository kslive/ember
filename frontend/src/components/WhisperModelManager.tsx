import React, { useState, useEffect, useRef } from 'react';
import { listen } from '@tauri-apps/api/event';
import { invoke } from '@tauri-apps/api/core';
import { motion } from 'framer-motion';
import { toast } from 'sonner';
import {
  ModelInfo,
  ModelStatus,
  getModelIcon,
  formatFileSize,
  getModelTagline,
  WhisperAPI
} from '../lib/whisper';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { ModelCard as EmberModelCard, type ModelCardState } from '@/components/ui/model-card';
import { Trash2, X } from 'lucide-react';

interface ModelManagerProps {
  selectedModel?: string;
  onModelSelect?: (modelName: string) => void;
  className?: string;
  autoSave?: boolean;
}

export function ModelManager({
  selectedModel,
  onModelSelect,
  className = '',
  autoSave = false
}: ModelManagerProps) {
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [initialized, setInitialized] = useState(false);
  const [downloadingModels, setDownloadingModels] = useState<Set<string>>(new Set());
  const [hasUserSelection, setHasUserSelection] = useState(false);

  const onModelSelectRef = useRef(onModelSelect);
  const autoSaveRef = useRef(autoSave);

  const progressThrottleRef = useRef<Map<string, { progress: number; timestamp: number }>>(new Map());

  useEffect(() => {
    onModelSelectRef.current = onModelSelect;
    autoSaveRef.current = autoSave;
  }, [onModelSelect, autoSave]);

  const getPersistedDownloadingModels = (): Set<string> => {
    try {
      const saved = localStorage.getItem('downloading-models');
      return saved ? new Set<string>(JSON.parse(saved) as string[]) : new Set<string>();
    } catch {
      return new Set<string>();
    }
  };

  const updateDownloadingModels = (updater: (prev: Set<string>) => Set<string>) => {
    setDownloadingModels(prev => {
      const newSet = updater(prev);
      localStorage.setItem('downloading-models', JSON.stringify(Array.from(newSet)));
      return newSet;
    });
  };

  useEffect(() => {
    if (initialized) return;

    const initializeModels = async () => {
      try {
        setLoading(true);
        await WhisperAPI.init();
        const modelList = await WhisperAPI.getAvailableModels();

        const persistedDownloading = getPersistedDownloadingModels();
        const modelsWithDownloadState = modelList.map(model => {
          if (persistedDownloading.has(model.name) && model.status !== 'Available') {
            if (typeof model.status === 'object' && 'Corrupted' in model.status) {
              updateDownloadingModels(prev => {
                const newSet = new Set(prev);
                newSet.delete(model.name);
                return newSet;
              });
              return model;
            } else if (model.status === 'Missing') {
              updateDownloadingModels(prev => {
                const newSet = new Set(prev);
                newSet.delete(model.name);
                return newSet;
              });
              return model;
            } else {
              return { ...model, status: { Downloading: 0 } as ModelStatus };
            }
          }
          return model;
        });

        setModels(modelsWithDownloadState);
        setInitialized(true);
      } catch (err) {
        console.error('Failed to initialize Whisper:', err);
        setError(err instanceof Error ? err.message : 'Не удалось загрузить модели');
        toast.error('Не удалось загрузить модели для транскрипции', {
          description: err instanceof Error ? err.message : 'Неизвестная ошибка',
          duration: 5000
        });
      } finally {
        setLoading(false);
      }
    };

    initializeModels();
  }, [initialized, selectedModel, onModelSelect]);

  useEffect(() => {
    let unlistenProgress: (() => void) | null = null;
    let unlistenComplete: (() => void) | null = null;
    let unlistenError: (() => void) | null = null;

    const setupListeners = async () => {
      console.log('[ModelManager] Setting up event listeners...');

      unlistenProgress = await listen<{ modelName: string; progress: number }>(
        'model-download-progress',
        (event) => {
          const { modelName, progress } = event.payload;
          const now = Date.now();
          const throttleData = progressThrottleRef.current.get(modelName);

          const shouldUpdate = !throttleData ||
            now - throttleData.timestamp > 300 ||
            Math.abs(progress - throttleData.progress) >= 5;

          if (shouldUpdate) {
            console.log(`[ModelManager] Progress update for ${modelName}: ${progress}%`);
            progressThrottleRef.current.set(modelName, { progress, timestamp: now });

            setModels(prevModels =>
              prevModels.map(model =>
                model.name === modelName
                  ? { ...model, status: { Downloading: progress } as ModelStatus }
                  : model
              )
            );
          }
        }
      );

      unlistenComplete = await listen<{ modelName: string }>(
        'model-download-complete',
        (event) => {
          const { modelName } = event.payload;
          const model = models.find(m => m.name === modelName);
          const displayName = getDisplayName(modelName);

          setModels(prevModels =>
            prevModels.map(model =>
              model.name === modelName
                ? { ...model, status: 'Available' as ModelStatus }
                : model
            )
          );

          setDownloadingModels(prev => {
            const newSet = new Set(prev);
            newSet.delete(modelName);
            return newSet;
          });

          progressThrottleRef.current.delete(modelName);

          toast.success(`${getModelIcon(model?.accuracy || 'Good')} ${displayName} готова!`, {
            description: 'Модель скачана и готова к использованию',
            duration: 4000
          });

          if (onModelSelectRef.current) {
            onModelSelectRef.current(modelName);
            if (autoSaveRef.current) {
              saveModelSelection(modelName);
            }
          }
        }
      );

      unlistenError = await listen<{ modelName: string; error: string }>(
        'model-download-error',
        (event) => {
          const { modelName, error } = event.payload;
          const displayName = getDisplayName(modelName);

          setModels(prevModels =>
            prevModels.map(model =>
              model.name === modelName
                ? { ...model, status: { Error: error } as ModelStatus }
                : model
            )
          );

          setDownloadingModels(prev => {
            const newSet = new Set(prev);
            newSet.delete(modelName);
            return newSet;
          });

          progressThrottleRef.current.delete(modelName);

          toast.error(`Не удалось скачать ${displayName}`, {
            description: error,
            duration: 6000,
            action: {
              label: 'Повторить',
              onClick: () => downloadModel(modelName)
            }
          });
        }
      );
    };

    setupListeners();

    return () => {
      console.log('[ModelManager] Cleaning up event listeners...');
      if (unlistenProgress) unlistenProgress();
      if (unlistenComplete) unlistenComplete();
      if (unlistenError) unlistenError();
    };
  }, []);

  const saveModelSelection = async (modelName: string) => {
    try {
      await invoke('api_save_transcript_config', {
        provider: 'localWhisper',
        model: modelName,
        apiKey: null
      });
    } catch (error) {
      console.error('Failed to save model selection:', error);
    }
  };

  const cancelDownload = async (modelName: string) => {
    const displayName = getDisplayName(modelName);

    try {
      await WhisperAPI.cancelDownload(modelName);

      updateDownloadingModels(prev => {
        const newSet = new Set(prev);
        newSet.delete(modelName);
        return newSet;
      });

      setModels(prevModels =>
        prevModels.map(model =>
          model.name === modelName
            ? { ...model, status: 'Missing' as ModelStatus }
            : model
        )
      );

      progressThrottleRef.current.delete(modelName);

      toast.info(`Загрузка ${displayName} отменена`, {
        duration: 3000
      });
    } catch (err) {
      console.error('Failed to cancel download:', err);
      toast.error('Не удалось отменить загрузку', {
        description: err instanceof Error ? err.message : 'Неизвестная ошибка',
        duration: 4000
      });
    }
  };

  const downloadModel = async (modelName: string) => {
    if (downloadingModels.has(modelName)) return;

    const displayName = getDisplayName(modelName);

    try {
      updateDownloadingModels(prev => new Set([...prev, modelName]));

      setModels(prevModels =>
        prevModels.map(model =>
          model.name === modelName
            ? { ...model, status: { Downloading: 0 } as ModelStatus }
            : model
        )
      );

      toast.info(`Скачивание ${displayName}...`, {
        description: 'Это может занять несколько минут',
        duration: 5000
      });

      await WhisperAPI.downloadModel(modelName);
    } catch (err) {
      console.error('Download failed:', err);
      updateDownloadingModels(prev => {
        const newSet = new Set(prev);
        newSet.delete(modelName);
        return newSet;
      });

      const errorMessage = err instanceof Error ? err.message : 'Download failed';
      setModels(prev =>
        prev.map(model =>
          model.name === modelName ? { ...model, status: { Error: errorMessage } } : model
        )
      );
    }
  };

  const selectModel = async (modelName: string) => {
    setHasUserSelection(true);

    if (onModelSelect) {
      onModelSelect(modelName);
    }

    if (autoSave) {
      await saveModelSelection(modelName);
    }

    const displayName = getDisplayName(modelName);
    toast.success(`Выбрана модель ${displayName}`, {
      duration: 3000
    });
  };

  const deleteModel = async (modelName: string) => {
    const displayName = getDisplayName(modelName);

    try {
      await WhisperAPI.deleteCorruptedModel(modelName);

      const modelList = await WhisperAPI.getAvailableModels();
      setModels(modelList);

      toast.success(`${displayName} удалена`, {
        description: 'Модель удалена для освобождения места',
        duration: 3000
      });

      if (selectedModel === modelName && onModelSelect) {
        onModelSelect('');
      }
    } catch (err) {
      console.error('Failed to delete model:', err);
      toast.error(`Не удалось удалить ${displayName}`, {
        description: err instanceof Error ? err.message : 'Ошибка удаления',
        duration: 4000
      });
    }
  };

  const getDisplayName = (modelName: string): string => {
    const modelNameMapping: { [key: string]: string } = {
      "small": "Small",
      "medium-q5_0": "Medium",
      "large-v3-q5_0": "Large V3 (сжатая)",
      "large-v3-turbo": "Large V3 Turbo",
      "large-v3": "Large V3"
    };

    const basicModelNames = ["small", "medium-q5_0", "large-v3-q5_0", "large-v3-turbo", "large-v3"];
    if (basicModelNames.includes(modelName)) {
      return modelNameMapping[modelName] || modelName;
    }
    return `Whisper ${modelName}`;
  };

  if (loading) {
    return (
      <div className={`space-y-3 ${className}`}>
        <div className="animate-pulse space-y-3">
          <div className="h-20 bg-surface rounded-[14px]"></div>
          <div className="h-20 bg-surface rounded-[14px]"></div>
          <div className="h-20 bg-surface rounded-[14px]"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className={`rounded-[14px] border border-rec/30 bg-rec/[0.08] p-4 ${className}`}>
        <p className="text-[13px] font-medium text-rec">Не удалось загрузить модели</p>
        <p className="mt-1 text-[12px] text-fg-muted">{error}</p>
      </div>
    );
  }

  const basicModelNames = ["small", "medium-q5_0", "large-v3-q5_0", "large-v3-turbo", "large-v3"];
  const basicModels = models.filter(m => basicModelNames.includes(m.name))
    .sort((a, b) => basicModelNames.indexOf(a.name) - basicModelNames.indexOf(b.name));
  const advancedModels = models.filter(m => !basicModelNames.includes(m.name));

  return (
    <div className={`space-y-3 ${className}`}>
      {}
      <div className="space-y-3">
        {basicModels.map((model) => {
          const isRecommended = model.name === 'base';
          return (
            <ModelCard
              key={model.name}
              model={model}
              isSelected={selectedModel === model.name}
              isRecommended={isRecommended}
              onSelect={() => {
                if (model.status === 'Available') {
                  selectModel(model.name);
                }
              }}
              onDownload={() => downloadModel(model.name)}
              onCancel={() => cancelDownload(model.name)}
              onDelete={() => deleteModel(model.name)}
              isDownloading={downloadingModels.has(model.name)}
              displayName={getDisplayName(model.name)}
            />
          );
        })}
      </div>

      {}
      {advancedModels.length > 0 && (
        <Accordion type="single" collapsible className="w-full">
          <AccordionItem value="advanced-models">
            <AccordionTrigger>
              <span className='text-lg'>Дополнительные модели</span>
            </AccordionTrigger>
            <AccordionContent>
              <div className="space-y-3 pt-4">
                {advancedModels.map((model) => (
                  <ModelCard
                    key={model.name}
                    model={model}
                    isSelected={selectedModel === model.name}
                    isRecommended={false}
                    onSelect={() => {
                      if (model.status === 'Available') {
                        selectModel(model.name);
                      }
                    }}
                    onDownload={() => downloadModel(model.name)}
                    onCancel={() => cancelDownload(model.name)}
                    onDelete={() => deleteModel(model.name)}
                    isDownloading={downloadingModels.has(model.name)}
                    displayName={getDisplayName(model.name)}
                  />
                ))}
              </div>
            </AccordionContent>
          </AccordionItem>
        </Accordion>
      )}

      {}
      {selectedModel && (
        <motion.div
          initial={{ opacity: 0, y: -5 }}
          animate={{ opacity: 1, y: 0 }}
          className="text-xs text-fg-muted text-center pt-2"
        >
          Используется {getDisplayName(selectedModel)} для транскрипции
        </motion.div>
      )}
    </div>
  );
}

interface ModelCardProps {
  model: ModelInfo;
  isSelected: boolean;
  isRecommended: boolean;
  onSelect: () => void;
  onDownload: () => void;
  onCancel: () => void;
  onDelete: () => void;
  isDownloading: boolean;
  displayName: string;
}

const ACCURACY_RU: Record<string, string> = { High: 'высокая', Good: 'хорошая', Decent: 'приличная' };
const SPEED_RU: Record<string, string> = {
  Slow: 'медленная', Medium: 'средняя', Fast: 'быстрая', 'Very Fast': 'очень быстрая',
};

function ModelCard({
  model,
  isSelected,
  isRecommended,
  onSelect,
  onDownload,
  onCancel,
  onDelete,
  displayName,
}: ModelCardProps) {
  const isAvailable = model.status === 'Available';
  const isMissing = model.status === 'Missing';
  const isError = typeof model.status === 'object' && 'Error' in model.status;
  const isCorrupted = typeof model.status === 'object' && 'Corrupted' in model.status;
  const downloadProgress =
    typeof model.status === 'object' && 'Downloading' in model.status
      ? model.status.Downloading
      : null;

  const meta = [
    formatFileSize(model.size_mb),
    `точность ${ACCURACY_RU[model.accuracy] || model.accuracy}`,
    `обработка ${SPEED_RU[model.speed] || model.speed}`,
  ].join(' · ');

  const description = getModelTagline(model.name, model.speed, model.accuracy);
  const badge = isRecommended ? 'Рекомендуем' : undefined;

  const cardState: ModelCardState =
    downloadProgress !== null
      ? 'downloading'
      : isSelected && isAvailable
        ? 'selected'
        : isAvailable
          ? 'ready'
          : 'download';

  return (
    <motion.div
      initial={{ opacity: 0, y: 5 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
    >
      <EmberModelCard
        name={displayName}
        description={description}
        meta={meta}
        badge={badge}
        state={cardState}
        progress={downloadProgress ?? 0}
        onDownload={isMissing ? onDownload : undefined}
        onSelect={isAvailable ? onSelect : undefined}
      />

      {}
      {downloadProgress !== null && (
        <div className="mt-2 flex justify-end">
          <button
            onClick={(e) => {
              e.stopPropagation();
              onCancel();
            }}
            className="inline-flex items-center gap-1 rounded-md px-2 py-1 font-mono text-[11px] text-fg-faint transition-colors hover:text-rec"
            title="Отменить загрузку"
          >
            <X className="h-3 w-3" />
            Отменить
          </button>
        </div>
      )}

      {isError && downloadProgress === null && (
        <div className="mt-2 flex justify-end">
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDownload();
            }}
            className="inline-flex h-[30px] items-center rounded-md bg-rec px-3 text-[12px] font-medium text-white transition-opacity hover:opacity-90"
          >
            Повторить
          </button>
        </div>
      )}

      {isCorrupted && (
        <div className="mt-2 flex justify-end gap-2">
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDelete();
            }}
            className="inline-flex h-[30px] items-center gap-1 rounded-md border border-line bg-elevated px-3 text-[12px] font-medium text-fg-muted transition-colors hover:bg-fg/[0.04]"
          >
            <Trash2 className="h-3 w-3" />
            Удалить
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDownload();
            }}
            className="inline-flex h-[30px] items-center rounded-md bg-accent px-3 text-[12px] font-medium text-white transition-opacity hover:opacity-90"
          >
            Скачать заново
          </button>
        </div>
      )}

      {isAvailable && (
        <div className="mt-1.5 flex justify-end">
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDelete();
            }}
            className="inline-flex items-center gap-1 rounded-md px-2 py-1 font-mono text-[11px] text-fg-faint transition-colors hover:text-rec"
            title="Удалить модель для освобождения места"
          >
            <Trash2 className="h-3 w-3" />
            Удалить
          </button>
        </div>
      )}
    </motion.div>
  );
}
