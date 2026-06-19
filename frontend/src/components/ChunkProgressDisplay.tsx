import React from 'react';

export interface ChunkStatus {
  chunk_id: number;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  start_time?: number;
  end_time?: number;
  duration_ms?: number;
  text_preview?: string;
  error_message?: string;
}

export interface ProcessingProgress {
  total_chunks: number;
  completed_chunks: number;
  processing_chunks: number;
  failed_chunks: number;
  estimated_remaining_ms?: number;
  chunks: ChunkStatus[];
}

interface ChunkProgressDisplayProps {
  progress: ProcessingProgress;
  onPause?: () => void;
  onResume?: () => void;
  onCancel?: () => void;
  isPaused?: boolean;
  className?: string;
}

export function ChunkProgressDisplay({
  progress,
  onPause,
  onResume,
  onCancel,
  isPaused = false,
  className = ''
}: ChunkProgressDisplayProps) {
  const completionPercentage = progress.total_chunks > 0
    ? Math.round((progress.completed_chunks / progress.total_chunks) * 100)
    : 0;

  const formatDuration = (ms: number) => {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
    } else if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`;
    } else {
      return `${seconds}s`;
    }
  };

  const formatTimeRemaining = (ms?: number) => {
    if (!ms || ms <= 0) return 'Calculating...';
    return formatDuration(ms);
  };

  const getChunkStatusIcon = (status: ChunkStatus['status']) => {
    switch (status) {
      case 'completed':
        return '✅';
      case 'processing':
        return '⚡';
      case 'failed':
        return '❌';
      case 'pending':
      default:
        return '⏳';
    }
  };

  const getChunkStatusColor = (status: ChunkStatus['status']) => {
    switch (status) {
      case 'completed':
        return 'text-green-600 bg-green-50 dark:bg-green-500/10 border-green-200 dark:border-green-500/30';
      case 'processing':
        return 'text-accent-text bg-accent-weak border-accent';
      case 'failed':
        return 'text-red-600 bg-red-50 dark:bg-red-500/10 border-red-200 dark:border-red-500/30';
      case 'pending':
      default:
        return 'text-fg-muted bg-surface border-line';
    }
  };

  return (
    <div className={`bg-canvas border border-line rounded-lg p-4 ${className}`}>
      {}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-3">
          <h3 className="text-lg font-semibold text-fg">
            Processing Progress
          </h3>
          {isPaused && (
            <span className="bg-yellow-100 dark:bg-yellow-500/15 text-yellow-800 dark:text-yellow-200 px-2 py-1 rounded-full text-xs font-medium">
              Paused
            </span>
          )}
        </div>

        <div className="flex items-center space-x-2">
          {!isPaused ? (
            <button
              onClick={onPause}
              className="bg-yellow-500 hover:bg-yellow-600 text-white px-3 py-1 rounded text-sm transition-colors"
              disabled={progress.processing_chunks === 0 && progress.completed_chunks === progress.total_chunks}
            >
              Pause
            </button>
          ) : (
            <button
              onClick={onResume}
              className="bg-green-500 hover:bg-green-600 text-white px-3 py-1 rounded text-sm transition-colors"
            >
              Resume
            </button>
          )}

          <button
            onClick={onCancel}
            className="bg-red-500 hover:bg-red-600 text-white px-3 py-1 rounded text-sm transition-colors"
          >
            Cancel
          </button>
        </div>
      </div>

      {}
      <div className="mb-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm font-medium text-fg-muted">
            {progress.completed_chunks} of {progress.total_chunks} chunks completed
          </span>
          <span className="text-sm font-medium text-fg-muted">
            {completionPercentage}%
          </span>
        </div>

        <div className="w-full bg-surface rounded-full h-2">
          <div
            className="bg-accent h-2 rounded-full transition-all duration-300 ease-out"
            style={{ width: `${completionPercentage}%` }}
          />
        </div>
      </div>

      {}
      <div className="grid grid-cols-4 gap-4 mb-4 text-sm">
        <div className="text-center">
          <div className="text-lg font-semibold text-green-600">
            {progress.completed_chunks}
          </div>
          <div className="text-fg-muted">Completed</div>
        </div>

        <div className="text-center">
          <div className="text-lg font-semibold text-accent-text">
            {progress.processing_chunks}
          </div>
          <div className="text-fg-muted">Processing</div>
        </div>

        <div className="text-center">
          <div className="text-lg font-semibold text-fg-muted">
            {progress.total_chunks - progress.completed_chunks - progress.processing_chunks - progress.failed_chunks}
          </div>
          <div className="text-fg-muted">Pending</div>
        </div>

        <div className="text-center">
          <div className="text-lg font-semibold text-red-600">
            {progress.failed_chunks}
          </div>
          <div className="text-fg-muted">Failed</div>
        </div>
      </div>

      {}
      {progress.estimated_remaining_ms && progress.estimated_remaining_ms > 0 && (
        <div className="bg-accent-weak border border-accent rounded-lg p-3 mb-4">
          <div className="flex items-center space-x-2">
            <span className="text-accent-text">⏱️</span>
            <span className="text-sm text-accent-text">
              Estimated time remaining: {formatTimeRemaining(progress.estimated_remaining_ms)}
            </span>
          </div>
        </div>
      )}

      {}
      <div className="space-y-2">
        <h4 className="text-sm font-medium text-fg-muted mb-2">
          Recent Chunks ({Math.min(progress.chunks.length, 10)} of {progress.total_chunks})
        </h4>

        <div className="max-h-48 overflow-y-auto space-y-1">
          {progress.chunks
            .slice(-10)
            .reverse()
            .map((chunk) => (
              <div
                key={chunk.chunk_id}
                className={`text-xs p-2 rounded border ${getChunkStatusColor(chunk.status)}`}
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center space-x-2">
                    <span>{getChunkStatusIcon(chunk.status)}</span>
                    <span className="font-medium">
                      Chunk {chunk.chunk_id}
                    </span>
                    {chunk.duration_ms && (
                      <span className="text-fg-muted">
                        ({formatDuration(chunk.duration_ms)})
                      </span>
                    )}
                  </div>

                  {chunk.status === 'processing' && (
                    <div className="flex items-center space-x-1">
                      <div className="animate-spin w-3 h-3 border border-accent border-t-transparent rounded-full"></div>
                    </div>
                  )}
                </div>

                {chunk.text_preview && (
                  <div className="mt-1 text-fg-muted text-xs truncate">
                    "{chunk.text_preview}"
                  </div>
                )}

                {chunk.error_message && (
                  <div className="mt-1 text-red-700 dark:text-red-300 text-xs">
                    Error: {chunk.error_message}
                  </div>
                )}
              </div>
            ))}
        </div>
      </div>

      {}
      {progress.completed_chunks === progress.total_chunks && progress.total_chunks > 0 && (
        <div className="mt-4 bg-green-50 dark:bg-green-500/10 border border-green-200 dark:border-green-500/30 rounded-lg p-3">
          <div className="flex items-center space-x-2">
            <span className="text-green-600">🎉</span>
            <span className="text-sm font-medium text-green-800 dark:text-green-200">
              Processing completed! All {progress.total_chunks} chunks have been transcribed.
            </span>
          </div>
        </div>
      )}
    </div>
  );
}

export function ChunkProgressMini({ progress, className = '' }: { progress: ProcessingProgress; className?: string }) {
  const completionPercentage = progress.total_chunks > 0
    ? Math.round((progress.completed_chunks / progress.total_chunks) * 100)
    : 0;

  return (
    <div className={`bg-surface border border-line rounded-lg p-3 ${className}`}>
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm font-medium text-fg-muted">
          Processing
        </span>
        <span className="text-sm font-medium text-fg-muted">
          {completionPercentage}%
        </span>
      </div>

      <div className="w-full bg-surface rounded-full h-1.5 mb-2">
        <div
          className="bg-accent h-1.5 rounded-full transition-all duration-300"
          style={{ width: `${completionPercentage}%` }}
        />
      </div>

      <div className="text-xs text-fg-muted">
        {progress.completed_chunks} / {progress.total_chunks} chunks
        {progress.processing_chunks > 0 && (
          <span className="ml-2 text-accent-text">
            ({progress.processing_chunks} processing)
          </span>
        )}
      </div>
    </div>
  );
}