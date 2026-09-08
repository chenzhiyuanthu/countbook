/**
 * The whole icon set, drawn by hand. There is no icon library, no icon font and
 * no network request in this product, so every glyph in the app is one of the
 * fourteen below (DESIGN.md §8.3) and a fifteenth needs an amendment to that
 * document, not a new file here.
 *
 * Construction (DESIGN.md §8.2): a 24 grid with a 20 live area, stroke 1.5,
 * butt caps, mitred joins, every coordinate on the 0.5 grid so the stroke lands
 * on pixel boundaries at 1×. Colour is never set — an icon takes the ink of
 * whatever it sits in.
 */

const VIEW_BOX = '0 0 24 24'

// Geometry constants, not style: they belong to the drawing, which is why they
// are here rather than in tokens.css. See DESIGN.md §8.2.
const STROKE = 1.5
const DOT = 2

/** Optical size in row and header contexts; the keypad asks for 24. */
const SIZE = 20

export interface IconProps {
  size?: number
}

export type IconName =
  | 'chevron.right'
  | 'chevron.left'
  | 'chevron.up'
  | 'chevron.down'
  | 'xmark'
  | 'delete.backward'
  | 'magnifyingglass'
  | 'checkmark'
  | 'ellipsis'
  | 'plus'
  | 'minus'
  | 'tray.arrow.down'
  | 'square.and.arrow.up'
  | 'exclamationmark'

interface Drawing {
  /** Path data, stroked at 1.5 and never filled. */
  readonly stroke?: readonly string[]
  /** The only filled marks in the set: the ellipsis dots and the ! point. */
  readonly dots?: readonly { readonly x: number; readonly y: number }[]
}

const DRAWINGS: Record<IconName, Drawing> = {
  'chevron.right': { stroke: ['M9 5 L15.5 12 L9 19'] },
  'chevron.left': { stroke: ['M15 5 L8.5 12 L15 19'] },
  'chevron.up': { stroke: ['M5 15 L12 8.5 L19 15'] },
  'chevron.down': { stroke: ['M5 9 L12 15.5 L19 9'] },
  xmark: { stroke: ['M6 6 L18 18', 'M18 6 L6 18'] },
  'delete.backward': {
    stroke: ['M9 4 H21 V20 H9 L3 12 Z', 'M12 9 L17 15', 'M17 9 L12 15'],
  },
  magnifyingglass: {
    stroke: ['M17 10.5 A6.5 6.5 0 1 1 4 10.5 A6.5 6.5 0 1 1 17 10.5 Z', 'M15.2 15.2 L20 20'],
  },
  checkmark: { stroke: ['M5 12.5 L10 17.5 L19.5 6.5'] },
  ellipsis: { dots: [{ x: 5.5, y: 11 }, { x: 11, y: 11 }, { x: 16.5, y: 11 }] },
  plus: { stroke: ['M12 5 L12 19', 'M5 12 L19 12'] },
  minus: { stroke: ['M5 12 L19 12'] },
  'tray.arrow.down': {
    stroke: ['M4 14 V19 H20 V14', 'M12 5 L12 14', 'M8.5 10.5 L12 14 L15.5 10.5'],
  },
  'square.and.arrow.up': {
    stroke: ['M5 10 V20 H19 V10', 'M12 16 L12 4', 'M8.5 7.5 L12 4 L15.5 7.5'],
  },
  exclamationmark: { stroke: ['M12 5 L12 14.5'], dots: [{ x: 11, y: 17.5 }] },
}

export function Icon({ name, size = SIZE }: IconProps & { name: IconName }) {
  const drawing = DRAWINGS[name]
  return (
    <svg
      width={size}
      height={size}
      viewBox={VIEW_BOX}
      aria-hidden="true"
      focusable="false"
      style={{ display: 'block' }}
    >
      {drawing.stroke?.map((d) => (
        <path
          key={d}
          d={d}
          fill="none"
          stroke="currentColor"
          strokeWidth={STROKE}
          strokeLinecap="butt"
          strokeLinejoin="miter"
          strokeMiterlimit={4}
        />
      ))}
      {drawing.dots?.map((dot) => (
        <rect key={`${dot.x}-${dot.y}`} x={dot.x} y={dot.y} width={DOT} height={DOT} fill="currentColor" />
      ))}
    </svg>
  )
}

export const ChevronRight = ({ size }: IconProps) => <Icon name="chevron.right" size={size} />
export const ChevronLeft = ({ size }: IconProps) => <Icon name="chevron.left" size={size} />
export const ChevronUp = ({ size }: IconProps) => <Icon name="chevron.up" size={size} />
export const ChevronDown = ({ size }: IconProps) => <Icon name="chevron.down" size={size} />
export const XMark = ({ size }: IconProps) => <Icon name="xmark" size={size} />
export const DeleteBackward = ({ size }: IconProps) => <Icon name="delete.backward" size={size} />
export const MagnifyingGlass = ({ size }: IconProps) => <Icon name="magnifyingglass" size={size} />
export const Checkmark = ({ size }: IconProps) => <Icon name="checkmark" size={size} />
export const Ellipsis = ({ size }: IconProps) => <Icon name="ellipsis" size={size} />
export const Plus = ({ size }: IconProps) => <Icon name="plus" size={size} />
export const Minus = ({ size }: IconProps) => <Icon name="minus" size={size} />
export const TrayArrowDown = ({ size }: IconProps) => <Icon name="tray.arrow.down" size={size} />
export const SquareAndArrowUp = ({ size }: IconProps) => <Icon name="square.and.arrow.up" size={size} />
export const ExclamationMark = ({ size }: IconProps) => <Icon name="exclamationmark" size={size} />
