// Firstmate Calm's OMP-native presentation toggle.
//
// OMP exposes tool-output expansion and the working-message presentation, but no
// supported transcript-wide renderer. Calm therefore uses only those public seams;
// it never changes messages, model input, tool execution, or session entries.
import { randomUUID } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";

type CalmUI = Pick<ExtensionContext["ui"], "getToolsExpanded" | "setToolsExpanded" | "setWorkingMessage">;

type AgentEndEvent = {
  willContinue?: boolean;
};

const extensionFile = fileURLToPath(import.meta.url);
const root = resolve(dirname(extensionFile), "../..");
const fmHome = process.env.FM_HOME || process.env.FM_ROOT_OVERRIDE || root;
const configDirectory = process.env.FM_CONFIG_OVERRIDE || resolve(fmHome, "config");
const calmPreferencePath = resolve(configDirectory, "calm");

function loadCalmPreference(): boolean {
  try {
    return readFileSync(calmPreferencePath, "utf8").trim() === "on";
  } catch {
    return false;
  }
}

function persistCalmPreference(active: boolean): void {
  mkdirSync(dirname(calmPreferencePath), { recursive: true });
  const temporaryPath = `${calmPreferencePath}.${process.pid}.${randomUUID()}.tmp`;
  try {
    writeFileSync(temporaryPath, active ? "on\n" : "off\n", {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
    renameSync(temporaryPath, calmPreferencePath);
  } finally {
    rmSync(temporaryPath, { force: true });
  }
}

export default function (omp: ExtensionAPI) {
  let calmActive = false;
  let agentRunActive = false;
  let savedToolsExpanded: boolean | undefined;

  const restorePresentation = (ui: CalmUI): void => {
    if (savedToolsExpanded !== undefined) {
      ui.setToolsExpanded(savedToolsExpanded);
      savedToolsExpanded = undefined;
    }
    ui.setWorkingMessage(undefined);
  };

  const applyPresentation = (ui: CalmUI): void => {
    if (savedToolsExpanded === undefined) {
      // Restore the user's expansion choice when Calm is disabled instead of
      // making a presentation preference permanently alter the next session.
      savedToolsExpanded = ui.getToolsExpanded();
    }
    ui.setToolsExpanded(false);
    if (agentRunActive) ui.setWorkingMessage("Working");
  };

  const startSession = (ctx: ExtensionContext): void => {
    calmActive = loadCalmPreference();
    agentRunActive = false;
    savedToolsExpanded = undefined;
    if (calmActive) applyPresentation(ctx.ui);
  };

  omp.on("session_start", (_event, ctx) => {
    startSession(ctx);
  });

  omp.on("session_switch", (_event, ctx) => {
    if (calmActive) restorePresentation(ctx.ui);
    startSession(ctx);
  });

  omp.on("agent_start", (_event, ctx) => {
    agentRunActive = true;
    if (calmActive) ctx.ui.setWorkingMessage("Working");
  });

  omp.on("agent_end", (event: AgentEndEvent, ctx) => {
    if (event.willContinue === true) return;
    agentRunActive = false;
    if (calmActive) ctx.ui.setWorkingMessage(undefined);
  });

  omp.on("session_shutdown", (_event, ctx) => {
    if (calmActive) restorePresentation(ctx.ui);
    calmActive = false;
    agentRunActive = false;
  });

  omp.registerCommand("calm", {
    description: "Toggle Firstmate Calm's supported OMP presentation.",
    handler: async (_args, ctx) => {
      const next = !calmActive;
      // Persistence precedes live presentation so a failed write cannot claim
      // a choice that the next OMP session would not restore.
      persistCalmPreference(next);
      calmActive = next;
      if (calmActive) applyPresentation(ctx.ui);
      else restorePresentation(ctx.ui);
    },
  });
}
