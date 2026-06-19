/** @type {import('tailwindcss').Config} */
module.exports = {
  // Follow the macOS system appearance automatically. Theme colours are CSS
  // variables that flip in globals.css via `@media (prefers-color-scheme: dark)`,
  // and `darkMode: 'media'` makes `dark:` variants fire under the same signal.
  darkMode: 'media',
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        // ── Ember semantic palette (→ CSS vars in globals.css) ──────────────
        // surfaces
        canvas: 'var(--bg)',
        surface: 'var(--surface)',
        elevated: 'var(--surface-2)',
        // hairlines
        line: {
          DEFAULT: 'var(--border)',
          strong: 'var(--border-strong)',
        },
        // text / foreground
        fg: {
          DEFAULT: 'var(--text)',
          muted: 'var(--text-2)',
          faint: 'var(--text-3)',
        },
        // accent (ember)
        accent: {
          DEFAULT: 'var(--accent)',
          weak: 'var(--accent-weak)',
          text: 'var(--accent-text)',
          foreground: '#ffffff',
        },
        // status
        rec: 'var(--rec)',
        good: 'var(--good)',
        warn: 'var(--warn)',

        // ── shadcn semantic tokens (used by ui/* primitives) ────────────────
        background: 'var(--background)',
        foreground: 'var(--foreground)',
        border: 'var(--border)',
        input: 'var(--input)',
        ring: 'var(--ring)',
        card: {
          DEFAULT: 'var(--card)',
          foreground: 'var(--card-foreground)',
        },
        popover: {
          DEFAULT: 'var(--popover)',
          foreground: 'var(--popover-foreground)',
        },
        muted: {
          DEFAULT: 'var(--muted)',
          foreground: 'var(--muted-foreground)',
        },
        primary: {
          DEFAULT: 'var(--primary)',
          foreground: 'var(--primary-foreground)',
        },
        secondary: {
          DEFAULT: 'var(--secondary)',
          foreground: 'var(--secondary-foreground)',
        },
        destructive: {
          DEFAULT: 'var(--destructive)',
          foreground: 'var(--destructive-foreground)',
        },
      },
      fontFamily: {
        // Geist — self-hosted via the `geist` package (offline-friendly).
        sans: [
          'var(--font-geist-sans)',
          '-apple-system',
          'BlinkMacSystemFont',
          'system-ui',
          'sans-serif',
        ],
        mono: [
          'var(--font-geist-mono)',
          'ui-monospace',
          'SFMono-Regular',
          'monospace',
        ],
      },
      // One strict type scale tuned to the Ember spec (Geist).
      fontSize: {
        'xs': ['11px', { lineHeight: '1.45', letterSpacing: '0' }],
        'sm': ['13px', { lineHeight: '1.5', letterSpacing: '0' }],
        'base': ['14px', { lineHeight: '1.6', letterSpacing: '0' }],
        'lg': ['15px', { lineHeight: '1.55', letterSpacing: '-0.005em' }],
        'xl': ['20px', { lineHeight: '1.3', letterSpacing: '-0.01em' }],
        '2xl': ['23px', { lineHeight: '1.25', letterSpacing: '-0.02em' }],
        '3xl': ['28px', { lineHeight: '1.15', letterSpacing: '-0.02em' }],
        'caption': ['12px', { lineHeight: '1.4', letterSpacing: '0' }],
        'small': ['13px', { lineHeight: '1.5', letterSpacing: '0' }],
        'body': ['14px', { lineHeight: '1.6', letterSpacing: '0' }],
        'h2': ['17px', { lineHeight: '1.4', fontWeight: '600', letterSpacing: '-0.01em' }],
        'h1': ['23px', { lineHeight: '1.25', fontWeight: '600', letterSpacing: '-0.02em' }],
        'display': ['36px', { lineHeight: '1.1', fontWeight: '300', letterSpacing: '-0.02em' }],
      },
      borderRadius: {
        lg: 'var(--r-lg)',
        md: 'var(--r)',
        sm: 'var(--r-sm)',
        xl: 'var(--r-lg)',
      },
      boxShadow: {
        soft: '0 1px 2px rgba(0,0,0,0.04), 0 4px 16px rgba(0,0,0,0.04)',
        pop: '0 8px 28px rgba(0,0,0,0.12), 0 1px 3px rgba(0,0,0,0.06)',
        ember: 'var(--shadow)',
        glow: '0 10px 30px rgba(249,115,22,0.40)',
      },
      keyframes: {
        'accordion-down': {
          from: { height: '0' },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: '0' },
        },
      },
      animation: {
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
      },
    },
  },
  plugins: [require('tailwindcss-animate'), require('@tailwindcss/typography')],
}
