import { ModelConfig } from "@/components/ModelSettingsModal";
import { PreferenceSettings } from "@/components/PreferenceSettings";
import { DeviceSelection } from "@/components/DeviceSelection";
import { LanguageSelection } from "@/components/LanguageSelection";
import { TranscriptSettings } from "@/components/TranscriptSettings";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { toast } from "sonner";
import { useConfig } from "@/contexts/ConfigContext";
import { useRecordingState } from "@/contexts/RecordingStateContext";

type modalType = "modelSettings" | "deviceSettings" | "languageSettings" | "modelSelector" | "errorAlert" | "chunkDropWarning";

interface SettingsModalsProps {
  modals: {
    modelSettings: boolean;
    deviceSettings: boolean;
    languageSettings: boolean;
    modelSelector: boolean;
    errorAlert: boolean;
    chunkDropWarning: boolean;
  };
  messages: {
    errorAlert: string;
    chunkDropWarning: string;
    modelSelector: string;
  };
  onClose: (name: modalType) => void;
}

export function SettingsModals({
  modals,
  messages,
  onClose,
}: SettingsModalsProps) {
  const {
    modelConfig,
    setModelConfig,
    models,
    modelOptions,
    error,
    selectedDevices,
    setSelectedDevices,
    selectedLanguage,
    setSelectedLanguage,
    transcriptModelConfig,
    setTranscriptModelConfig,
    showConfidenceIndicator,
    toggleConfidenceIndicator,
  } = useConfig();

  const { isRecording } = useRecordingState();

  return <>
    {}
    {modals.modelSettings && (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
        <div className="bg-canvas rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col">
          {}
          <div className="flex justify-between items-center p-6 border-b">
            <h3 className="text-xl font-semibold text-fg">Preferences</h3>
            <button
              onClick={() => onClose("modelSettings")
              }
              className="text-fg-muted hover:text-fg-muted"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {}
          <div className="flex-1 overflow-y-auto p-6 space-y-8">
            {}
            <PreferenceSettings />

            {}
            <div className="border-t pt-8">
              <h4 className="text-lg font-semibold text-fg mb-4">AI Model Configuration</h4>
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-fg-muted mb-1">
                    Summarization Model
                  </label>
                  <div className="flex space-x-2">
                    <select
                      className="px-3 py-2 text-sm bg-canvas border border-line rounded-md shadow-soft focus:outline-none focus:ring-1 focus:ring-accent focus:border-accent"
                      value={modelConfig.provider}
                      onChange={(e) => {
                        const provider = e.target.value as ModelConfig['provider'];
                        setModelConfig({
                          ...modelConfig,
                          provider,
                          model: modelOptions[provider][0]
                        });
                      }}
                    >
                      <option value="builtin-ai">Built-in AI</option>
                      <option value="claude">Claude</option>
                      <option value="groq">Groq</option>
                      <option value="ollama">Ollama</option>
                      <option value="openrouter">OpenRouter</option>
                      <option value="openai">OpenAI</option>
                    </select>

                    <select
                      className="flex-1 px-3 py-2 text-sm bg-canvas border border-line rounded-md shadow-soft focus:outline-none focus:ring-1 focus:ring-accent focus:border-accent"
                      value={modelConfig.model}
                      onChange={(e) => setModelConfig((prev: ModelConfig) => ({ ...prev, model: e.target.value }))}
                    >
                      {modelOptions[modelConfig.provider].map((model: string) => (
                        <option key={model} value={model}>
                          {model}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
                {modelConfig.provider === 'ollama' && (
                  <div>
                    <h4 className="text-lg font-bold mb-4">Available Ollama Models</h4>
                    {error && (
                      <div className="bg-red-100 dark:bg-red-500/15 border border-red-400 dark:border-red-500/40 text-red-700 dark:text-red-300 px-4 py-3 rounded mb-4">
                        {error}
                      </div>
                    )}
                    <div className="grid gap-4 max-h-[400px] overflow-y-auto pr-2">
                      {models.map((model) => (
                        <div
                          key={model.id}
                          className={`bg-canvas p-4 rounded-lg shadow cursor-pointer transition-colors ${modelConfig.model === model.name ? 'ring-2 ring-accent bg-accent-weak' : 'hover:bg-surface'
                            }`}
                          onClick={() => setModelConfig((prev: ModelConfig) => ({ ...prev, model: model.name }))}
                        >
                          <h3 className="font-bold">{model.name}</h3>
                          <p className="text-fg-muted">Size: {model.size}</p>
                          <p className="text-fg-muted">Modified: {model.modified}</p>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>

          {}
          <div className="border-t p-6 flex justify-end">
            <button
              onClick={() => onClose('modelSettings')}
              className="px-4 py-2 text-sm font-medium text-white bg-accent rounded-md hover:bg-accent focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-accent"
            >
              Done
            </button>
          </div>
        </div>
      </div>
    )}

    {}
    {modals.deviceSettings && (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <div className="bg-canvas rounded-lg p-6 max-w-md w-full mx-4 shadow-xl">
          <div className="flex justify-between items-center mb-4">
            <h3 className="text-lg font-semibold text-fg">Audio Device Settings</h3>
            <button
              onClick={() => onClose('deviceSettings')}
              className="text-fg-muted hover:text-fg-muted"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <DeviceSelection
            selectedDevices={selectedDevices}
            onDeviceChange={setSelectedDevices}
            disabled={isRecording}
          />

          <div className="mt-6 flex justify-end">
            <button
              onClick={() => {
                const micDevice = selectedDevices.micDevice || 'Default';
                const systemDevice = selectedDevices.systemDevice || 'Default';
                toast.success("Devices selected", {
                  description: `Microphone: ${micDevice}, System Audio: ${systemDevice}`
                });
                onClose('deviceSettings');
              }}
              className="px-4 py-2 text-sm font-medium text-white bg-accent rounded-md hover:bg-accent focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-accent"
            >
              Done
            </button>
          </div>
        </div>
      </div>
    )}

    {}
    {modals.languageSettings && (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <div className="bg-canvas rounded-lg p-6 max-w-md w-full mx-4 shadow-xl">
          <div className="flex justify-between items-center mb-4">
            <h3 className="text-lg font-semibold text-fg">Language Settings</h3>
            <button
              onClick={() => onClose('languageSettings')}
              className="text-fg-muted hover:text-fg-muted"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <LanguageSelection
            selectedLanguage={selectedLanguage}
            onLanguageChange={setSelectedLanguage}
            disabled={isRecording}
            provider={transcriptModelConfig.provider}
          />

          <div className="mt-6 flex justify-end">
            <button
              onClick={() => onClose('languageSettings')}
              className="px-4 py-2 text-sm font-medium text-white bg-accent rounded-md hover:bg-accent focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-accent"
            >
              Done
            </button>
          </div>
        </div>
      </div>
    )}

    {}
    {modals.modelSelector && (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <div className="bg-canvas rounded-lg max-w-4xl w-full mx-4 shadow-xl max-h-[90vh] flex flex-col">
          {}
          <div className="flex justify-between items-center p-6 pb-4 border-b border-line">
            <h3 className="text-lg font-semibold text-fg">
              {messages.modelSelector ? 'Нужно настроить распознавание речи' : 'Настройки модели транскрипции'}
            </h3>
            <button
              onClick={() => onClose('modelSelector')}
              className="text-fg-muted hover:text-fg-muted"
            >
              <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {}
          <div className="flex-1 overflow-y-auto p-6 pt-4">
            <TranscriptSettings
              transcriptModelConfig={transcriptModelConfig}
              setTranscriptModelConfig={setTranscriptModelConfig}
              onModelSelect={() => onClose('modelSelector')}
            />
          </div>

          {}
          <div className="p-6 pt-4 border-t border-line flex items-center justify-between">
            {}
            <div className="flex items-center gap-3">
              <label className="relative inline-flex items-center cursor-pointer">
                <input
                  type="checkbox"
                  checked={showConfidenceIndicator}
                  onChange={(e) => toggleConfidenceIndicator(e.target.checked)}
                  className="sr-only peer"
                />
                <div className="w-11 h-6 bg-surface peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-accent rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-canvas after:border-line after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-accent"></div>
              </label>
              <div>
                <p className="text-sm font-medium text-fg-muted">Индикаторы уверенности</p>
                <p className="text-xs text-fg-muted">Цветные точки показывают уверенность транскрипции</p>
              </div>
            </div>

            <button
              onClick={() => onClose('modelSelector')}
              className="px-4 py-2 text-sm font-medium text-fg-muted bg-surface rounded-md hover:bg-surface focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-line-strong"
            >
              {messages.modelSelector ? 'Отмена' : 'Готово'}
            </button>
          </div>
        </div>
      </div>
    )}

    {}
    {modals.errorAlert && (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <Alert className="max-w-md mx-4 border-red-200 bg-canvas shadow-xl">
          <AlertTitle className="text-red-800">Recording Stopped</AlertTitle>
          <AlertDescription className="text-red-700">
            {messages.errorAlert}
            <button
              onClick={() => onClose('errorAlert')}
              className="ml-2 text-red-600 hover:text-red-800 underline"
            >
              Dismiss
            </button>
          </AlertDescription>
        </Alert>
      </div>
    )}

    {}
    {modals.chunkDropWarning && (
      <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
        <Alert className="max-w-lg mx-4 border-yellow-200 bg-canvas shadow-xl">
          <AlertTitle className="text-yellow-800">Transcription Performance Warning</AlertTitle>
          <AlertDescription className="text-yellow-700">
            {messages.chunkDropWarning}
            <button
              onClick={() => onClose('chunkDropWarning')}
              className="ml-2 text-yellow-600 hover:text-yellow-800 underline"
            >
              Dismiss
            </button>
          </AlertDescription>
        </Alert>
      </div>
    )}
  </>
}
