'use client';

import React, { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { ArrowLeft, Settings2, Mic, Database as DatabaseIcon, SparkleIcon } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { invoke } from '@tauri-apps/api/core';
import { TranscriptSettings } from '@/components/TranscriptSettings';
import { RecordingSettings } from '@/components/RecordingSettings';
import { PreferenceSettings } from '@/components/PreferenceSettings';
import { SummaryModelSettings } from '@/components/SummaryModelSettings';
import { useConfig } from '@/contexts/ConfigContext';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs';

const TABS = [
  { value: 'general', label: 'Общие', icon: Settings2 },
  { value: 'recording', label: 'Запись', icon: Mic },
  { value: 'Transcriptionmodels', label: 'Транскрипция', icon: DatabaseIcon },
  { value: 'summaryModels', label: 'Саммари', icon: SparkleIcon },
] as const;

export default function SettingsPage() {
  const router = useRouter();
  const { transcriptModelConfig, setTranscriptModelConfig } = useConfig();

  const [activeTab, setActiveTab] = useState('general');

  useEffect(() => {
    const loadTranscriptConfig = async () => {
      try {
        const config = await invoke('api_get_transcript_config') as any;
        if (config) {
          setTranscriptModelConfig({
            provider: config.provider || 'localWhisper',
            model: config.model || 'large-v3',
            apiKey: config.apiKey || null
          });
        }
      } catch (error) {
        console.error('Failed to load transcript config:', error);
      }
    };
    loadTranscriptConfig();
  }, [setTranscriptModelConfig]);

  return (
    <div className="h-full bg-canvas flex flex-col overflow-hidden">
      <Tabs value={activeTab} onValueChange={setActiveTab} className="flex flex-col flex-1 min-h-0">
        <header className="flex-none px-9 pt-[26px] titlebar-drag">
          <button
            onClick={() => router.back()}
            className="titlebar-no-drag inline-flex items-center gap-1.5 -ml-2 mb-3 px-2 h-7 rounded-[8px] text-[13px] text-fg-muted hover:bg-fg/[0.05] transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            <span>Назад</span>
          </button>
          <h1 className="text-[26px] font-semibold tracking-[-0.02em] text-fg mb-5">Настройки</h1>
          <TabsList className="bg-surface rounded-[11px] p-1 h-auto inline-flex gap-[3px] w-max titlebar-no-drag">
            {TABS.map((tab) => {
              const Icon = tab.icon;
              const isActive = activeTab === tab.value;
              return (
                <TabsTrigger
                  key={tab.value}
                  value={tab.value}
                  className="relative inline-flex items-center gap-[7px] px-[15px] py-2 text-[13.5px] rounded-[8px] text-fg-muted hover:text-fg data-[state=active]:text-fg data-[state=active]:font-medium transition-colors"
                >
                  {isActive && (
                    <motion.div
                      layoutId="settings-tab-indicator"
                      className="absolute inset-0 rounded-[8px] bg-elevated shadow-sm"
                      transition={{ type: 'spring', stiffness: 380, damping: 32 }}
                    />
                  )}
                  <Icon className="relative z-10 w-3.5 h-3.5" />
                  <span className="relative z-10">{tab.label}</span>
                </TabsTrigger>
              );
            })}
          </TabsList>
        </header>

        <div className="flex-1 min-h-0 overflow-y-auto custom-scrollbar">
          <div className="px-9 py-7">
            <TabsContent value="general" className="mt-0">
              <PreferenceSettings />
            </TabsContent>
            <TabsContent value="recording" className="mt-0">
              <RecordingSettings />
            </TabsContent>
            <TabsContent value="Transcriptionmodels" className="mt-0">
              <TranscriptSettings
                transcriptModelConfig={transcriptModelConfig}
                setTranscriptModelConfig={setTranscriptModelConfig}
              />
            </TabsContent>
            <TabsContent value="summaryModels" className="mt-0">
              <SummaryModelSettings />
            </TabsContent>
          </div>
        </div>
      </Tabs>
    </div>
  );
};
