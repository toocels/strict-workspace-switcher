// SPDX-License-Identifier: GPL-3.0-or-later
//
// Tests for the JavaScript that tools/demo-attention-window.sh hands to GNOME
// Shell — run with:
//
//     make test
//     # or: gjs --module tests/demo-script.test.js
//
// No GNOME session is needed: the shell (global.get_window_actors,
// global.workspace_manager) is mocked and GLib/Meta are stubbed, so nothing is
// really spawned and no mutter typelib has to be installed. The JS is read out
// of the script itself, so this test also fails if the two drift apart.

import GLib from 'gi://GLib';
import system from 'system';

let failures = 0;

function ok(condition, description) {
    if (condition) {
        print(`ok   - ${description}`);
    } else {
        failures++;
        print(`FAIL - ${description}`);
    }
}

function eq(actual, expected, description) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    ok(a === e, `${description} (expected ${e}, got ${a})`);
}

// --- the JS the script sends to the shell -----------------------------------

const scriptPath = import.meta.url
    .replace(/^file:\/\//, '')
    .replace(/\/tests\/[^/]+$/, '/tools/demo-attention-window.sh');

const [, bytes] = GLib.file_get_contents(scriptPath);
const script = new TextDecoder().decode(bytes);

function heredoc(name) {
    const lines = script.split('\n');
    const start = lines.findIndex(line => line.startsWith(`read -r -d '' ${name} <<'JS'`));
    if (start < 0)
        throw new Error(`${name}: heredoc not found in ${scriptPath}`);
    const end = lines.indexOf('JS', start);
    if (end < 0)
        throw new Error(`${name}: heredoc is never closed`);
    return lines.slice(start + 1, end).join('\n').trim();
}

const demoJs = heredoc('JS_DEMO')
    .replaceAll('__APP__', 'demo-app')
    .replaceAll('__APP_ID__', 'org.example.Demo');
const clearJs = heredoc('JS_CLEAR').replaceAll('__CLOSE__', 'no');
const closeJs = heredoc('JS_CLEAR').replaceAll('__CLOSE__', 'yes');

// The script passes each of these to `gdbus … Eval` as one single-quoted
// GVariant string, with newlines stripped: quotes, backslashes and //-comments
// would all be mangled on the way through. The list is read out of the script,
// so a new heredoc is checked too (and a renamed one is noticed here).
const heredocNames = [...script.matchAll(/^read -r -d '' (\w+) <<'JS'/gm)].map(m => m[1]);

for (const name of ['JS_DEMO', 'JS_CLEAR', 'JS_STATUS'])
    ok(heredocNames.includes(name), `${name}: is one of the script's JS blocks`);

for (const name of heredocNames) {
    const js = heredoc(name);
    ok(js.length > 0, `${name}: found in the script`);
    ok(!js.includes("'"), `${name}: contains no single quotes (GVariant quoting)`);
    ok(!js.includes('\\'), `${name}: contains no backslashes (GVariant escaping)`);
    ok(!js.includes('//'), `${name}: contains no // comments (newlines are stripped)`);
}

// --- a fake shell -----------------------------------------------------------

function fakeWindow(log, {title = 'Mock Document', appId = 'org.example.Demo',
                         attention = false, sticky = false} = {}) {
    const win = {
        demands_attention: attention,
        get_title: () => title,
        get_gtk_application_id: () => appId,
        is_skip_taskbar: () => false,
        is_on_all_workspaces: () => sticky,
        get_window_type: () => 0, // Meta.WindowType.NORMAL
        located_on_workspace: () => false,
        change_workspace_by_index: (index, append) => log.push(`move to ${index} (append: ${append})`),
        activate: timestamp => {
            log.push(`activate(${timestamp})`);
            win.demands_attention = true; // what mutter does for a window elsewhere
        },
        unset_demands_attention: () => log.push('unset attention'),
        delete: timestamp => log.push(`delete(${timestamp})`),
    };
    return win;
}

function fakeShell({spawnOpensAWindow = true, windows = [], activeIndex = 0,
                    workspaceCount = 3} = {}) {
    const log = [];
    const onDesktop = windows.map(options => fakeWindow(log, options));
    let actors = onDesktop.map(meta_window => ({meta_window}));
    const opened = fakeWindow(log);

    const spawn_command_line_async = command => {
        log.push(`spawn(${command})`);
        if (spawnOpensAWindow)
            actors = [...actors, {meta_window: opened}];
    };

    const global_ = {
        // global.get_window_actors() is the shell's list of window actors -
        // Meta.Display has no such method any more.
        get_window_actors: () => actors,
        workspace_manager: {
            get_active_workspace: () => ({index: () => activeIndex}),
            n_workspaces: workspaceCount,
        },
        get_current_time: () => 42,
    };

    return {log, global: global_, opened, spawn_command_line_async};
}

// Runs the script's JS against that fake shell. GLib's timers are answered
// immediately (the script's waits become plain microtasks: no main loop, no
// real delay, nothing really spawned), and GLib/Meta are stubs, so no mutter
// typelib is needed either.
async function runInFakeShell(js, {global: global_, spawn_command_line_async}) {
    const imports = {
        gi: {
            GLib: {
                PRIORITY_DEFAULT: GLib.PRIORITY_DEFAULT,
                SOURCE_REMOVE: GLib.SOURCE_REMOVE,
                timeout_add: (priority, ms, callback) => {
                    callback();
                    return GLib.SOURCE_REMOVE;
                },
                spawn_command_line_async,
            },
            Meta: {WindowType: {NORMAL: 0}},
        },
    };

    const previous = globalThis.global;
    globalThis.global = global_;

    try {
        const fn = new Function('imports', `return (${js});`);

        let settled = false;
        let value = null;
        let error = null;
        fn(imports).then(result => {
            settled = true;
            value = result;
        }, reason => {
            settled = true;
            error = reason;
        });

        // Let the microtask chain run itself out. One yield per step is enough
        // in practice, and a stuck one is reported instead of hanging the suite.
        for (let i = 0; i < 1000 && !settled; i++)
            await Promise.resolve();

        if (!settled)
            throw new Error('the script\'s JS did not finish');
        if (error)
            throw error;

        return value;
    } finally {
        globalThis.global = previous;
    }
}

// --- JS_DEMO: open a window, move it away, flag it ---------------------------

{
    const shell = fakeShell();
    const result = await runInFakeShell(demoJs, shell);

    ok(result.startsWith('window "Mock Document" - you are on workspace 1, ' +
                         'it is on workspace 2, demands_attention=true'),
        `demo: reports the window, both workspaces and the flag (got ${JSON.stringify(result)})`);
    eq(shell.log, ['spawn(demo-app)', 'move to 1 (append: true)', 'activate(0)'],
        'demo: opens the app, moves the new window to the other workspace, asks for attention');
}

{
    // already on workspace 3, and the app reuses the window it had
    const shell = fakeShell({spawnOpensAWindow: false, windows: [{title: 'Existing Document'}],
                             activeIndex: 2, workspaceCount: 3});
    const result = await runInFakeShell(demoJs, shell);

    ok(result.includes('you are on workspace 3, it is on workspace 1'),
        `demo: picks the other workspace whichever one you are on (got ${JSON.stringify(result)})`);
    eq(shell.log, ['spawn(demo-app)', 'move to 0 (append: true)', 'activate(0)'],
        'demo: falls back to the window the app already had open');
}

{
    // last workspace: there is no other one yet, so append has to create it
    const shell = fakeShell({activeIndex: 0, workspaceCount: 1});
    await runInFakeShell(demoJs, shell);

    eq(shell.log, ['spawn(demo-app)', 'move to 1 (append: true)', 'activate(0)'],
        'demo: makes a second workspace when there is only one');
}

{
    // the app never opens anything (bad --app, or the app crashed)
    const shell = fakeShell({spawnOpensAWindow: false});
    const result = await runInFakeShell(demoJs, shell);

    eq(result, 'the app did not open a window - try --app with another app',
        'demo: says so instead of throwing when no window appears');
    eq(shell.log, ['spawn(demo-app)'], 'demo: touches no window in that case');
}

// --- JS_CLEAR: drop the flag, bring the window back --------------------------

{
    const shell = fakeShell({windows: [{title: 'Flagged Window', attention: true}]});
    const result = await runInFakeShell(clearJs, shell);

    eq(result, 'undone for: Flagged Window', 'clear: names the window it fixed');
    eq(shell.log, ['unset attention', 'move to 0 (append: true)'],
        'clear: drops the flag and brings it back, without closing it');
}

{
    const shell = fakeShell({windows: [{attention: true}]});
    await runInFakeShell(closeJs, shell);

    eq(shell.log, ['unset attention', 'move to 0 (append: true)', 'delete(42)'],
        'clear --close: also closes the window it flagged');
}

{
    // nothing to do: no window elsewhere is demanding attention
    const shell = fakeShell({windows: [{attention: false}]});
    const result = await runInFakeShell(clearJs, shell);

    eq(result, 'nothing to undo - no window on another workspace demands attention',
        'clear: says there is nothing to undo');
}

// --- summary ----------------------------------------------------------------

if (failures > 0) {
    printerr(`${failures} test(s) failed`);
    system.exit(1);
}

print(`all tests passed`);
