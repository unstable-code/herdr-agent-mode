// herdr-agent-mode: opencode's agent (Build, Plan, ...) as the $mode / $mode_label pane tokens, and
// its model as $model.
//
// This is an opencode 2.x TUI plugin. The install action registers this directory in opencode's
// cli.json "plugins" list — through a link in the herdr plugin's state directory, so an update that
// moves the installation does not leave a dead path behind (see bin/lib.sh).
//
// Why the TUI and not a server hook such as chat.message: in the full TUI the server may be shared
// or run in a worker that cannot tell which pane it serves. herdr's own opencode integration makes
// the same split and reports from its TUI plugin.
//
// The agent comes from the selected session (api.data.session.get(id).agent). opencode records the
// agent when a message is sent, not when shift+tab cycles it, and the TUI plugin API does not expose
// the prompt's own selection — so, as with Claude, the sidebar shows what the last message ran
// under. The model comes from the same session (.model.id) and follows the same rule; the prompt's
// own model selection is readable, but showing it beside an agent that lags would describe a pairing
// no message ran under. With no session open (the home screen) there is nothing to report and the
// tokens are cleared.
//
// Reporting goes through bin/publish, the same lib.sh code the Claude hook uses, so the glyph table,
// the token names and the sequence rule exist once. It runs only when the agent or model changes. Every
// failure is silent: outside herdr, a missing script, an API this opencode does not have.

import { spawn } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ID = "unstable-code.herdr-agent-mode";
// The route has no change event; herdr's integration polls it at the same rate.
const POLL_MS = 200;

// This file's real location, not the state-directory link it was loaded through: bin/ sits next to
// opencode/ in the installation, while the state directory has a bin link only where Claude hooks
// are installed too.
let publishPath;
try {
  publishPath = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "..", "bin", "publish");
} catch {}

// publish(agent, model) resolves when the report has been made; an empty field clears its tokens.
// bin/publish takes its sequence number when it runs, so reports go one at a time: two in flight
// could land in the wrong order.
function publish(agent, model, options = {}) {
  return new Promise((resolve) => {
    if (!publishPath) return resolve();
    const child = spawn(publishPath, [agent, model], { stdio: "ignore", ...options });
    child.on("error", resolve);
    child.on("exit", resolve);
    if (options.detached) {
      child.unref();
      resolve();
    }
  });
}

function setup(api) {
  if (process.env.HERDR_ENV !== "1" || !process.env.HERDR_PANE_ID) return;

  // What was last published. Empty is what a fresh pane shows, so the home screen publishes nothing.
  let lastAgent = "";
  let lastModel = "";
  let chain = Promise.resolve();

  function sync() {
    let agent = "";
    let model = "";
    try {
      const route = api.ui.router.current();
      if (route.type === "session") {
        const session = api.data.session.get(route.sessionID);
        agent = session?.agent ?? "";
        model = session?.model?.id ?? "";
      }
    } catch {
      return;
    }
    if (agent === lastAgent && model === lastModel) return;
    lastAgent = agent;
    lastModel = model;
    chain = chain.then(() => publish(agent, model));
  }

  // Fires as the message that records a new agent is sent; the poll would catch it a moment later.
  const off = api.data.on("session.agent.selected", sync);
  const poll = setInterval(sync, POLL_MS);
  sync();

  return () => {
    clearInterval(poll);
    off();
    // The pane outlives opencode; a mode left behind would describe an agent that is gone. Detached,
    // because opencode may exit before the report finishes.
    if (lastAgent || lastModel) publish("", "", { detached: true });
  };
}

// opencode 2.x calls setup(api). Keep the object plain, as herdr's integration does.
export default { id: ID, setup };
