# LocalPort Registry Audit

## Source

Prototype reference repo: `/Users/workspace/LocalPort`

Reviewed file:

- `src/views/RegistryView.tsx`

## Observed Structure

### 1. Page split

- Root layout: left host list + right detail pane.
- Left host list width: `w-[260px]`.
- Left list background: `bg-slate-50/50`.
- Left list border: `border-r border-slate-200/60`.
- Right detail pane background: `bg-white`.

### 2. Left host list

- Section label row uses very small uppercase-ish title text with a plus icon on the right.
- Host rows are almost separator-free.
- Selected row uses:
  - light background `bg-black/[0.04]`
  - medium weight text
  - a thin blue accent bar on the far left
- Host rows have:
  - OS icon
  - host name
  - small status dot
- No explicit divider between rows; spacing and background carry the grouping.

### 3. Right host header

- Header uses a single bottom border only.
- Header content has generous left/right padding.
- Host icon is visually larger than the list icon.
- Metadata line is compact and low-contrast.
- Settings action is very light and sits far right.

### 4. Scrollable work area

- Scroll area background is not pure white; it uses `bg-[#FAFAFA]`.
- Internal sections are separated by vertical spacing (`gap-8`) rather than hard rules.

### 5. Presets section

- Section title is a tiny uppercase label.
- `新建预设` is a low-contrast text action, not a bordered button.
- Presets render as a lightweight vertical list with no surrounding card.
- Each preset shows:
  - small play icon
  - preset name
  - optional derived badge
  - indented child rules below
- Empty state is just one line of light italic text.
- No top+bottom frame lines, no repeated dividers.

### 6. Rules section toolbar

- `规则清单` title sits on the left.
- Filter, import SSH, and add rule live inside one compact toolbar cluster.
- The cluster uses a shared rounded container with tiny internal separators.

### 7. Rules section containers

- Running rules and stopped rules are rendered as separate rounded white cards.
- Card style:
  - white background
  - faint border
  - very light shadow
  - rounded-xl
- Card header has:
  - colored dot
  - state label and count
  - only one faint divider below
- Inside the card, row separation uses `divide-y divide-slate-100/80`, which is very light.

### 8. Registry rule rows

- Rule rows feel like compact list items inside a card, not table rows across the whole page.
- Each row has:
  - service glyph
  - service name + alias
  - ports detail
  - target info
  - actions aligned right
- The card absorbs most of the visual grouping; row-level lines stay subtle.

## Current RelayDock Drift To Correct

1. `RegistryPresetsSection` currently combines:
   - row `Divider()`
   - top/bottom `overlay` dividers
   This creates repeated framing and explains the visible double-line feeling under `启动预设`.

2. `RegistryRuleGroupBand` currently repeats the same pattern:
   - band header
   - row dividers
   - outer overlay top/bottom dividers
   This makes the rules area read like stacked bands instead of card-contained lists.

3. RelayDock right-side work area is mostly white-on-white. The prototype uses a faint gray work surface with white cards/lists on top, which creates hierarchy without extra lines.

4. RelayDock host list is narrower and more “data list” like. The prototype host list feels roomier and less ruled.

## Implementation Direction

- Shift grouping from repeated divider lines to:
  - spacing between sections
  - subtle gray work surface
  - one white rounded container for rule groups
- Keep `启动预设` as a lightweight list flow, not a boxed table band.
- Use shallow borders only where a container boundary is truly needed.
