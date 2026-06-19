import { useState, useEffect, useRef } from 'react';
import { useSidebar } from './Sidebar/SidebarProvider';
import { invoke } from '@tauri-apps/api/core';
import { Button } from '@/components/ui/button';
import { useOllamaDownload } from '@/contexts/OllamaDownloadContext';
import { BuiltInModelManager } from '@/components/BuiltInModelManager';
import { ModelCard, type ModelCardState } from '@/components/ui/model-card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useConfig } from '@/contexts/ConfigContext';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Switch } from '@/components/ui/switch';
import { Lock, Unlock, Eye, EyeOff, RefreshCw, CheckCircle2, XCircle, ChevronDown, ChevronUp, Download, ExternalLink, Check, ChevronsUpDown } from 'lucide-react';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command';
import { cn, isOllamaNotInstalledError } from '@/lib/utils';
import { toast } from 'sonner';

export interface ModelConfig {
  provider: 'ollama' | 'groq' | 'claude' | 'openai' | 'openrouter' | 'builtin-ai' | 'custom-openai';
  model: string;
  whisperModel: string;
  apiKey?: string | null;
  ollamaEndpoint?: string | null;
  customOpenAIEndpoint?: string | null;
  customOpenAIModel?: string | null;
  customOpenAIApiKey?: string | null;
  maxTokens?: number | null;
  temperature?: number | null;
  topP?: number | null;
}

interface OllamaModel {
  name: string;
  id: string;
  size: string;
  modified: string;
}

interface OpenRouterModel {
  id: string;
  name: string;
  context_length?: number;
  prompt_price?: string;
  completion_price?: string;
}

interface OpenAIModel {
  id: string;
}

interface AnthropicModel {
  id: string;
  display_name?: string;
}

interface GroqModel {
  id: string;
  owned_by?: string;
}

const OPENAI_FALLBACK_MODELS = [
  'gpt-4o',
  'gpt-4o-mini',
  'gpt-4-turbo',
  'gpt-4',
  'gpt-3.5-turbo',
  'o1',
  'o1-mini',
  'o3',
  'o3-mini',
];

const CLAUDE_FALLBACK_MODELS = [
  'claude-sonnet-4-5-20250929',
  'claude-haiku-4-5-20251001',
  'claude-opus-4-5-20251101',
  'claude-3-5-sonnet-latest',
];

const GROQ_FALLBACK_MODELS = [
  'llama-3.3-70b-versatile',
  'llama-3.1-70b-versatile',
  'mixtral-8x7b-32768',
  'gemma2-9b-it',
];

interface ModelSettingsModalProps {
  modelConfig: ModelConfig;
  setModelConfig: (config: ModelConfig | ((prev: ModelConfig) => ModelConfig)) => void;
  onSave: (config: ModelConfig) => void;
  skipInitialFetch?: boolean;
}

export function ModelSettingsModal({
  modelConfig: propsModelConfig,
  setModelConfig: propsSetModelConfig,
  onSave,
  skipInitialFetch = false,
}: ModelSettingsModalProps) {
  const configContext = useConfig();
  const modelConfig = configContext?.modelConfig || propsModelConfig;
  const setModelConfig = configContext?.setModelConfig || propsSetModelConfig;
  const providerApiKeys = configContext?.providerApiKeys;
  const updateProviderApiKey = configContext?.updateProviderApiKey;

  const [models, setModels] = useState<OllamaModel[]>([]);
  const [error, setError] = useState<string>('');
  const [apiKey, setApiKey] = useState<string | null>(modelConfig.apiKey || null);
  const [showApiKey, setShowApiKey] = useState<boolean>(false);
  const [isApiKeyLocked, setIsApiKeyLocked] = useState<boolean>(!!modelConfig.apiKey?.trim());
  const [isLockButtonVibrating, setIsLockButtonVibrating] = useState<boolean>(false);
  const { serverAddress } = useSidebar();
  const [openRouterModels, setOpenRouterModels] = useState<OpenRouterModel[]>([]);
  const [openRouterError, setOpenRouterError] = useState<string>('');
  const [isLoadingOpenRouter, setIsLoadingOpenRouter] = useState<boolean>(false);
  const [ollamaEndpoint, setOllamaEndpoint] = useState<string>(modelConfig.ollamaEndpoint || '');
  const [isLoadingOllama, setIsLoadingOllama] = useState<boolean>(false);
  const [lastFetchedEndpoint, setLastFetchedEndpoint] = useState<string>(modelConfig.ollamaEndpoint || '');
  const [endpointValidationState, setEndpointValidationState] = useState<'valid' | 'invalid' | 'none'>('none');
  const [hasAutoFetched, setHasAutoFetched] = useState<boolean>(false);
  const hasSyncedFromParent = useRef<boolean>(false);
  const hasLoadedInitialConfig = useRef<boolean>(false);
  const [autoGenerateEnabled, setAutoGenerateEnabled] = useState<boolean>(true);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [isEndpointSectionCollapsed, setIsEndpointSectionCollapsed] = useState<boolean>(true);
  const [ollamaNotInstalled, setOllamaNotInstalled] = useState<boolean>(false);

  const [customOpenAIEndpoint, setCustomOpenAIEndpoint] = useState<string>(modelConfig.customOpenAIEndpoint || '');
  const [customOpenAIModel, setCustomOpenAIModel] = useState<string>(modelConfig.customOpenAIModel || '');
  const [customOpenAIApiKey, setCustomOpenAIApiKey] = useState<string>(modelConfig.customOpenAIApiKey || '');
  const [customMaxTokens, setCustomMaxTokens] = useState<string>(modelConfig.maxTokens?.toString() || '');
  const [customTemperature, setCustomTemperature] = useState<string>(modelConfig.temperature?.toString() || '');
  const [customTopP, setCustomTopP] = useState<string>(modelConfig.topP?.toString() || '');
  const [isCustomOpenAIAdvancedOpen, setIsCustomOpenAIAdvancedOpen] = useState<boolean>(false);
  const [isTestingConnection, setIsTestingConnection] = useState<boolean>(false);

  const [modelComboboxOpen, setModelComboboxOpen] = useState<boolean>(false);

  const [openaiModels, setOpenaiModels] = useState<string[]>([]);
  const [claudeModels, setClaudeModels] = useState<string[]>([]);
  const [groqModels, setGroqModels] = useState<string[]>([]);
  const [isLoadingOpenAI, setIsLoadingOpenAI] = useState<boolean>(false);
  const [isLoadingClaude, setIsLoadingClaude] = useState<boolean>(false);
  const [isLoadingGroq, setIsLoadingGroq] = useState<boolean>(false);

  const { isDownloading, getProgress, downloadingModels } = useOllamaDownload();

  const [builtinAiModels, setBuiltinAiModels] = useState<any[]>([]);

  const modelsCache = useRef<Map<string, OllamaModel[]>>(new Map());

  const validateOllamaEndpoint = (url: string): boolean => {
    if (!url.trim()) return true;
    try {
      const parsed = new URL(url);
      return parsed.protocol === 'http:' || parsed.protocol === 'https:';
    } catch {
      return false;
    }
  };

  useEffect(() => {
    const timer = setTimeout(() => {
      const trimmed = ollamaEndpoint.trim();

      if (!trimmed) {
        setEndpointValidationState('none');
      } else if (validateOllamaEndpoint(trimmed)) {
        setEndpointValidationState('valid');
      } else {
        setEndpointValidationState('invalid');
      }
    }, 500);

    return () => clearTimeout(timer);
  }, [ollamaEndpoint]);

  const fetchApiKey = async (provider: string) => {
    try {
      const data = (await invoke('api_get_api_key', {
        provider,
      })) as string;
      setApiKey(data || '');
    } catch (err) {
      console.error('Error fetching API key:', err);
      setApiKey(null);
    }
  };

  useEffect(() => {
    const hasContent = !!apiKey?.trim();
    if (!hasContent) {
      setIsApiKeyLocked(false);
    }
  }, [apiKey]);

  const modelOptions: Record<string, string[]> = {
    ollama: models.map((model) => model.name),
    claude: claudeModels.length > 0 ? claudeModels : CLAUDE_FALLBACK_MODELS,
    groq: groqModels.length > 0 ? groqModels : GROQ_FALLBACK_MODELS,
    openai: openaiModels.length > 0 ? openaiModels : OPENAI_FALLBACK_MODELS,
    openrouter: openRouterModels.map((m) => m.id),
    'builtin-ai': builtinAiModels.map((m) => m.name),
    'custom-openai': customOpenAIModel ? [customOpenAIModel] : [],
  };

  const requiresApiKey =
    modelConfig.provider === 'claude' ||
    modelConfig.provider === 'groq' ||
    modelConfig.provider === 'openai' ||
    modelConfig.provider === 'openrouter';

  const ollamaEndpointChanged = modelConfig.provider === 'ollama' &&
    ollamaEndpoint.trim() !== lastFetchedEndpoint.trim();

  const isCustomOpenAIInvalid = modelConfig.provider === 'custom-openai' && (
    !customOpenAIEndpoint.trim() ||
    !customOpenAIModel.trim()
  );

  useEffect(() => {
    const fetchModelConfig = async () => {
      if (skipInitialFetch) {
        hasLoadedInitialConfig.current = true;
        return;
      }

      try {
        const data = (await invoke('api_get_model_config')) as any;
        if (data && data.provider !== null) {
          setModelConfig(data);

          if (data.provider !== 'ollama' && !data.apiKey) {
            try {
              const apiKeyData = await invoke('api_get_api_key', {
                provider: data.provider
              }) as string;
              data.apiKey = apiKeyData;
              setApiKey(apiKeyData);
            } catch (err) {
              console.error('Failed to fetch API key:', err);
            }
          }

          if (data.ollamaEndpoint) {
            setOllamaEndpoint(data.ollamaEndpoint);
          }
          hasLoadedInitialConfig.current = true;

          if (data.provider === 'custom-openai') {
            try {
              const customConfig = (await invoke('api_get_custom_openai_config')) as any;
              if (customConfig) {
                setCustomOpenAIEndpoint(customConfig.endpoint || '');
                setCustomOpenAIModel(customConfig.model || '');
                setCustomOpenAIApiKey(customConfig.apiKey || '');
                setCustomMaxTokens(customConfig.maxTokens?.toString() || '');
                setCustomTemperature(customConfig.temperature?.toString() || '');
                setCustomTopP(customConfig.topP?.toString() || '');
              }
            } catch (err) {
              console.error('Failed to fetch custom OpenAI config:', err);
            }
          }
        }
      } catch (error) {
        console.error('Failed to fetch model config:', error);
        hasLoadedInitialConfig.current = true;
      }
    };

    fetchModelConfig();
  }, [skipInitialFetch]);

  useEffect(() => {
    const fetchAutoGenerateSetting = async () => {
      try {
        const enabled = (await invoke('api_get_auto_generate_setting')) as boolean;
        setAutoGenerateEnabled(enabled);
        console.log('Auto-generate setting loaded:', enabled);
      } catch (err) {
        console.error('Failed to fetch auto-generate setting:', err);
      }
    };

    fetchAutoGenerateSetting();
  }, []);

  useEffect(() => {
    const endpoint = modelConfig.ollamaEndpoint || '';
    if (endpoint !== ollamaEndpoint) {
      setOllamaEndpoint(endpoint);
    }
    if (modelConfig.provider) {
      hasSyncedFromParent.current = true;
    }
  }, [modelConfig.ollamaEndpoint, modelConfig.provider]);

  useEffect(() => {
    if (modelConfig.provider === 'custom-openai') {
      console.log('Syncing custom OpenAI fields from ConfigContext:', {
        endpoint: modelConfig.customOpenAIEndpoint,
        model: modelConfig.customOpenAIModel,
        hasApiKey: !!modelConfig.customOpenAIApiKey,
      });

      setCustomOpenAIEndpoint(modelConfig.customOpenAIEndpoint || '');
      setCustomOpenAIModel(modelConfig.customOpenAIModel || '');
      setCustomOpenAIApiKey(modelConfig.customOpenAIApiKey || '');
      setCustomMaxTokens(modelConfig.maxTokens?.toString() || '');
      setCustomTemperature(modelConfig.temperature?.toString() || '');
      setCustomTopP(modelConfig.topP?.toString() || '');
    }
  }, [
    modelConfig.provider,
    modelConfig.customOpenAIEndpoint,
    modelConfig.customOpenAIModel,
    modelConfig.customOpenAIApiKey,
    modelConfig.maxTokens,
    modelConfig.temperature,
    modelConfig.topP
  ]);

  useEffect(() => {
    if (modelConfig.provider !== 'ollama') {
      setHasAutoFetched(false);
      setModels([]);
      setError('');
      setOllamaNotInstalled(false);
    }
  }, [modelConfig.provider]);

  useEffect(() => {
    if (modelConfig.provider === 'ollama' &&
      ollamaEndpoint.trim() !== lastFetchedEndpoint.trim()) {

      const cachedModels = modelsCache.current.get(ollamaEndpoint.trim());

      if (cachedModels && cachedModels.length > 0) {
        setModels(cachedModels);
        setLastFetchedEndpoint(ollamaEndpoint.trim());
        setError('');
      } else {
        setHasAutoFetched(false);
        setModels([]);
        setError('');
      }
    }
  }, [ollamaEndpoint, lastFetchedEndpoint, modelConfig.provider]);

  useEffect(() => {
    if (providerApiKeys && requiresApiKey && modelConfig.provider !== 'custom-openai') {
      const correctKey = providerApiKeys[modelConfig.provider as keyof typeof providerApiKeys];
      if (correctKey !== apiKey) {
        setApiKey(correctKey || '');
        setIsApiKeyLocked(!!correctKey?.trim());
      }
    }
  }, [modelConfig.provider, providerApiKeys, requiresApiKey]);

  const fetchOllamaModels = async (silent = false) => {
    const trimmedEndpoint = ollamaEndpoint.trim();

    if (trimmedEndpoint && !validateOllamaEndpoint(trimmedEndpoint)) {
      const errorMsg = 'Некорректный адрес Ollama. Должен начинаться с http:// или https://';
      setError(errorMsg);
      if (!silent) {
        toast.error(errorMsg);
      }
      return;
    }

    setIsLoadingOllama(true);
    setError('');

    try {
      const endpoint = trimmedEndpoint || null;
      const modelList = (await invoke('get_ollama_models', { endpoint })) as OllamaModel[];
      setModels(modelList);
      setLastFetchedEndpoint(trimmedEndpoint);

      modelsCache.current.set(trimmedEndpoint, modelList);

      setOllamaNotInstalled(false);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Не удалось загрузить модели Ollama';
      setError(errorMsg);

      if (isOllamaNotInstalledError(errorMsg)) {
        setOllamaNotInstalled(true);
      } else {
        setOllamaNotInstalled(false);
      }

      if (!silent) {
        toast.error(errorMsg);
      }
      console.error('Error loading models:', err);
    } finally {
      setIsLoadingOllama(false);
    }
  };

  useEffect(() => {
    let mounted = true;

    const initialLoad = async () => {
      if (modelConfig.provider === 'ollama' &&
        !hasAutoFetched &&
        mounted) {
        await fetchOllamaModels(skipInitialFetch);
        setHasAutoFetched(true);
      }
    };

    initialLoad();

    return () => {
      mounted = false;
    };
  }, [modelConfig.provider]);

  const loadOpenRouterModels = async () => {
    if (openRouterModels.length > 0) return;

    try {
      setIsLoadingOpenRouter(true);
      setOpenRouterError('');
      const data = (await invoke('get_openrouter_models')) as OpenRouterModel[];
      setOpenRouterModels(data);
    } catch (err) {
      console.error('Error loading OpenRouter models:', err);
      setOpenRouterError(
        err instanceof Error ? err.message : 'Не удалось загрузить модели OpenRouter'
      );
    } finally {
      setIsLoadingOpenRouter(false);
    }
  };

  const loadBuiltinAiModels = async () => {
    if (builtinAiModels.length > 0) return;

    try {
      const data = (await invoke('builtin_ai_list_models')) as any[];
      setBuiltinAiModels(data);

      if (data.length > 0 && !modelConfig.model) {
        const firstAvailable = data.find((m: any) => m.status?.type === 'available');
        if (firstAvailable) {
          setModelConfig((prev: ModelConfig) => ({ ...prev, model: firstAvailable.name }));
        }
      }
    } catch (err) {
      console.error('Error loading Built-in AI models:', err);
      toast.error('Не удалось загрузить встроенные модели');
    }
  };

  const loadOpenAIModels = async (key: string | null) => {
    if (!key?.trim()) {
      setOpenaiModels([]);
      return;
    }
    setIsLoadingOpenAI(true);
    try {
      const data = (await invoke('get_openai_models', { apiKey: key })) as OpenAIModel[];
      setOpenaiModels(data.map((m) => m.id));
    } catch (err) {
      console.error('Error loading OpenAI models:', err);
      setOpenaiModels([]);
    } finally {
      setIsLoadingOpenAI(false);
    }
  };

  const loadClaudeModels = async (key: string | null) => {
    if (!key?.trim()) {
      setClaudeModels([]);
      return;
    }
    setIsLoadingClaude(true);
    try {
      const data = (await invoke('get_anthropic_models', { apiKey: key })) as AnthropicModel[];
      setClaudeModels(data.map((m) => m.id));
    } catch (err) {
      console.error('Error loading Claude models:', err);
      setClaudeModels([]);
    } finally {
      setIsLoadingClaude(false);
    }
  };

  const loadGroqModels = async (key: string | null) => {
    if (!key?.trim()) {
      setGroqModels([]);
      return;
    }
    setIsLoadingGroq(true);
    try {
      const data = (await invoke('get_groq_models', { apiKey: key })) as GroqModel[];
      setGroqModels(data.map((m) => m.id));
    } catch (err) {
      console.error('Error loading Groq models:', err);
      setGroqModels([]);
    } finally {
      setIsLoadingGroq(false);
    }
  };

  useEffect(() => {
    if (modelConfig.provider === 'openai' && apiKey?.trim()) {
      loadOpenAIModels(apiKey);
    }
  }, [modelConfig.provider, apiKey]);

  useEffect(() => {
    if (modelConfig.provider === 'claude' && apiKey?.trim()) {
      loadClaudeModels(apiKey);
    }
  }, [modelConfig.provider, apiKey]);

  useEffect(() => {
    if (modelConfig.provider === 'groq' && apiKey?.trim()) {
      loadGroqModels(apiKey);
    }
  }, [modelConfig.provider, apiKey]);

  useEffect(() => {
    const providerModels = modelOptions[modelConfig.provider];
    if (!providerModels || providerModels.length === 0) return;

    if (modelConfig.model && providerModels.includes(modelConfig.model)) return;

    const map = JSON.parse(localStorage.getItem('providerModelMap') || '{}');
    const cachedModel = map[modelConfig.provider];
    if (cachedModel && providerModels.includes(cachedModel)) {
      setModelConfig((prev: ModelConfig) => ({ ...prev, model: cachedModel }));
    }
  }, [models, openRouterModels, builtinAiModels, openaiModels, claudeModels, groqModels, modelConfig.provider]);

  const commitConfig = async (modelOverride?: string) => {
    if (modelConfig.provider === 'custom-openai') {
      try {
        await invoke('api_save_custom_openai_config', {
          endpoint: customOpenAIEndpoint.trim(),
          apiKey: customOpenAIApiKey.trim() || null,
          model: customOpenAIModel.trim(),
          maxTokens: customMaxTokens ? parseInt(customMaxTokens, 10) : null,
          temperature: customTemperature ? parseFloat(customTemperature) : null,
          topP: customTopP ? parseFloat(customTopP) : null,
        });
        console.log('Custom OpenAI config saved successfully');
      } catch (err) {
        console.error('Failed to save custom OpenAI config:', err);
        toast.error('Не удалось сохранить настройки OpenAI-совместимого сервера');
        return;
      }
    }

    const selectedModel = modelConfig.provider === 'custom-openai'
      ? customOpenAIModel.trim()
      : (modelOverride ?? modelConfig.model);

    const updatedConfig = {
      ...modelConfig,
      apiKey: typeof apiKey === 'string' ? apiKey.trim() || null : null,
      ollamaEndpoint: modelConfig.provider === 'ollama'
        ? (ollamaEndpoint.trim() || null)
        : (modelConfig.ollamaEndpoint || null),
      customOpenAIEndpoint: modelConfig.provider === 'custom-openai' ? customOpenAIEndpoint.trim() : null,
      customOpenAIModel: modelConfig.provider === 'custom-openai' ? customOpenAIModel.trim() : null,
      customOpenAIApiKey: modelConfig.provider === 'custom-openai' && customOpenAIApiKey.trim() ? customOpenAIApiKey.trim() : null,
      maxTokens: modelConfig.provider === 'custom-openai' && customMaxTokens ? parseInt(customMaxTokens, 10) : null,
      temperature: modelConfig.provider === 'custom-openai' && customTemperature ? parseFloat(customTemperature) : null,
      topP: modelConfig.provider === 'custom-openai' && customTopP ? parseFloat(customTopP) : null,
      model: selectedModel,
    };
    setModelConfig(updatedConfig);
    console.log('ModelSettingsModal - commitConfig - Updated ModelConfig:', updatedConfig);

    if (updatedConfig.model) {
      const map = JSON.parse(localStorage.getItem('providerModelMap') || '{}');
      map[updatedConfig.provider] = updatedConfig.model;
      localStorage.setItem('providerModelMap', JSON.stringify(map));
    }

    if (updateProviderApiKey && updatedConfig.apiKey && updatedConfig.provider !== 'custom-openai') {
      updateProviderApiKey(updatedConfig.provider, updatedConfig.apiKey);
    }

    onSave(updatedConfig);
  };

  const testCustomOpenAIConnection = async () => {
    if (!customOpenAIEndpoint.trim() || !customOpenAIModel.trim()) {
      toast.error('Сначала укажите адрес (URL) и название модели');
      return;
    }

    setIsTestingConnection(true);
    try {
      const result = await invoke<{ status: string; message: string }>('api_test_custom_openai_connection', {
        endpoint: customOpenAIEndpoint.trim(),
        apiKey: customOpenAIApiKey.trim() || null,
        model: customOpenAIModel.trim(),
      });
      toast.success(result.message || 'Подключение успешно!');
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      toast.error(errorMsg);
    } finally {
      setIsTestingConnection(false);
    }
  };

  const handleInputClick = () => {
    if (isApiKeyLocked) {
      setIsLockButtonVibrating(true);
      setTimeout(() => setIsLockButtonVibrating(false), 500);
    }
  };

  const downloadRecommendedModel = async () => {
    const recommendedModel = 'gemma3:1b';

    if (isDownloading(recommendedModel)) {
      toast.info(`${recommendedModel} уже скачивается`, {
        description: `Прогресс: ${Math.round(getProgress(recommendedModel) || 0)}%`
      });
      return;
    }

    try {
      const endpoint = ollamaEndpoint.trim() || null;

      await invoke('pull_ollama_model', {
        modelName: recommendedModel,
        endpoint
      });

      await fetchOllamaModels(true);

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to download model';
      console.error('Error downloading model:', err);

      if (isOllamaNotInstalledError(errorMsg)) {
        toast.error('Ollama не установлена', {
          description: 'Скачайте и установите Ollama перед загрузкой моделей.',
          duration: 7000,
          action: {
            label: 'Скачать',
            onClick: () => invoke('open_external_url', { url: 'https://ollama.com/download' })
          }
        });
        setOllamaNotInstalled(true);
      }
    }
  };

  const deleteOllamaModel = async (modelName: string) => {
    try {
      const endpoint = ollamaEndpoint.trim() || null;
      await invoke('delete_ollama_model', {
        modelName,
        endpoint
      });

      toast.success(`Модель ${modelName} удалена`);
      await fetchOllamaModels(true);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Не удалось удалить модель';
      toast.error(errorMsg);
      console.error('Error deleting model:', err);
    }
  };

  const previousDownloadingRef = useRef<Set<string>>(new Set());

  useEffect(() => {
    const current = downloadingModels;
    const previous = previousDownloadingRef.current;

    for (const modelName of previous) {
      if (!current.has(modelName)) {
        console.log(`[ModelSettingsModal] Download completed for ${modelName}, refreshing list`);
        fetchOllamaModels(true);
        break;
      }
    }

    previousDownloadingRef.current = new Set(current);
  }, [downloadingModels]);

  const filteredModels = models.filter((model) => {
    if (!searchQuery.trim()) return true;

    const query = searchQuery.toLowerCase();
    const isLoaded = modelConfig.model === model.name;
    const loadedText = isLoaded ? 'loaded' : '';

    return (
      model.name.toLowerCase().includes(query) ||
      model.size.toLowerCase().includes(query) ||
      loadedText.includes(query)
    );
  });

  return (
    <div className="flex flex-col max-h-[85vh] min-h-0">
      <div className="flex-none flex justify-between items-center mb-4">
        <h3 className="text-lg font-semibold">Настройки модели</h3>
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto space-y-4 pr-1">
        <div>
          <Label>Модель для конспектов</Label>
          <div className="flex space-x-2 mt-1">
            <Select
              value={modelConfig.provider}
              onValueChange={(value) => {
                const provider = value as ModelConfig['provider'];

                setError('');

                const map = JSON.parse(localStorage.getItem('providerModelMap') || '{}');
                if (modelConfig.model) {
                  map[modelConfig.provider] = modelConfig.model;
                  localStorage.setItem('providerModelMap', JSON.stringify(map));
                }

                const savedModel = map[provider];
                const providerModels = modelOptions[provider];
                const defaultModel = providerModels && providerModels.length > 0
                  ? providerModels[0]
                  : '';
                const model = (savedModel && providerModels?.includes(savedModel))
                  ? savedModel
                  : defaultModel;

                setModelConfig({
                  ...modelConfig,
                  provider,
                  model,
                });

                if (provider === 'openrouter') {
                  loadOpenRouterModels();
                }

                if (provider === 'builtin-ai') {
                  loadBuiltinAiModels();
                }

                if (provider === 'custom-openai') {
                  invoke<any>('api_get_custom_openai_config').then((config) => {
                    if (config) {
                      setCustomOpenAIEndpoint(config.endpoint || '');
                      setCustomOpenAIModel(config.model || '');
                      setCustomOpenAIApiKey(config.apiKey || '');
                      setCustomMaxTokens(config.maxTokens?.toString() || '');
                      setCustomTemperature(config.temperature?.toString() || '');
                      setCustomTopP(config.topP?.toString() || '');
                    }
                  }).catch((err) => {
                    console.error('Failed to load custom OpenAI config:', err);
                  });
                }
              }}
            >
              <SelectTrigger>
                <SelectValue placeholder="Выберите провайдера" />
              </SelectTrigger>
              <SelectContent className="max-h-64 overflow-y-auto">
                <SelectItem value="builtin-ai">Встроенная локальная модель (без API)</SelectItem>
                <SelectItem value="ollama">Ollama (локально)</SelectItem>
                <SelectItem value="custom-openai">Свой OpenAI-совместимый сервер (локально)</SelectItem>
              </SelectContent>
            </Select>

            {modelConfig.provider !== 'builtin-ai' && modelConfig.provider !== 'custom-openai' && (
              <Popover open={modelComboboxOpen} onOpenChange={setModelComboboxOpen} modal={true}>
                <PopoverTrigger asChild>
                  <Button
                    variant="outline"
                    role="combobox"
                    aria-expanded={modelComboboxOpen}
                    className="flex-1 max-w-[200px] justify-between font-normal"
                  >
                    <span className="truncate">
                      {modelConfig.model || "Выберите модель…"}
                    </span>
                    <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-[250px] p-0" align="start">
                  <Command>
                    <CommandInput placeholder="Поиск моделей…" />
                    <CommandList className="max-h-[300px]">
                      {(modelConfig.provider === 'openrouter' && isLoadingOpenRouter) ||
                       (modelConfig.provider === 'openai' && isLoadingOpenAI) ||
                       (modelConfig.provider === 'claude' && isLoadingClaude) ||
                       (modelConfig.provider === 'groq' && isLoadingGroq) ? (
                        <div className="py-6 text-center text-sm text-muted-foreground">
                          <RefreshCw className="mx-auto h-4 w-4 animate-spin mb-2" />
                          Загрузка моделей…
                        </div>
                      ) : (
                        <>
                          <CommandEmpty>Модели не найдены.</CommandEmpty>
                          <CommandGroup>
                            {modelOptions[modelConfig.provider]?.map((model) => (
                              <CommandItem
                                key={model}
                                value={model}
                                onSelect={(currentValue) => {
                                  setModelConfig((prev: ModelConfig) => ({ ...prev, model: currentValue }));
                                  setModelComboboxOpen(false);
                                }}
                              >
                                <Check
                                  className={cn(
                                    "mr-2 h-4 w-4",
                                    modelConfig.model === model ? "opacity-100" : "opacity-0"
                                  )}
                                />
                                <span className="truncate">{model}</span>
                              </CommandItem>
                            ))}
                          </CommandGroup>
                        </>
                      )}
                    </CommandList>
                  </Command>
                </PopoverContent>
              </Popover>
            )}
          </div>
        </div>

        {}
        {modelConfig.provider === 'custom-openai' && (
          <div className="space-y-4 border-t pt-4">
            <div>
              <Label htmlFor="custom-endpoint">Адрес (URL) *</Label>
              <Input
                id="custom-endpoint"
                value={customOpenAIEndpoint}
                onChange={(e) => setCustomOpenAIEndpoint(e.target.value)}
                placeholder="http://localhost:8000/v1"
                className="mt-1"
              />
              <p className="text-xs text-muted-foreground mt-1">
                Базовый URL OpenAI-совместимого API
              </p>
            </div>

            <div>
              <Label htmlFor="custom-model">Название модели *</Label>
              <Input
                id="custom-model"
                value={customOpenAIModel}
                onChange={(e) => setCustomOpenAIModel(e.target.value)}
                placeholder="gpt-4, llama-3-70b и т.д."
                className="mt-1"
              />
              <p className="text-xs text-muted-foreground mt-1">
                Идентификатор модели для запросов
              </p>
            </div>

            <div>
              <Label htmlFor="custom-api-key">API-ключ (необязательно)</Label>
              <Input
                id="custom-api-key"
                type="password"
                value={customOpenAIApiKey}
                onChange={(e) => setCustomOpenAIApiKey(e.target.value)}
                placeholder="Оставьте пустым, если не требуется"
                className="mt-1"
              />
            </div>

            {}
            <div>
              <div
                className="flex items-center justify-between cursor-pointer py-2"
                onClick={() => setIsCustomOpenAIAdvancedOpen(!isCustomOpenAIAdvancedOpen)}
              >
                <Label className="cursor-pointer">Дополнительно</Label>
                {isCustomOpenAIAdvancedOpen ? (
                  <ChevronUp className="h-4 w-4 text-muted-foreground" />
                ) : (
                  <ChevronDown className="h-4 w-4 text-muted-foreground" />
                )}
              </div>

              {isCustomOpenAIAdvancedOpen && (
                <div className="space-y-3 pl-2 border-l-2 border-muted mt-2">
                  <div>
                    <Label htmlFor="custom-max-tokens">Макс. токенов</Label>
                    <Input
                      id="custom-max-tokens"
                      type="number"
                      value={customMaxTokens}
                      onChange={(e) => setCustomMaxTokens(e.target.value)}
                      placeholder="напр., 4096"
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="custom-temperature">Температура (0.0–2.0)</Label>
                    <Input
                      id="custom-temperature"
                      type="number"
                      step="0.1"
                      min="0"
                      max="2"
                      value={customTemperature}
                      onChange={(e) => setCustomTemperature(e.target.value)}
                      placeholder="напр., 0.7"
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <Label htmlFor="custom-top-p">Top P (0.0–1.0)</Label>
                    <Input
                      id="custom-top-p"
                      type="number"
                      step="0.1"
                      min="0"
                      max="1"
                      value={customTopP}
                      onChange={(e) => setCustomTopP(e.target.value)}
                      placeholder="напр., 0.9"
                      className="mt-1"
                    />
                  </div>
                </div>
              )}
            </div>

            {}
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={testCustomOpenAIConnection}
              disabled={isTestingConnection || !customOpenAIEndpoint.trim() || !customOpenAIModel.trim()}
              className="w-full"
            >
              {isTestingConnection ? (
                <>
                  <RefreshCw className="mr-2 h-4 w-4 animate-spin" />
                  Проверка подключения…
                </>
              ) : (
                <>
                  <CheckCircle2 className="mr-2 h-4 w-4" />
                  Проверить подключение
                </>
              )}
            </Button>
          </div>
        )}

        {requiresApiKey && (
          <div>
            <Label>API-ключ</Label>
            <div className="relative mt-1">
              <Input
                type={showApiKey ? 'text' : 'password'}
                value={apiKey || ''}
                onChange={(e) => setApiKey(e.target.value)}
                disabled={isApiKeyLocked}
                placeholder="Введите ваш API-ключ"
                className="pr-24"
              />
              {isApiKeyLocked && apiKey?.trim() && (
                <div
                  onClick={handleInputClick}
                  className="absolute inset-0 flex items-center justify-center bg-muted/50 rounded-md cursor-not-allowed"
                />
              )}
              <div className="absolute inset-y-0 right-0 pr-1 flex items-center space-x-1">
                {apiKey?.trim() && (
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    onClick={() => setIsApiKeyLocked(!isApiKeyLocked)}
                    className={isLockButtonVibrating ? 'animate-vibrate text-red-500' : ''}
                    title={isApiKeyLocked ? 'Разблокировать для редактирования' : 'Заблокировать от изменений'}
                  >
                    {isApiKeyLocked ? <Lock /> : <Unlock />}
                  </Button>
                )}
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  onClick={() => setShowApiKey(!showApiKey)}
                >
                  {showApiKey ? <EyeOff /> : <Eye />}
                </Button>
              </div>
            </div>
          </div>
        )}

        {modelConfig.provider === 'ollama' && (
          <div>
            <div
              className="flex items-center justify-between cursor-pointer py-2"
              onClick={() => setIsEndpointSectionCollapsed(!isEndpointSectionCollapsed)}
            >
              <Label className="cursor-pointer">Свой адрес (необязательно)</Label>
              {isEndpointSectionCollapsed ? (
                <ChevronDown className="h-4 w-4 text-muted-foreground" />
              ) : (
                <ChevronUp className="h-4 w-4 text-muted-foreground" />
              )}
            </div>

            {!isEndpointSectionCollapsed && (
              <>
                <p className="text-sm text-muted-foreground mt-1 mb-2">
                  Оставьте пустым или укажите свой адрес (напр., http://x.yy.zz:11434)
                </p>
                <div className="flex gap-2 mt-1">
                  <div className="relative flex-1">
                    <Input
                      type="url"
                      value={ollamaEndpoint}
                      onChange={(e) => {
                        setOllamaEndpoint(e.target.value);
                        if (e.target.value.trim() !== lastFetchedEndpoint.trim()) {
                          setModels([]);
                          setError('');
                        }
                      }}
                      placeholder="http://localhost:11434"
                      className={cn(
                        "pr-10",
                        endpointValidationState === 'invalid' && "border-red-500"
                      )}
                    />
                    {endpointValidationState === 'valid' && (
                      <CheckCircle2 className="absolute right-3 top-1/2 -translate-y-1/2 h-5 w-5 text-green-500" />
                    )}
                    {endpointValidationState === 'invalid' && (
                      <XCircle className="absolute right-3 top-1/2 -translate-y-1/2 h-5 w-5 text-red-500" />
                    )}
                  </div>
                  <Button
                    type="button"
                    size={'sm'}
                    onClick={() => fetchOllamaModels()}
                    disabled={isLoadingOllama}
                    variant="outline"
                    className="whitespace-nowrap"
                  >
                    {isLoadingOllama ? (
                      <>
                        <RefreshCw className="mr-2 h-4 w-4 animate-spin" />
                        Загрузка…
                      </>
                    ) : (
                      <>
                        <RefreshCw className="mr-2 h-4 w-4" />
                        Загрузить список моделей
                      </>
                    )}
                  </Button>
                </div>
                {ollamaEndpointChanged && !error && (
                  <Alert className="mt-3 border-yellow-500 bg-yellow-50 dark:bg-yellow-500/10 dark:border-yellow-500/40">
                    <AlertDescription className="text-yellow-800 dark:text-yellow-200">
                      Адрес изменён. Перед сохранением нажмите «Загрузить список моделей», чтобы загрузить модели с нового адреса.
                    </AlertDescription>
                  </Alert>
                )}
              </>
            )}
          </div>
        )}

        {modelConfig.provider === 'ollama' && (
          <div>
            <div className="flex items-center justify-between mb-4">
              <h4 className="text-sm font-bold">Доступные модели Ollama</h4>
              {lastFetchedEndpoint && models.length > 0 && (
                <div className="flex items-center gap-2 text-sm">
                  <span className="text-muted-foreground">Используется:</span>
                  <code className="px-2 py-1 bg-muted rounded text-xs">
                    {lastFetchedEndpoint || 'http://localhost:11434'}
                  </code>
                </div>
              )}
            </div>
            {models.length > 0 && (
              <div className="mb-4">
                <Input
                  placeholder="Поиск моделей…"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full"
                />
              </div>
            )}
            {isLoadingOllama ? (
              <div className="text-center py-8 text-muted-foreground">
                <RefreshCw className="mx-auto h-8 w-8 animate-spin mb-2" />
                Загрузка моделей…
              </div>
            ) : models.length === 0 ? (
              <div className="space-y-3">
                {ollamaNotInstalled ? (
                  <div className="space-y-4">
                    <Alert className="border-orange-500 bg-orange-50 dark:bg-orange-500/10 dark:border-orange-500/40">
                      <AlertDescription className="text-orange-800 dark:text-orange-200">
                        Ollama не установлена или не запущена. Скачайте и установите Ollama, чтобы использовать локальные модели.
                      </AlertDescription>
                    </Alert>
                    <Button
                      variant="default"
                      size="sm"
                      onClick={() => invoke('open_external_url', { url: 'https://ollama.com/download' })}
                      className="w-full bg-accent hover:bg-accent"
                    >
                      <ExternalLink className="mr-2 h-4 w-4" />
                      Скачать Ollama
                    </Button>
                    <div className="text-sm text-muted-foreground text-center">
                      После установки Ollama перезапустите приложение и нажмите «Загрузить список моделей», чтобы продолжить.
                    </div>
                  </div>
                ) : (
                  <>
                    <Alert className="mb-4">
                      <AlertDescription>
                        {ollamaEndpointChanged
                          ? 'Адрес изменён. Нажмите «Загрузить список моделей», чтобы загрузить модели с нового адреса.'
                          : 'Модели не найдены. Скачайте рекомендуемую модель или нажмите «Загрузить список моделей», чтобы загрузить доступные модели Ollama.'}
                      </AlertDescription>
                    </Alert>
                    {!ollamaEndpointChanged && (
                      <div className="space-y-3">
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={downloadRecommendedModel}
                          disabled={isDownloading('gemma3:1b')}
                          className="w-full"
                        >
                          {isDownloading('gemma3:1b') ? (
                            <>
                              <RefreshCw className="mr-2 h-4 w-4 animate-spin" />
                              Скачивание gemma3:1b…
                            </>
                          ) : (
                            <>
                              <Download className="mr-2 h-4 w-4" />
                              Скачать gemma3:1b (рекомендуется, ~800МБ)
                            </>
                          )}
                        </Button>

                        {}
                        {isDownloading('gemma3:1b') && getProgress('gemma3:1b') !== undefined && (
                          <div className="bg-canvas rounded-md border p-3">
                            <div className="flex items-center justify-between mb-2">
                              <span className="text-sm font-medium text-accent-text">Скачивание gemma3:1b</span>
                              <span className="text-sm font-semibold text-accent-text">
                                {Math.round(getProgress('gemma3:1b')!)}%
                              </span>
                            </div>
                            <div className="w-full h-2 bg-surface rounded-full overflow-hidden">
                              <div
                                className="h-full bg-gradient-to-r from-accent to-accent rounded-full transition-all duration-300"
                                style={{ width: `${getProgress('gemma3:1b')}%` }}
                              />
                            </div>
                          </div>
                        )}
                      </div>
                    )}
                  </>
                )}
              </div>
            ) : !ollamaEndpointChanged && (
              <div className="pr-1">
                {filteredModels.length === 0 ? (
                  <Alert>
                    <AlertDescription>
                      По запросу «{searchQuery}» модели не найдены. Попробуйте изменить запрос.
                    </AlertDescription>
                  </Alert>
                ) : (
                  <div className="grid gap-4">
                    {filteredModels.map((model) => {
                      const progress = getProgress(model.name);
                      const modelIsDownloading = isDownloading(model.name);
                      const isSelected = modelConfig.model === model.name;

                      const cardState: ModelCardState = modelIsDownloading
                        ? 'downloading'
                        : isSelected
                          ? 'selected'
                          : 'ready';

                      return (
                        <ModelCard
                          key={model.id}
                          name={model.name}
                          meta={`размер ${model.size}`}
                          state={cardState}
                          progress={progress ?? 0}
                          onCardClick={
                            modelIsDownloading
                              ? undefined
                              : () => commitConfig(model.name)
                          }
                        />
                      );
                    })}
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {}
        {modelConfig.provider === 'builtin-ai' && (
          <div className="mt-6">
            <BuiltInModelManager
              selectedModel={modelConfig.model}
              onModelSelect={(model) => {
                setModelConfig((prev: ModelConfig) => ({ ...prev, model }));
                commitConfig(model);
              }}
            />
          </div>
        )}
      </div>

      {}
      {}

      {}
      {modelConfig.provider === 'custom-openai' && (
        <div className="flex-none mt-6 flex justify-end">
          <Button
            className={cn(
              'px-4 text-sm font-medium text-white rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-accent',
              isCustomOpenAIInvalid ? 'bg-elevated cursor-not-allowed' : 'bg-accent hover:bg-accent'
            )}
            onClick={() => commitConfig()}
            disabled={isCustomOpenAIInvalid}
          >
            Сохранить
          </Button>
        </div>
      )}
    </div>
  );
}
