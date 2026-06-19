'use client';

import type { ReactNode } from 'react';

export interface TranscriptLabelProps {
    children: ReactNode;
    className?: string;
}

const BASE_LABEL_CLASS = 'font-mono text-[10.5px] uppercase tracking-[0.12em] text-fg-faint';

export function TranscriptLabel({ children, className = '' }: TranscriptLabelProps) {
    return (
        <span className={`${BASE_LABEL_CLASS}${className ? ` ${className}` : ''}`}>
            {children}
        </span>
    );
}
