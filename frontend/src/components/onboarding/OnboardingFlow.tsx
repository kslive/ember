import React, { useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { useOnboarding } from '@/contexts/OnboardingContext';
import {
  WelcomeStep,
  PermissionsStep,
  DownloadProgressStep,
  SetupOverviewStep,
} from './steps';

interface OnboardingFlowProps {
  onComplete: () => void;
}

export function OnboardingFlow({ onComplete }: OnboardingFlowProps) {
  const { currentStep } = useOnboarding();
  const [isMac, setIsMac] = React.useState(false);

  useEffect(() => {
    const checkPlatform = async () => {
      try {
        const { platform } = await import('@tauri-apps/plugin-os');
        setIsMac(platform() === 'macos');
      } catch (e) {
        console.error('Failed to detect platform:', e);
        setIsMac(navigator.userAgent.includes('Mac'));
      }
    };
    checkPlatform();
  }, []);

  const stepEl =
    currentStep === 1 ? <WelcomeStep /> :
    currentStep === 2 ? <SetupOverviewStep /> :
    currentStep === 3 ? <DownloadProgressStep /> :
    currentStep === 4 && isMac ? <PermissionsStep /> :
    null;

  const prevStep = useRef(currentStep);
  const direction = currentStep >= prevStep.current ? 1 : -1;
  useEffect(() => {
    prevStep.current = currentStep;
  }, [currentStep]);

  const offset = 24 * direction;

  return (
    <div className="onboarding-flow h-screen w-screen overflow-hidden">
      <AnimatePresence mode="wait" initial={false} custom={direction}>
        <motion.div
          key={currentStep}
          custom={direction}
          initial={{ opacity: 0, x: offset }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -offset }}
          transition={{ duration: 0.28, ease: [0.22, 1, 0.36, 1] }}
          className="h-full w-full"
        >
          {stepEl}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
