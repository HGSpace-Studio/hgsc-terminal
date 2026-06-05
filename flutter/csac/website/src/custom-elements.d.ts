import type React from 'react';

type MaterialElementProps = React.DetailedHTMLProps<
  React.HTMLAttributes<HTMLElement>,
  HTMLElement
> & {
  href?: string;
  target?: string;
  rel?: string;
  label?: string;
  value?: string;
  selected?: boolean;
  elevated?: boolean;
  disabled?: boolean;
};

declare module 'react/jsx-runtime' {
  namespace JSX {
    interface IntrinsicElements {
      'md-assist-chip': MaterialElementProps;
      'md-filled-button': MaterialElementProps;
      'md-elevated-button': MaterialElementProps;
      'md-filter-chip': MaterialElementProps;
      'md-icon': MaterialElementProps;
      'md-outlined-button': MaterialElementProps;
      'md-outlined-card': MaterialElementProps;
      'md-suggestion-chip': MaterialElementProps;
    }
  }
}
