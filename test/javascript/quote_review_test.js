const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const script = fs.readFileSync('app/assets/javascripts/quote_review.js', 'utf8');

function harness() {
  const events = {}, windowEvents = {}, requests = [], pushes = [], assigned = [];
  let current, responsePage, approveDiscard = true;
  const makeReview = (name) => {
    const heading = { textContent: name, focus() { this.focused = true; }, scrollIntoView(options) { this.scrollOptions = options; } };
    const detail = { heading, querySelector: () => heading, scrollIntoView() { this.scrolled = true; } };
    const selected = { after(drawer) { this.drawer = drawer; } };
    const source = { scrollTop: 0, querySelector: () => ({ getBoundingClientRect: () => ({top: 120}) }), getBoundingClientRect: () => ({top: 20}) };
    return {
      detail, selected, source, attributes: {},
      querySelector: (selector) => selector === '#line-detail' ? detail : selected,
      querySelectorAll: () => [source], contains: () => true,
      setAttribute(key, value) { this.attributes[key] = value; }, removeAttribute(key) { delete this.attributes[key]; },
      replaceWith(next) { current = next; }
    };
  };
  current = makeReview('Line 2');
  const next = makeReview('Line 3');
  const status = {textContent: ''};
  const summary = {replaceWith(nextSummary) { this.replaced = nextSummary; }};
  responsePage = {querySelector: (selector) => selector === '[data-review-root]' ? next : {fresh: true}};
  const location = {href: 'http://example.test/quotes/1?status=attention&line=2', origin: 'http://example.test', pathname: '/quotes/1', assign: (url) => assigned.push(url)};
  const document = {
    readyState: 'complete',
    querySelector: (selector) => selector === '[data-review-root]' ? current : selector === '.summary' ? summary : status,
    importNode: (node) => node,
    createElement: (name) => ({name, children: [], append(child) { this.children.push(child); }}),
    addEventListener: (name, fn) => { events[name] = fn; }
  };
  const context = {
    document, URL, AbortController,
    DOMParser: class { parseFromString() { return responsePage; } },
    fetch: async (url, options) => { requests.push({url, options}); return {ok: true, redirected: false, text: async () => '<html>response</html>'}; },
    window: {location, confirm: () => approveDiscard, getSelection: () => '', matchMedia: () => ({matches: true}),
      history: {pushState: (_, __, url) => { pushes.push(url); location.href = url; }},
      addEventListener: (name, fn) => { windowEvents[name] = fn; }}
  };
  vm.runInNewContext(script, context);
  const click = (extra = {}) => {
    const link = {href: 'http://example.test/quotes/1?status=attention&line=3', target: '', hasAttribute: () => false};
    const event = {button: 0, target: {closest: (selector) => selector === 'a[data-review-link]' ? link : null}, preventDefault() { this.prevented = true; }, ...extra};
    events.click(event);
    return event;
  };
  return {events, windowEvents, requests, pushes, assigned, next, status, summary, context, click,
    current: () => current, discard: (value) => { approveDiscard = value; }};
}
const flush = () => new Promise((resolve) => setImmediate(resolve));

test('line selection replaces detail and source together and puts detail directly beneath its row', async () => {
  const h = harness();
  assert.equal(h.current().selected.drawer.children[0].children[0], h.current().detail);
  assert.equal(h.click().prevented, true);
  await flush();
  assert.equal(h.requests.length, 1);
  assert.equal(h.requests[0].options.credentials, 'same-origin');
  assert.equal(h.current(), h.next);
  assert.equal(h.next.selected.drawer.children[0].children[0], h.next.detail);
  assert.equal(h.next.selected.drawer.children[0].colSpan, 6);
  assert.equal(h.next.detail.scrolled, undefined, 'A tall detail container must not determine the scroll position');
  assert.equal(h.next.detail.heading.scrollOptions.block, 'start');
  assert.equal(h.next.detail.heading.scrollOptions.behavior, 'instant');
  assert.equal(h.next.detail.heading.focused, true);
  assert.equal(h.next.source.scrollTop, 76);
  assert.match(h.status.textContent, /Line 3 opened.*highlights updated/);
  assert.equal(h.pushes.length, 1);
  assert.equal(h.assigned.length, 0);
  assert.equal(h.current().attributes['aria-busy'], undefined);
});

test('modified clicks retain native navigation and unsaved input can cancel enhanced navigation', async () => {
  const h = harness();
  assert.equal(h.click({ctrlKey: true}).prevented, undefined);
  h.events.input({target: {closest: () => ({})}});
  h.discard(false);
  h.click();
  await flush();
  assert.equal(h.requests.length, 0);
  let prevented = false;
  h.windowEvents.beforeunload({preventDefault: () => { prevented = true; }});
  assert.equal(prevented, true);
});

test('changes made during fetch are retained when the rep declines replacement', async () => {
  const h = harness();
  let release;
  h.context.fetch = () => new Promise((resolve) => { release = resolve; });
  h.click();
  h.events.change({target: {closest: () => ({})}});
  h.discard(false);
  release({ok: true, text: async () => 'page'});
  await flush();
  assert.notEqual(h.current(), h.next);
  assert.match(h.status.textContent, /Unsaved changes kept/);
  assert.equal(h.pushes.length, 0);
});

test('failed enhancement falls back to the ordinary line URL', async () => {
  const h = harness();
  h.context.fetch = async () => ({ok: false});
  h.click();
  await flush();
  assert.equal(h.assigned[0], 'http://example.test/quotes/1?status=attention&line=3');
});
