# LocalPort Style Audit

## Source

Local reference repo: `/Users/workspace/LocalPort`

Reviewed files:

- `src/App.tsx`
- `src/components/Sidebar.tsx`
- `src/components/TopBar.tsx`
- `src/views/ForwardsView.tsx`
- `src/components/OsIcon.tsx`
- `src/index.css`

## Shell Measurements From Prototype

### Window

- Main prototype window: `max-w-[1100px] h-[750px]`.
- Left sidebar: `w-[220px]`.
- Right pane: flex column with topbar, content, status bar.

### Sidebar

From `Sidebar.tsx`:

- Sidebar width: `w-[220px]`.
- Background: `bg-[#F6F6F7]/95`.
- Border: `border-r border-slate-200/60`.
- Traffic-light area: `h-[52px]`, `px-4`, `gap-2`, 12px colored circles.
- Nav wrapper: `px-3`, `gap-1`, `mt-2`.
- Group label: `text-[11px]`, semibold, slate-400, `px-2`, `mb-1.5`.
- Nav row: `gap-2.5`, `px-2.5`, `py-[5px]`, rounded-md, `text-[13px]`.
- Selected row: `bg-black/5 text-slate-900 font-medium`.
- Sidebar icons: lucide `Activity`, `Server`, `ScrollText`, `Settings`, `w-4 h-4`.
- System group top spacing: `mt-6`.

Swift mapping:

- Sidebar should be about 220pt wide.
- Traffic-light/titlebar spacer should be 52pt, not 58pt.
- Nav rows should be about 30pt high rather than fixed 24pt.
- Row spacing should be about 4pt.
- Label bottom spacing should be about 6pt.

### Top Bar

From `TopBar.tsx`:

- Topbar height: `h-[52px]`.
- Background: `bg-white/95 backdrop-blur-xl`.
- Border: `border-b border-slate-200/60`.
- Horizontal padding: `px-4`.
- Title section: icon + title with `gap-2`.
- Title font: `text-[13px] font-semibold`.
- Search width: `w-[300px]`.
- Search field: `bg-slate-100/80`, border slate-200/60, rounded-md, `pl-8 pr-12 py-[5px]`, `text-[12px]`.
- Action buttons: `gap-1.5`, `px-2.5`, `py-[5px]`, `text-[12px] font-medium`, transparent border by default, hover border/background.

Swift mapping:

- Keep topbar frame at 52pt, but ensure root layout and safe-area handling do not visually compress it.
- Search/control height should be approximately 26pt.
- Topbar content should be vertically centered with 16pt horizontal padding.
- Actions should be flat, text+small-icon, and visually subordinate except primary registry action.

### Run/Recovery Host Header

From `ForwardsView.tsx`:

- Host header: `px-4 py-2`, background `bg-slate-50/80`, border bottom, sticky.
- Host icon container: `w-7 h-7`, rounded-md, white, subtle border/shadow.
- OS icon: `w-3.5 h-3.5`.
- Host name: `text-[12px] font-medium`.
- Host metadata: `text-[11px] font-mono`, `mt-0.5`.
- Host actions: `text-[11px] font-medium`, buttons `px-2 py-1`.

Swift mapping:

- Current 44pt host header is close enough, but host icon should be 28pt and title weight should be medium, not visually heavy.
- Chevron belongs next to host title in prototype; Swift can keep left toggle if native, but visual weight must remain light.

### Run/Recovery Service Row

From `ForwardsView.tsx`:

- Row: `px-4 py-2 pl-[44px]`.
- Service icon slot: `w-7`, inner icon `w-5 h-5`.
- Fallback icon: `w-5 h-5 bg-slate-100 rounded-sm border border-slate-200/60`, uppercase first letter, `text-[10px] font-bold text-slate-400`.
- Service name: `text-[13px] font-medium`.
- Alias: mono `text-[11px]`.
- Provider label: `text-[10.5px]`, max `140px`, right aligned.
- Port text: `text-[11px]` mono with small `本地/远程` labels.
- Status and telemetry use fixed columns: status 64px, uptime 48px, latency 48px, errors 48px.
- Row actions: `text-[11px] font-medium`, `px-2 py-1`, icons `w-3.5 h-3.5`, stop last.

Swift mapping:

- Service rows should keep the existing two-line layout and stable columns.
- Service glyph should revert to the prototype fallback square-letter visual until bridge data supports favicon/repoIcon.
- Service title can increase to 13pt medium.
- Row actions should use smaller 11pt text and 14pt-ish symbols.

## Initial Drift List

1. `SidebarView` uses width 212pt, top spacer 58pt, row height 24pt, and zero row spacing. This makes the sidebar visibly more cramped than the prototype.
2. `RelayDockShellView` uses a 52pt topbar, but root safe-area ignoring plus sidebar 58pt spacer makes the top area visually inconsistent. The titlebar zone needs a consistent 52pt rhythm across sidebar and content.
3. `ServiceGlyph` currently chooses SF Symbols based on service names. The prototype's run/recovery row uses favicon/repoIcon when available and a simple 20px square-letter fallback otherwise. Without icon URLs in the bridge, Swift should use the fallback style rather than invented per-service symbols.
