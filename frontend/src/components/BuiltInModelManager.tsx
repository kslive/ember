'use client';

import { useState, useEffect } from 'react';
import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import { useTranslation } from 'react-i18next';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { ModelCard, type ModelCardState } from '@/components/ui/model-card';
import { RefreshCw, BadgeAlert, Trash2, X } from 'lucide-react';
import { toast } from 'sonner';
import { useLocale } from '@/contexts/LocaleContext';
import { MODEL_LABELS } from '@/constants/modelLocalization';

interface ModelInfo {
  name: string;
  display_name: string;
  status: {
    type: 'not_downloaded' | 'downloading' | 'available' | 'corrupted' | 'error';
    progress?: number;
  };
  size_mb: number;
  context_size: number;
  description: string;
  gguf_file: string;
}

interface DownloadProgressInfo {
  downloadedMb: number;
  totalMb: number;
  speedMbps: number;
}

interface BuiltInModelManagerProps {
  selectedModel: string;
  onModelSelect: (model: string) => void;
}

export function BuiltInModelManager({ selectedModel, onModelSelect }: BuiltInModelManagerProps) {
  const { t } = useTranslation('models');
  const { locale } = useLocale();
  const [models, setModels] = useState<ModelInfo[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [hasFetched, setHasFetched] = useState<boolean>(false);
  const [downloadProgress, setDownloadProgress] = useState<Record<string, number>>({});
  const [downloadProgressInfo, setDownloadProgressInfo] = useState<Record<string, DownloadProgressInfo>>({});
  const [downloadingModels, setDownloadingModels] = useState<Set<string>>(new Set());

  const fetchModels = async () => {
    try {
      setIsLoading(true);
      const data = (await invoke('builtin_ai_list_models')) as ModelInfo[];
      setModels(data);

      if (data.length > 0 && !selectedModel) {
        const firstAvailable = data.find((m) => m.status.type === 'available');
        if (firstAvailable) {
          onModelSelect(firstAvailable.name);
        }
      }
    } catch (error) {
      console.error('Failed to fetch built-in AI models:', error);
      toast.error(t('builtin.loadFailed'));
    } finally {
      setIsLoading(false);
      setHasFetched(true);
    }
  };

  useEffect(() => {
    fetchModels();
  }, []);

  useEffect(() => {
    let unlisten: (() => void) | undefined;

    const setupListener = async () => {
      unlisten = await listen('builtin-ai-download-progress', (event: any) => {
        const { model, progress, downloaded_mb, total_mb, speed_mbps, status } = event.payload;

        setDownloadProgress((prev) => ({
          ...prev,
          [model]: progress,
        }));

        setDownloadProgressInfo((prev) => ({
          ...prev,
          [model]: {
            downloadedMb: downloaded_mb ?? 0,
            totalMb: total_mb ?? 0,
            speedMbps: speed_mbps ?? 0,
          },
        }));

        if (status === 'downloading') {
          setDownloadingModels((prev) => {
            if (!prev.has(model)) {
              const newSet = new Set(prev);
              newSet.add(model);
              return newSet;
            }
            return prev;
          });
        }

        if (status === 'completed') {
          setDownloadingModels((prev) => {
            const newSet = new Set(prev);
            newSet.delete(model);
            return newSet;
          });
          setDownloadProgress((prev) => {
            const { [model]: _, ...rest } = prev;
            return rest;
          });
          setDownloadProgressInfo((prev) => {
            const { [model]: _, ...rest } = prev;
            return rest;
          });
          fetchModels();
          toast.success(t('builtin.downloadComplete', { model }));
        }

        if (status === 'cancelled') {
          setDownloadingModels((prev) => {
            const newSet = new Set(prev);
            newSet.delete(model);
            return newSet;
          });
          setDownloadProgress((prev) => {
            const { [model]: _, ...rest } = prev;
            return rest;
          });
          setDownloadProgressInfo((prev) => {
            const { [model]: _, ...rest } = prev;
            return rest;
          });
          fetchModels();
        }

        if (status === 'error') {
          setDownloadingModels((prev) => {
            const newSet = new Set(prev);
            newSet.delete(model);
            return newSet;
          });
          setDownloadProgress((prev) => {
            const { [model]: _, ...rest } = prev;
            return rest;
          });
          setDownloadProgressInfo((prev) => {
            const { [model]: _, ...rest } = prev;
            return rest;
          });

          setModels((prevModels) =>
            prevModels.map((m) =>
              m.name === model
                ? {
                    ...m,
                    status: {
                      type: 'error',
                      progress: 0,
                    } as any,
                  }
                : m
            )
          );

        }
      });
    };

    setupListener();

    return () => {
      if (unlisten) {
        unlisten();
      }
    };
  }, []);

  const downloadModel = async (modelName: string) => {
    try {
      setDownloadingModels((prev) => new Set([...prev, modelName]));

      await invoke('builtin_ai_download_model', { modelName });
    } catch (error) {
      console.error('Failed to download model:', error);

      const errorMsg = String(error);
      if (errorMsg.startsWith('CANCELLED:')) {
        return;
      }

      toast.error(t('builtin.downloadFailed', { model: modelName }));

      setDownloadingModels((prev) => {
        const newSet = new Set(prev);
        newSet.delete(modelName);
        return newSet;
      });

      fetchModels();
    }
  };

  const cancelDownload = async (modelName: string) => {
    try {
      await invoke('builtin_ai_cancel_download', { modelName });
      toast.info(t('builtin.downloadCancelled', { model: modelName }));
      setDownloadingModels((prev) => {
        const newSet = new Set(prev);
        newSet.delete(modelName);
        return newSet;
      });
    } catch (error) {
      console.error('Failed to cancel download:', error);
    }
  };

  const deleteModel = async (modelName: string) => {
    try {
      await invoke('builtin_ai_delete_model', { modelName });
      toast.success(t('builtin.deleted', { model: modelName }));
      fetchModels();
    } catch (error) {
      console.error('Failed to delete model:', error);
      toast.error(t('builtin.deleteFailed', { model: modelName }));
    }
  };

  if (isLoading && downloadingModels.size === 0) {
    return (
      <div className="py-8 text-center text-[13px] text-fg-muted">
        <RefreshCw className="mx-auto mb-2 h-7 w-7 animate-spin text-accent-text" />
        {t('loading')}
      </div>
    );
  }

  if (hasFetched && models.length === 0) {
    return (
      <Alert>
        <AlertDescription>
          {t('empty')}
        </AlertDescription>
      </Alert>
    );
  }

  return (
    <div>
      <div className="mb-3">
        <h4 className="font-mono text-[11px] uppercase tracking-[0.1em] text-fg-faint">
          {t('builtinSection')}
        </h4>
      </div>

      <div className="flex flex-col gap-3">
        {models.map((model) => {
          const progress = downloadProgress[model.name];
          const progressInfo = downloadProgressInfo[model.name];
          const modelIsDownloading = downloadingModels.has(model.name);
          const isAvailable = model.status.type === 'available';
          const isNotDownloaded = model.status.type === 'not_downloaded';
          const isCorrupted = model.status.type === 'corrupted';
          const isError = model.status.type === 'error';
          const isSelected = selectedModel === model.name;

          const lowerName = model.name.toLowerCase();
          const badge = lowerName.includes('qwen') && lowerName.includes('7b')
            ? t('badge.recommended')
            : lowerName.includes('gemma3:4b')
              ? t('badge.balance')
              : undefined;

          const localizedLabel = MODEL_LABELS[locale]?.[model.name];
          const displayName = localizedLabel?.displayName ?? model.display_name ?? model.name;
          const description = localizedLabel?.description ?? model.description;

          let meta = t('meta.sizeContext', { size: model.size_mb, tokens: model.context_size });
          if (modelIsDownloading && progressInfo?.totalMb > 0) {
            meta = t('meta.downloadProgress', {
              downloaded: progressInfo.downloadedMb.toFixed(1),
              total: progressInfo.totalMb.toFixed(1),
            });
            if (progressInfo.speedMbps > 0) {
              meta += ` · ${t('meta.downloadSpeed', { speed: progressInfo.speedMbps.toFixed(1) })}`;
            }
          }

          const cardState: ModelCardState = modelIsDownloading
            ? 'downloading'
            : isAvailable && isSelected
              ? 'selected'
              : isAvailable
                ? 'ready'
                : 'download';

          return (
            <div key={model.name}>
              <ModelCard
                name={displayName}
                description={description}
                meta={meta}
                badge={badge}
                state={cardState}
                progress={progress ?? 0}
                onDownload={isNotDownloaded ? () => downloadModel(model.name) : undefined}
                onSelect={isAvailable ? () => onModelSelect(model.name) : undefined}
              />

              {}
              {modelIsDownloading && (
                <div className="mt-2 flex justify-end">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      cancelDownload(model.name);
                    }}
                    className="inline-flex items-center gap-1 rounded-md px-2 py-1 font-mono text-[11px] text-fg-faint transition-colors hover:text-rec"
                  >
                    <X className="h-3 w-3" />
                    {t('actions.cancel')}
                  </button>
                </div>
              )}

              {}
              {isError && !modelIsDownloading && (
                <div className="mt-2 flex items-center justify-between">
                  <span className="text-[12px] text-rec">
                    {typeof model.status === 'object' && 'Error' in model.status
                      ? (model.status as any).Error
                      : t('errors.generic')}
                  </span>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={(e) => {
                      e.stopPropagation();
                      downloadModel(model.name);
                    }}
                  >
                    <RefreshCw className="mr-2 h-4 w-4" />
                    {t('actions.retry')}
                  </Button>
                </div>
              )}

              {}
              {isCorrupted && !modelIsDownloading && (
                <div className="mt-2 flex items-center justify-between">
                  <span className="flex items-center gap-1.5 text-[12px] text-rec">
                    <BadgeAlert className="h-3.5 w-3.5" />
                    {t('errors.corrupted')}
                  </span>
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={(e) => {
                        e.stopPropagation();
                        downloadModel(model.name);
                      }}
                    >
                      <RefreshCw className="mr-2 h-4 w-4" />
                      {t('actions.retry')}
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={(e) => {
                        e.stopPropagation();
                        deleteModel(model.name);
                      }}
                    >
                      <Trash2 className="mr-2 h-4 w-4" />
                      {t('actions.delete')}
                    </Button>
                  </div>
                </div>
              )}

              {}
              {isAvailable && !modelIsDownloading && !isSelected && (
                <div className="mt-1.5 flex justify-end">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      deleteModel(model.name);
                    }}
                    className="inline-flex items-center gap-1 rounded-md px-2 py-1 font-mono text-[11px] text-fg-faint transition-colors hover:text-rec"
                    title={t('actions.deleteTitle')}
                  >
                    <Trash2 className="h-3 w-3" />
                    {t('actions.delete')}
                  </button>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
