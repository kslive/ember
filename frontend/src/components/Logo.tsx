'use client';

import React from 'react';

interface LogoProps { isCollapsed?: boolean }

export default function Logo({ isCollapsed = false }: LogoProps) {
  return (
    <div className="flex items-center gap-2.5 select-none" title="Ember">
      <span
        className="h-[9px] w-[9px] flex-none rounded-full bg-accent"
        style={{ boxShadow: '0 0 10px rgba(249,115,22,.7)' }}
        aria-hidden
      />
      {!isCollapsed && (
        <span className="text-[17px] font-medium text-fg tracking-[-0.01em] lowercase">
          ember
        </span>
      )}
    </div>
  );
}
