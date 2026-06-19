import * as React from "react"
import { Slot } from "@radix-ui/react-slot"
import { cva, type VariantProps } from "class-variance-authority"

import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-[11px] text-[13.5px] font-medium transition-[background-color,color,border-color,box-shadow,opacity,transform] duration-150 ease-out active:scale-[0.98] focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 disabled:active:scale-100 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default:
          "bg-accent text-white shadow-glow hover:opacity-90",
        destructive:
          "bg-rec text-white shadow-soft hover:opacity-90",
        outline:
          "border border-line bg-elevated text-fg-muted shadow-soft hover:bg-fg/[0.04]",
        secondary:
          "bg-surface text-fg-muted hover:bg-fg/[0.06]",
        ghost: "text-fg-muted hover:bg-fg/[0.06]",
        link: "text-accent-text underline-offset-4 hover:underline",
        green: "bg-good text-white hover:opacity-90",
        blue: "bg-accent text-white hover:opacity-90",
        red: "bg-rec text-white hover:opacity-90",
        gray: "border border-line bg-surface text-fg-muted shadow-soft hover:bg-fg/[0.04]",
      },
      size: {
        default: "h-[38px] px-4 py-2",
        sm: "h-8 rounded-[8px] px-3 text-xs",
        lg: "h-11 px-6 text-[15px]",
        icon: "h-9 w-9",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button"
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    )
  }
)
Button.displayName = "Button"

export { Button, buttonVariants }
