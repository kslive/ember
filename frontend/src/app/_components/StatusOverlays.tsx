interface StatusOverlaysProps {
  isProcessing: boolean;
  isSaving: boolean;

  sidebarCollapsed: boolean;
}

interface StatusOverlayProps {
  show: boolean;
  message: string;
  sidebarCollapsed: boolean;
}

function StatusOverlay({ show, message, sidebarCollapsed }: StatusOverlayProps) {
  if (!show) return null;

  return (
    <div className="fixed bottom-4 left-0 right-0 z-10">
      <div
        className="flex justify-center pl-8 transition-[margin] duration-300"
        style={{
          marginLeft: sidebarCollapsed ? '4rem' : '16rem'
        }}
      >
        <div className="w-2/3 max-w-[750px] flex justify-center">
          <div className="bg-surface border border-line rounded-full shadow-ember px-4 py-2 flex items-center gap-2.5">
            <div className="animate-spin rounded-full h-4 w-4 border-2 border-accent-weak border-t-accent"></div>
            <span className="text-sm text-fg-muted">{message}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

export function StatusOverlays({
  isProcessing,
  isSaving,
  sidebarCollapsed
}: StatusOverlaysProps) {
  return (
    <>
      {}
      <StatusOverlay
        show={isProcessing}
        message="Завершаем расшифровку…"
        sidebarCollapsed={sidebarCollapsed}
      />

      {}
      <StatusOverlay
        show={isSaving}
        message="Сохраняем транскрипт…"
        sidebarCollapsed={sidebarCollapsed}
      />
    </>
  );
}
