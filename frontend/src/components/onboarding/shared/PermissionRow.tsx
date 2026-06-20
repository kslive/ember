import React from 'react';
import { CheckCircle2, Loader2, XCircle } from 'lucide-react';
import { useTranslation } from 'react-i18next';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import type { PermissionRowProps } from '@/types/onboarding';

export function PermissionRow({ icon, title, description, status, isPending = false, onAction }: PermissionRowProps) {
  const { t } = useTranslation('onboarding');
  const isAuthorized = status === 'authorized';
  const isDenied = status === 'denied';
  const isChecking = isPending;

  const getButtonText = () => {
    if (isChecking) return t('permissions.row.checking');
    if (isDenied) return t('permissions.row.openSettings');
    return t('permissions.row.allow');
  };

  return (
    <div
      className={cn(
        'flex items-center justify-between rounded-[14px] border px-5 py-[18px] transition-colors',
        isAuthorized
          ? 'border-accent bg-accent-weak'
          : isDenied
            ? 'border-rec/40 bg-rec/[0.08]'
            : 'border-line bg-elevated'
      )}
    >
      {}
      <div className="flex items-center gap-3.5 flex-1 min-w-0">
        {}
        <div
          className={cn(
            'flex size-10 items-center justify-center rounded-[11px] flex-shrink-0',
            isDenied ? 'bg-rec/10 text-rec' : 'bg-surface text-accent-text'
          )}
        >
          {icon}
        </div>

        {}
        <div className="min-w-0 flex-1">
          <div className="text-[14.5px] font-semibold truncate text-fg">{title}</div>
          <div className="text-[12.5px] mt-0.5">
            {isAuthorized ? (
              <span className="text-good font-medium flex items-center gap-1.5">
                <CheckCircle2 className="w-[15px] h-[15px]" />
                {t('permissions.row.granted')}
              </span>
            ) : isDenied ? (
              <span className="text-rec font-medium flex items-center gap-1.5">
                <XCircle className="w-[15px] h-[15px]" />
                {t('permissions.row.denied')}
              </span>
            ) : (
              <span className="text-fg-muted">{description}</span>
            )}
          </div>
        </div>
      </div>

      {}
      <div className="flex items-center gap-2 flex-shrink-0 ml-3">
        {!isAuthorized && (
          <Button
            variant={isDenied ? 'outline' : 'default'}
            size="sm"
            onClick={onAction}
            disabled={isChecking}
            className="min-w-[110px]"
          >
            {isChecking && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {getButtonText()}
          </Button>
        )}
        {isAuthorized && (
          <div className="flex size-[26px] items-center justify-center rounded-full bg-accent">
            <CheckCircle2 className="w-4 h-4 text-white" strokeWidth={2.4} />
          </div>
        )}
      </div>
    </div>
  );
}
