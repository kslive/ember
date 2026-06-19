'use client';

import React, { useState, useEffect, useRef } from 'react';
import { Button } from './ui/button';
import { AlertTriangle, CheckCircle, X } from 'lucide-react';

interface ComplianceNotificationProps {
  isOpen: boolean;
  onClose: () => void;
  onAcknowledge: () => void;
  recordingButtonRef?: React.RefObject<HTMLElement | HTMLButtonElement>;
}

export const ComplianceNotification: React.FC<ComplianceNotificationProps> = ({
  isOpen,
  onClose,
  onAcknowledge,
  recordingButtonRef,
}) => {
  const [isVisible, setIsVisible] = useState(false);
  const [position, setPosition] = useState({ top: 0, left: 0, width: 192 });

  useEffect(() => {
    if (isOpen) {
      setIsVisible(true);
      
      if (recordingButtonRef?.current) {
        const buttonRect = recordingButtonRef.current.getBoundingClientRect();
        const buttonWidth = buttonRect.width;
        const notificationWidth = buttonWidth * 1.5;
        
        setPosition({
          top: buttonRect.top - 100,
          left: buttonRect.left + (buttonWidth - notificationWidth) / 2,
          width: notificationWidth,
        });
      } else {
        setPosition({
          top: window.innerHeight - 200,
          left: window.innerWidth - 250,
          width: 192,
        });
      }
    }
  }, [isOpen, recordingButtonRef]);

  const handleClose = () => {
    setIsVisible(false);
    setTimeout(() => {
      onClose();
    }, 200);
  };

  const handleAcknowledge = () => {
    onAcknowledge();
    handleClose();
  };

  if (!isOpen) return null;

  return (
    <div 
      className={`fixed z-50 transition-all duration-300 ${
        isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 -translate-y-2'
      }`}
      style={{
        top: `${position.top}px`,
        left: `${position.left}px`,
        width: `${position.width}px`,
      }}
    >
      <div className="bg-canvas border border-line rounded-lg shadow-soft p-3">
        {}
        <div className="flex items-start justify-between mb-2">
          <div className="flex items-center gap-1">
            <AlertTriangle className="h-3 w-3 text-amber-500 flex-shrink-0" />
            <h3 className="text-xs font-semibold text-fg">
              Recording Notice
            </h3>
          </div>
          <button
            onClick={handleClose}
            className="text-fg-faint hover:text-fg-muted transition-colors p-0.5 rounded hover:bg-surface"
          >
            <X className="h-3 w-3" />
          </button>
        </div>

        {}
        <div className="mb-2">
          <p className="text-xs text-fg-muted mb-1">
            Inform participants about recording.
          </p>
          <div className="bg-amber-50 dark:bg-amber-500/10 border border-amber-200 dark:border-amber-500/30 rounded p-1">
            <p className="text-xs text-amber-800 dark:text-amber-200 font-medium">
              US compliance required
            </p>
          </div>
        </div>

        {}
        <div className="flex gap-1">
          <Button
            variant="outline"
            size="sm"
            onClick={handleClose}
            className="text-xs px-2 py-0.5 h-6 flex-1"
          >
            Later
          </Button>
          <Button
            size="sm"
            onClick={handleAcknowledge}
            className="text-xs px-2 py-0.5 h-6 bg-green-600 hover:bg-green-700 flex-1"
          >
            <CheckCircle className="h-2 w-2 mr-1" />
            Done
          </Button>
        </div>
      </div>
    </div>
  );
};
