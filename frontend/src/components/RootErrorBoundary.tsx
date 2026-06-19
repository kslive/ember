'use client';

import React from 'react';

interface State {
  error?: Error;
  info?: React.ErrorInfo;
}

export class RootErrorBoundary extends React.Component<{ children: React.ReactNode }, State> {
  state: State = {};

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('RootErrorBoundary caught:', error, info);
    this.setState({ error, info });
  }

  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: 20, fontFamily: 'monospace', whiteSpace: 'pre-wrap', color: '#b91c1c' }}>
          <h1 style={{ fontSize: 18, fontWeight: 700 }}>Application crashed</h1>
          <div><strong>Message:</strong> {String(this.state.error?.message || this.state.error)}</div>
          <details open style={{ marginTop: 12 }}>
            <summary>Stack</summary>
            <pre style={{ fontSize: 12 }}>{this.state.error?.stack}</pre>
          </details>
          {this.state.info && (
            <details open style={{ marginTop: 12 }}>
              <summary>Component stack</summary>
              <pre style={{ fontSize: 12 }}>{this.state.info.componentStack}</pre>
            </details>
          )}
          <button
            onClick={() => location.reload()}
            style={{ marginTop: 16, padding: '6px 12px', background: '#1f2937', color: '#fff', borderRadius: 6 }}
          >
            Reload
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
