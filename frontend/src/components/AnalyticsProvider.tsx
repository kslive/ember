'use client';

import React, { ReactNode, createContext } from 'react';

interface AnalyticsProviderProps { children: ReactNode }

interface AnalyticsContextType {
  isAnalyticsOptedIn: boolean;
  setIsAnalyticsOptedIn: (optedIn: boolean) => void;
}

export const AnalyticsContext = createContext<AnalyticsContextType>({
  isAnalyticsOptedIn: false,
  setIsAnalyticsOptedIn: () => {},
});

export default function AnalyticsProvider({ children }: AnalyticsProviderProps) {
  return (
    <AnalyticsContext.Provider value={{ isAnalyticsOptedIn: false, setIsAnalyticsOptedIn: () => {} }}>
      {children}
    </AnalyticsContext.Provider>
  );
}
