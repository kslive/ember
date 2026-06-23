'use client'

import './globals.css'
import { GeistSans } from 'geist/font/sans'
import { GeistMono } from 'geist/font/mono'
import Sidebar from '@/components/Sidebar'
import { SidebarProvider } from '@/components/Sidebar/SidebarProvider'
import AnalyticsProvider from '@/components/AnalyticsProvider'
import { Toaster, toast } from 'sonner'
import "sonner/dist/styles.css"
import { useState, useEffect } from 'react'
import { listen } from '@tauri-apps/api/event'
import { invoke } from '@tauri-apps/api/core'
import { getCurrentWindow } from '@tauri-apps/api/window'
import { TooltipProvider } from '@/components/ui/tooltip'
import { RecordingStateProvider } from '@/contexts/RecordingStateContext'
import { OllamaDownloadProvider } from '@/contexts/OllamaDownloadContext'
import { TranscriptProvider } from '@/contexts/TranscriptContext'
import { ConfigProvider } from '@/contexts/ConfigContext'
import { ThemeProvider } from '@/contexts/ThemeContext'
import { LocaleProvider } from '@/contexts/LocaleContext'
import i18n from '@/i18n'
import { OnboardingProvider } from '@/contexts/OnboardingContext'
import { OnboardingFlow } from '@/components/onboarding'
import { RootErrorBoundary } from '@/components/RootErrorBoundary'
import { RecordingPostProcessingProvider } from '@/contexts/RecordingPostProcessingProvider'
import { UpdateBanner } from '@/components/UpdateBanner'
import { PanelGroup, Panel, PanelResizeHandle } from 'react-resizable-panels'

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const [showOnboarding, setShowOnboarding] = useState<boolean | null>(null)

  useEffect(() => {
    invoke<{ completed: boolean } | null>('get_onboarding_status')
      .then((status) => {
        setShowOnboarding(!status?.completed)
      })
      .catch((error) => {
        console.error('[Layout] Failed to check onboarding status:', error)
        setShowOnboarding(true)
      })
  }, [])

  useEffect(() => {
    const raf = requestAnimationFrame(() =>
      requestAnimationFrame(() => { getCurrentWindow().show().catch(() => {}) })
    )
    return () => cancelAnimationFrame(raf)
  }, [])

  useEffect(() => {
    if (process.env.NODE_ENV === 'production') {
      const handleContextMenu = (e: MouseEvent) => e.preventDefault();
      document.addEventListener('contextmenu', handleContextMenu);
      return () => document.removeEventListener('contextmenu', handleContextMenu);
    }
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && (e.key === 'r' || e.key === 'R')) {
        e.preventDefault();
        if (!showOnboarding) {
          window.dispatchEvent(new CustomEvent('start-recording-from-sidebar'));
        }
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [showOnboarding]);

  useEffect(() => {
    const unlisten = listen('request-recording-toggle', () => {
      if (showOnboarding) {
        toast.error(i18n.t('common:onboardingRequired.title'), {
          description: i18n.t('common:onboardingRequired.description')
        });
      } else {
        window.dispatchEvent(new CustomEvent('start-recording-from-sidebar'));
      }
    });
    return () => { unlisten.then(fn => fn()); };
  }, [showOnboarding]);

  const handleOnboardingComplete = () => {
    setShowOnboarding(false)
    window.location.reload()
  }

  return (
    <html lang="ru" data-theme="auto" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body className="font-sans antialiased">
        <RootErrorBoundary>
          <ThemeProvider>
          <LocaleProvider>
          <AnalyticsProvider>
            <RecordingStateProvider>
              <TranscriptProvider>
                <ConfigProvider>
                  <OllamaDownloadProvider>
                    <OnboardingProvider>
                      <SidebarProvider>
                        <TooltipProvider>
                          <RecordingPostProcessingProvider>
                            {showOnboarding === null ? (
                              <div className="h-screen bg-canvas" />
                            ) : showOnboarding ? (
                              <OnboardingFlow onComplete={handleOnboardingComplete} />
                            ) : (
                              <div className="h-screen relative">
                                {}
                                <div
                                  className="titlebar-drag pointer-events-auto absolute top-0 left-0 right-0 h-7 z-50"
                                  aria-hidden
                                />
                                <PanelGroup direction="horizontal" autoSaveId="ember-shell" className="h-screen">
                                  <Panel defaultSize={19} minSize={14} maxSize={32} className="min-w-0">
                                    <Sidebar />
                                  </Panel>
                                  {}
                                  <PanelResizeHandle className="w-px bg-line data-[resize-handle-state=hover]:bg-accent/50 data-[resize-handle-state=drag]:bg-accent transition-colors relative outline-none cursor-col-resize before:absolute before:inset-y-0 before:-left-1 before:-right-1 before:content-['']" />
                                  {}
                                  <Panel className="min-w-0">
                                    <main className="h-full min-w-0 overflow-hidden bg-canvas flex flex-col">
                                      <UpdateBanner />
                                      <div className="flex-1 min-h-0 overflow-hidden">{children}</div>
                                    </main>
                                  </Panel>
                                </PanelGroup>
                              </div>
                            )}
                          </RecordingPostProcessingProvider>
                        </TooltipProvider>
                      </SidebarProvider>
                    </OnboardingProvider>
                  </OllamaDownloadProvider>
                </ConfigProvider>
              </TranscriptProvider>
            </RecordingStateProvider>
          </AnalyticsProvider>
          </LocaleProvider>
          </ThemeProvider>
        </RootErrorBoundary>

        <Toaster position="bottom-right" closeButton gap={12} offset={24} />
      </body>
    </html>
  )
}
