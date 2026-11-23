// herdr-agent-mode: opencode's agent (Build, Plan, ...) as the $mode / $mode_label pane tokens.
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
// under. With no session open (the home screen) there is no agent to report and the tokens are
// cleared.
//
// Reporting goes through bin/publish, the same lib.sh code the Claude hook uses, so the glyph table,
// the token names and the sequence rule exist once. It runs only when the agent changes. Every
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

// publish(agent) resolves when the report has been made. bin/publish takes its sequence number when
// it runs, so reports go one at a time: two in flight could land in the wrong order.
function publish(agent, options = {}) {
  return new Promise((resolve) => {
    if (!publishPath) return resolve();
    const child = spawn(publishPath, agent ? [agent] : [], { stdio: "ignore", ...options });
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

  let last;
  let chain = Promise.resolve();

  function sync() {
    let agent;
    try {
      const route = api.ui.router.current();
      if (route.type === "session") agent = api.data.session.get(route.sessionID)?.agent;
    } catch {
      return;
    }
    if (agent === last) return;
    last = agent;
    chain = chain.then(() => publish(agent));
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
    if (last !== undefined) publish(undefined, { detached: true });
  };
}

// opencode 2.x calls setup(api). Keep the object plain, as herdr's integration does.
export default { id: ID, setup };
