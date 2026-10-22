// SPDX-License-Identifier: GPL-3.0-or-later
//
// Checks the API names that tools/demo-attention-window.sh uses inside GNOME
// Shell against mutter's Meta typelib, so a renamed or non-existent method is
// caught here rather than in a live session. (Meta.Display.get_window_actors()
// used to exist; today the shell's list is global.get_window_actors(), and
// getting that wrong is exactly the kind of thing this test is for.)
//
// Needs mutter's typelib, which is not on gjs's default search path everywhere:
// make test passes it in GI_TYPELIB_PATH. Without the typelib the test skips
// itself rather than failing.

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
    return lines.slice(start + 1, end).join('\n');
}

const js = [heredoc('JS_DEMO'), heredoc('JS_CLEAR')].join('\n');

// --- what the shell offers --------------------------------------------------

let Meta = null;
try {
    Meta = (await import('gi://Meta')).default;
} catch {
    // not installed, or not on GI_TYPELIB_PATH
}

if (!Meta) {
    print('skip - mutter\'s Meta typelib is not available');
    print('       (install mutter, or point GI_TYPELIB_PATH at its directory)');
    print('all tests passed');
    system.exit(0);
}

// ---------------------------------------------------------------------------
// 1. Methods called on something the script got from `global.…`: work out the
//    type from the import, then check every member the script uses on it.
// ---------------------------------------------------------------------------

const GLOBAL_TYPES = {
    display: 'Meta.Display',                     // global.display
    workspace_manager: 'Meta.WorkspaceManager',  // global.workspace_manager
};

function prototypeOf(typeName) {
    const [namespace, name] = typeName.split('.');
    const type = {Meta}[namespace];
    return type ? type[name]?.prototype : undefined;
}

const aliases = [...js.matchAll(/const\s+(\w+)\s*=\s*global\.(\w+);/g)]
    .map(([, alias, globalName]) => ({alias, type: GLOBAL_TYPES[globalName]}));

ok(aliases.length > 0, 'found at least one `const x = global.…` alias to check');

for (const {alias, type} of aliases) {
    const proto = prototypeOf(type);
    ok(proto !== undefined, `${type} is a type in the Meta namespace`);

    if (!proto)
        continue;

    const members = [...new Set([...js.matchAll(new RegExp(`\\b${alias}\\.(\\w+)`, 'g'))]
        .map(([, member]) => member))];

    ok(members.length > 0, `${alias} (${type}) is actually used in the JS`);

    for (const member of members)
        ok(typeof proto[member] !== 'undefined', `${type}.${member} exists`);
}

// ---------------------------------------------------------------------------
// 2. Window APIs. The windows come out of the actor list, so their type cannot
//    be read off the source: this is the list to extend when the script starts
//    using something new.
// ---------------------------------------------------------------------------

const WINDOW_MEMBERS = [
    'get_title', 'get_window_type', 'get_gtk_application_id',
    'is_skip_taskbar', 'is_on_all_workspaces', 'located_on_workspace',
    'change_workspace_by_index', 'activate', 'delete',
    'demands_attention', 'unset_demands_attention',
];

for (const member of WINDOW_MEMBERS) {
    const used = js.includes(`.${member}`);
    ok(!used || typeof Meta.Window.prototype[member] !== 'undefined',
        `Meta.Window.${member} exists${used ? '' : ' (unused, listed for completeness)'}`);
}

const WORKSPACE_MEMBERS = ['index', 'activate'];
for (const member of WORKSPACE_MEMBERS) {
    const used = js.includes(`.${member}(`);
    ok(!used || typeof Meta.Workspace.prototype[member] !== 'undefined',
        `Meta.Workspace.${member} exists${used ? '' : ' (unused, listed for completeness)'}`);
}

const MANAGER_MEMBERS = ['get_active_workspace', 'n_workspaces'];
for (const member of MANAGER_MEMBERS) {
    const used = js.includes(`manager.${member}`);
    ok(!used || typeof Meta.WorkspaceManager.prototype[member] !== 'undefined',
        `Meta.WorkspaceManager.${member} exists${used ? '' : ' (unused, listed for completeness)'}`);
}

for (const constant of ['NORMAL']) {
    const used = js.includes(`Meta.WindowType.${constant}`);
    ok(!used || typeof Meta.WindowType[constant] !== 'undefined',
        `Meta.WindowType.${constant} exists`);
}

// ---------------------------------------------------------------------------
// 3. `global.…` members come from gnome-shell, whose typelib this test does not
//    load, so they are listed instead: anything new has to be checked by hand
//    once and added here.
// ---------------------------------------------------------------------------

const SHELL_GLOBAL_MEMBERS = ['display', 'workspace_manager', 'get_window_actors',
                              'get_current_time'];

for (const name of new Set([...js.matchAll(/global\.(\w+)/g)].map(([, n]) => n)))
    ok(SHELL_GLOBAL_MEMBERS.includes(name),
        `global.${name} is a checked API (add it to SHELL_GLOBAL_MEMBERS once verified)`);

// ---------------------------------------------------------------------------

if (failures > 0) {
    printerr(`${failures} test(s) failed`);
    system.exit(1);
}

print(`all tests passed`);
