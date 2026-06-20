'use client'

import * as React from 'react'
import * as DialogPrimitive from '@radix-ui/react-dialog'
import { Trash2, AlertTriangle, Info, X } from 'lucide-react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'

export type EmberDialogTone = 'danger' | 'warning' | 'info'

export interface EmberDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onConfirm: () => void
  title: string
  message?: string
  tone?: EmberDialogTone
  confirmLabel?: string
  cancelLabel?: string
  showIcon?: boolean
  confirmIcon?: boolean
  busy?: boolean
}

const TONES: Record<
  EmberDialogTone,
  { iconWrap: string; icon: React.ReactNode; confirm: string }
> = {
  danger: {
    iconWrap: 'bg-rec/[0.13] text-rec',
    icon: <Trash2 className="h-[19px] w-[19px]" strokeWidth={1.8} />,
    confirm: 'bg-rec text-white hover:opacity-90',
  },
  warning: {
    iconWrap: 'bg-warn/[0.14] text-warn',
    icon: <AlertTriangle className="h-[19px] w-[19px]" strokeWidth={1.8} />,
    confirm: 'bg-accent text-white hover:opacity-90',
  },
  info: {
    iconWrap: 'bg-accent-weak text-accent-text',
    icon: <Info className="h-[19px] w-[19px]" strokeWidth={1.8} />,
    confirm: 'bg-accent text-white hover:opacity-90',
  },
}

export function EmberDialog({
  open,
  onOpenChange,
  onConfirm,
  title,
  message,
  tone = 'danger',
  confirmLabel,
  cancelLabel,
  showIcon = true,
  confirmIcon,
  busy = false,
}: EmberDialogProps) {
  const { t: translate } = useTranslation('common')
  const t = TONES[tone]
  const showConfirmIcon = confirmIcon ?? tone === 'danger'
  const resolvedConfirmLabel = confirmLabel ?? translate('delete')
  const resolvedCancelLabel = cancelLabel ?? translate('cancel')

  return (
    <DialogPrimitive.Root open={open} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50 backdrop-blur-[3px] data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=closed]:animate-out data-[state=closed]:fade-out-0" />
        <DialogPrimitive.Content
          onOpenAutoFocus={(e) => e.preventDefault()}
          className={cn(
            'fixed left-1/2 top-1/2 z-50 w-[420px] max-w-[calc(100%-48px)] -translate-x-1/2 -translate-y-1/2',
            'overflow-hidden rounded-[14px] border border-line bg-elevated text-fg',
            'shadow-[0_30px_70px_-18px_rgba(0,0,0,0.55)] focus:outline-none',
            'data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95',
            'data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=closed]:zoom-out-95',
          )}
        >
          <div className="p-6 pb-5">
            <div className="flex items-start gap-3.5">
              {showIcon && (
                <div
                  className={cn(
                    'flex h-10 w-10 flex-none items-center justify-center rounded-[11px]',
                    t.iconWrap,
                  )}
                >
                  {t.icon}
                </div>
              )}
              <div className="min-w-0 flex-1 pt-px">
                <DialogPrimitive.Title className="mb-1.5 text-[16.5px] font-semibold tracking-[-0.01em]">
                  {title}
                </DialogPrimitive.Title>
                {message && (
                  <DialogPrimitive.Description className="m-0 text-[13.5px] leading-[1.55] text-fg-muted">
                    {message}
                  </DialogPrimitive.Description>
                )}
              </div>
              <DialogPrimitive.Close
                aria-label={translate('close')}
                className="-mr-0.5 -mt-0.5 flex-none p-0.5 text-fg-faint transition-colors hover:text-fg"
              >
                <X className="h-4 w-4" strokeWidth={2} />
              </DialogPrimitive.Close>
            </div>
          </div>
          <div className="flex justify-end gap-[9px] border-t border-line px-6 py-3.5">
            <button
              type="button"
              onClick={() => onOpenChange(false)}
              className="h-[38px] rounded-[11px] border border-line-strong bg-transparent px-4 text-[13.5px] font-medium text-fg transition-colors hover:bg-fg/[0.05]"
            >
              {resolvedCancelLabel}
            </button>
            <button
              type="button"
              onClick={onConfirm}
              disabled={busy}
              className={cn(
                'inline-flex h-[38px] items-center gap-[7px] rounded-[11px] px-[18px] text-[13.5px] font-semibold transition-opacity disabled:opacity-60',
                t.confirm,
              )}
            >
              {showConfirmIcon && <Trash2 className="h-3.5 w-3.5" strokeWidth={2} />}
              {resolvedConfirmLabel}
            </button>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  )
}
