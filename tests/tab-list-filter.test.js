// SPDX-License-Identifier: GPL-3.0-or-later
//
// Unit tests for tabListFilter.js — run with:
//
//     make test
//     # or: gjs --module tests/tab-list-filter.test.js
//
// No GNOME session and no display needed: the tab list is mocked with the exact
// shape mutter produces, i.e. the windows of the requested workspace plus the
// demands-attention windows it prepends from other workspaces.

import System from 'system';

import {makeWorkspaceStrict} from '../tabListFilter.js';

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

// --- fixtures ---------------------------------------------------------------

const ws1 = {name: 'ws1'};
const ws2 = {name: 'ws2'};
const ws3 = {name: 'ws3'};

function window(name, workspaces, {attention = false} = {}) {
    return {
        name,
        demandsAttention: attention,
        located_on_workspace: ws => workspaces.includes(ws),
    };
}

const w1 = window('terminal@ws1', [ws1]);
const w1b = window('files@ws1', [ws1]);
const w2 = window('thunderbird@ws2', [ws2]);
const w2attention = window('chat@ws2 (wants attention)', [ws2], {attention: true});
const w3attention = window('steam@ws3 (wants attention)', [ws3], {attention: true});
const sticky = window('sticky@everywhere', [ws1, ws2, ws3]);

// A stand-in for meta_display_get_tab_list(): workspace MRU list, then the
// demands-attention windows from other workspaces prepended (mutters order:
// injected first, then the workspace's own windows).
function makeStockTabList(allWindows, byWorkspace) {
    return function get_tab_list(type, workspace) {
        this.lastType = type;

        if (!workspace)
            return allWindows.slice();

        const injected = allWindows.filter(
            w => w.demandsAttention && !w.located_on_workspace(workspace));

        return [...injected, ...byWorkspace[workspace.name]];
    };
}

const allWindows = [w1, w1b, w2, w2attention, w3attention, sticky];
const byWorkspace = {
    ws1: [w1b, w1, sticky],
    ws2: [w2attention, w2, sticky],
    ws3: [w3attention, sticky],
};

const stock = makeStockTabList(allWindows, byWorkspace);
const strict = makeWorkspaceStrict(stock);
const fakeDisplay = {};

// --- the tests --------------------------------------------------------------

// Sanity check: the stock behaviour really does leak other workspaces
// (this is the bug the extension exists for).
eq(stock.call(fakeDisplay, 0, ws1).map(w => w.name),
    ['chat@ws2 (wants attention)', 'steam@ws3 (wants attention)', 'files@ws1', 'terminal@ws1', 'sticky@everywhere'],
    'stock mutter: ws1 list contains the windows demanding attention on ws2 and ws3');

// And the extension removes exactly those.
eq(strict.call(fakeDisplay, 0, ws1).map(w => w.name),
    ['files@ws1', 'terminal@ws1', 'sticky@everywhere'],
    'strict: ws1 list has no ws2 window, keeps ws1 windows and sticky windows');

eq(strict.call(fakeDisplay, 0, ws2).map(w => w.name),
    ['chat@ws2 (wants attention)', 'thunderbird@ws2', 'sticky@everywhere'],
    'strict: a window demanding attention still shows on its own workspace');

eq(strict.call(fakeDisplay, 0, ws3).map(w => w.name),
    ['steam@ws3 (wants attention)', 'sticky@everywhere'],
    'strict: same for a third workspace');

// "all workspaces" mode must be untouched, byte for byte.
const allList = stock.call(fakeDisplay, 0, null);
ok(allList.length === allWindows.length,
    'strict: "all workspaces" mode still lists every window');
ok(strict.call(fakeDisplay, 0, null) !== undefined &&
   JSON.stringify(strict.call(fakeDisplay, 0, null).map(w => w.name)) ===
   JSON.stringify(allList.map(w => w.name)),
    'strict: "all workspaces" mode results are unchanged');

// Returned list is a new array, order is preserved, arguments are forwarded.
const strictListWs1 = strict.call(fakeDisplay, 0, ws1);
ok(strictListWs1 !== stock.call(fakeDisplay, 0, ws1),
    'strict: returns a new array (the caller may sort/mutate it)');
ok(strict.call(fakeDisplay, 42, ws1) !== null && fakeDisplay.lastType === 42,
    'strict: forwards get_tab_list() arguments and `this` to the original');

// Chaining: wrapping an already wrapped implementation must keep both filters.
const twice = makeWorkspaceStrict(strict);
eq(twice.call(fakeDisplay, 0, ws1).map(w => w.name),
    ['files@ws1', 'terminal@ws1', 'sticky@everywhere'],
    'strict: chaining two wrappers is idempotent');

// Defensive: bad input should fail loudly, not silently disable the filter.
let threw = false;
try {
    makeWorkspaceStrict(null);
} catch (e) {
    threw = e instanceof TypeError;
}
ok(threw, 'strict: refuses to wrap a non-function');

// --- summary ----------------------------------------------------------------

if (failures > 0) {
    printerr(`${failures} test(s) failed`);
    System.exit(1);
}

print(`all tests passed`);
