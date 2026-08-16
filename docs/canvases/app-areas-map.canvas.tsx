import {
  Callout,
  H1,
  H2,
  Pill,
  Row,
  Stack,
  Text,
  computeDAGLayout,
  useCanvasState,
  useHostTheme,
  type Color,
} from "cursor/canvas";

type Area = {
  id: string;
  title: string;
  short: string;
  role: string;
  color: Color;
  side: "FE" | "FE+BE";
  owns: string;
  doesNot: string;
  includes: string[];
};

const AREAS: Area[] = [
  {
    id: "ux",
    title: "UX",
    short: "Flow & shell",
    role: "What happens and where",
    color: "orange",
    side: "FE",
    owns: "Shell flow: chrome stays still; main pane swaps.",
    doesNot: "Does not invent visual tokens (those live in UI).",
    includes: [
      "Sections: topic canvas, task views, objects map, archive",
      "File layouts: single / split / large / row / grid",
      "Arrange mode + menus + shortcuts",
      "Insert-object catalog into the active file",
      "Desktop vs phone form factor",
    ],
  },
  {
    id: "ui",
    title: "UI",
    short: "Design patterns",
    role: "How things look",
    color: "pink",
    side: "FE",
    owns: "Visual style only: colors, type, spacing, glass, controls.",
    doesNot: "No flows, menu wiring, or business rules.",
    includes: [
      "Tokens: app_colors / app_typography",
      "Surface hierarchy & glass presets",
      "Topic colour washes; aiCyan for AI",
      "Dialogs, icons, RTL primitives",
      "Presentational widgets only",
    ],
  },
  {
    id: "editor",
    title: "Editor",
    short: "Files / document",
    role: "One continuous document",
    color: "blue",
    side: "FE+BE",
    owns: "Placement, marker text, Super Editor, in-file presentation.",
    doesNot: "Does not own task/view/info business logic.",
    includes: [
      "v4 marker text ↔ Super Editor",
      "Embeds as pointer nodes",
      "DocumentMark (selection or caret line)",
      "Editor text vs agent text",
      "Silent save + keyboard safety",
    ],
  },
  {
    id: "objects",
    title: "Objects",
    short: "Typed embeds",
    role: "Special embed types + tasks/views",
    color: "green",
    side: "FE+BE",
    owns: "Content, type logic, cascades.",
    doesNot: "Does not own caret/menu chrome rules.",
    includes: [
      "task_list, info, image, table (+ chart)",
      "Create id + pointer; delete cascades",
      "Tasks Active/Done; views = membership",
      "Info links graph + tags",
      "Shared create path with agent",
    ],
  },
  {
    id: "agent",
    title: "Agent",
    short: "Production AI",
    role: "In-app AI that reads/edits documents",
    color: "cyan",
    side: "FE+BE",
    owns: "Consult / tools / apply vs review.",
    doesNot: "Not the Cursor coding agent; no invented ids.",
    includes: [
      "Bolt + Consult; hints (file, selected_text)",
      "Tools: list / find / open / create / patch / rewrite",
      "Workspace-wide browse; agent text only",
      "apply_mode: direct / review / notify",
      "Review → accept apply-agent-text",
    ],
  },
  {
    id: "automations",
    title: "Automations",
    short: "Scheduled runs",
    role: "Saved agent runs on a schedule",
    color: "purple",
    side: "FE+BE",
    owns: "Config + triggers into the same agent pipeline.",
    doesNot: "Does not invent a second AI stack.",
    includes: [
      "Prompt, scope, apply_mode, schedule",
      "Run now / cron / bolt menu",
      "Results via presentAgentRunResult",
      "automation_runs history",
      "Disabled never auto-fires",
    ],
  },
];

const AREA_BY_ID = Object.fromEntries(AREAS.map((a) => [a.id, a])) as Record<
  string,
  Area
>;

const EDGES: Array<{ from: string; to: string; label: string }> = [
  { from: "ux", to: "ui", label: "styles" },
  { from: "ux", to: "editor", label: "places files" },
  { from: "ui", to: "editor", label: "paints" },
  { from: "editor", to: "objects", label: "embeds" },
  { from: "agent", to: "editor", label: "reads / writes" },
  { from: "automations", to: "agent", label: "runs" },
];

const NODE_W = 168;
const NODE_H = 88;

function edgePath(
  sx: number,
  sy: number,
  tx: number,
  ty: number,
  back: boolean,
): string {
  if (back) {
    const midY = (sy + ty) / 2;
    return `M ${sx} ${sy} C ${sx + 40} ${midY}, ${tx + 40} ${midY}, ${tx} ${ty}`;
  }
  const midY = (sy + ty) / 2;
  return `M ${sx} ${sy} C ${sx} ${midY}, ${tx} ${midY}, ${tx} ${ty}`;
}

function AreaFrame({
  area,
  x,
  y,
  active,
  onEnter,
  onLeave,
}: {
  area: Area;
  x: number;
  y: number;
  active: boolean;
  onEnter: () => void;
  onLeave: () => void;
}) {
  const theme = useHostTheme();
  const hue = theme.category[area.color];
  return (
    <div
      onMouseEnter={onEnter}
      onMouseLeave={onLeave}
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: NODE_W,
        height: NODE_H,
        boxSizing: "border-box",
        padding: "10px 12px",
        borderRadius: 10,
        border: `2px solid ${hue}`,
        background: active ? theme.fill.secondary : theme.fill.tertiary,
        cursor: "default",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 4,
      }}
    >
      <div
        style={{
          fontSize: 13,
          fontWeight: 600,
          color: theme.text.primary,
        }}
      >
        {area.title}
      </div>
      <div style={{ fontSize: 11, color: hue }}>{area.short}</div>
      <div style={{ fontSize: 10, color: theme.text.tertiary }}>{area.side}</div>
    </div>
  );
}

function HoverBubble({
  area,
  x,
  y,
  canvasW,
}: {
  area: Area;
  x: number;
  y: number;
  canvasW: number;
}) {
  const theme = useHostTheme();
  const hue = theme.category[area.color];
  const bubbleW = 320;
  let left = x + NODE_W + 16;
  if (left + bubbleW > canvasW - 8) {
    left = Math.max(8, x - bubbleW - 16);
  }
  let top = y;
  if (top + 280 > 520) {
    top = Math.max(8, 520 - 280);
  }

  return (
    <div
      style={{
        position: "absolute",
        left,
        top,
        width: bubbleW,
        zIndex: 20,
        boxSizing: "border-box",
        padding: 14,
        borderRadius: 12,
        border: `2px solid ${hue}`,
        background: theme.bg.elevated,
        pointerEvents: "none",
      }}
    >
      <Stack gap={8}>
        <Row gap={8} align="center" justify="space-between">
          <Text weight="semibold">{area.title}</Text>
          <Pill size="sm" tone="neutral">
            {area.side}
          </Pill>
        </Row>
        <Text size="small" tone="secondary">
          {area.role}
        </Text>
        <Text size="small">{area.owns}</Text>
        <Text size="small" tone="tertiary">
          {area.doesNot}
        </Text>
        <div
          style={{
            height: 1,
            background: theme.stroke.secondary,
            marginTop: 2,
            marginBottom: 2,
          }}
        />
        <Text size="small" weight="semibold" style={{ color: hue }}>
          Includes
        </Text>
        <Stack gap={4}>
          {area.includes.map((line) => (
            <div key={line}>
              <Text size="small">
                <span style={{ color: hue }}>• </span>
                {line}
              </Text>
            </div>
          ))}
        </Stack>
      </Stack>
    </div>
  );
}

function AreaDiagram() {
  const theme = useHostTheme();
  const [hovered, setHovered] = useCanvasState<string | null>(
    "hovered-area",
    null,
  );

  const layout = computeDAGLayout({
    nodes: AREAS.map((a) => ({ id: a.id })),
    edges: EDGES.map((e) => ({ from: e.from, to: e.to })),
    direction: "vertical",
    nodeWidth: NODE_W,
    nodeHeight: NODE_H,
    rankGap: 72,
    nodeGap: 48,
    padding: 28,
  });

  const pos = Object.fromEntries(
    layout.nodes.map((n) => [n.id, n]),
  ) as Record<string, (typeof layout.nodes)[number]>;

  const edgeLabels = Object.fromEntries(
    EDGES.map((e) => [`${e.from}->${e.to}`, e.label]),
  );

  const hoveredArea = hovered ? AREA_BY_ID[hovered] : null;
  const hoveredPos = hovered ? pos[hovered] : null;

  return (
    <div
      style={{
        position: "relative",
        width: layout.width,
        height: layout.height,
        background: theme.fill.quaternary,
        borderRadius: 12,
        border: `1px solid ${theme.stroke.secondary}`,
        overflow: "hidden",
      }}
    >
      <svg
        width={layout.width}
        height={layout.height}
        style={{ position: "absolute", inset: 0, pointerEvents: "none" }}
      >
        <defs>
          <marker
            id="arrowhead"
            markerWidth="8"
            markerHeight="8"
            refX="6"
            refY="3"
            orient="auto"
          >
            <path d="M0,0 L6,3 L0,6 Z" fill={theme.stroke.primary} />
          </marker>
        </defs>
        {layout.edges.map((edge) => {
          const key = `${edge.from}->${edge.to}`;
          const label = edgeLabels[key] ?? "";
          const midX = (edge.sourceX + edge.targetX) / 2;
          const midY = (edge.sourceY + edge.targetY) / 2;
          const accent =
            hovered === edge.from || hovered === edge.to
              ? theme.accent.primary
              : theme.stroke.primary;
          return (
            <g key={key}>
              <path
                d={edgePath(
                  edge.sourceX,
                  edge.sourceY,
                  edge.targetX,
                  edge.targetY,
                  edge.isBackEdge,
                )}
                fill="none"
                stroke={accent}
                strokeWidth={hovered === edge.from || hovered === edge.to ? 2 : 1.5}
                strokeDasharray={edge.isBackEdge ? "5 4" : undefined}
                markerEnd="url(#arrowhead)"
              />
              {label ? (
                <text
                  x={midX + 8}
                  y={midY}
                  fill={theme.text.tertiary}
                  fontSize={10}
                >
                  {label}
                </text>
              ) : null}
            </g>
          );
        })}
      </svg>

      {AREAS.map((area) => {
        const n = pos[area.id];
        if (!n) return null;
        return (
          <div key={area.id}>
            <AreaFrame
              area={area}
              x={n.x}
              y={n.y}
              active={hovered === area.id}
              onEnter={() => setHovered(area.id)}
              onLeave={() => setHovered(null)}
            />
          </div>
        );
      })}

      {hoveredArea && hoveredPos ? (
        <HoverBubble
          area={hoveredArea}
          x={hoveredPos.x}
          y={hoveredPos.y}
          canvasW={layout.width}
        />
      ) : null}
    </div>
  );
}

export default function AppAreasMap() {
  return (
    <Stack gap={20} style={{ padding: 24, maxWidth: 980 }}>
      <Stack gap={8}>
        <H1>System App — area map</H1>
        <Text tone="secondary">
          Colored frames with arrows. Hover a frame to open its detail bubble.
        </Text>
      </Stack>

      <Callout tone="info" title="Domain spine">
        Workspace → Topic → File → continuous text with embedded objects. Views
        are task membership; automations are saved agent runs.
      </Callout>

      <H2>Parts diagram</H2>
      <AreaDiagram />

      <Text size="small" tone="tertiary">
        Arrows: UX drives shell and asks UI to style; Editor hosts the document;
        Objects supply embeds; Agent reads/writes the editor; Automations call
        the agent. Paths: lib/areas/* (FE) and areas/* (BE). Each area has
        AREA.md.
      </Text>
    </Stack>
  );
}
