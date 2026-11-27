import { createApp, h, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch, watchEffect } from 'vue'
import icon from "./icon.svg?raw"
import { basicSetup } from 'codemirror'
import { oneDark } from '@codemirror/theme-one-dark'
import MarBlockReader from '@/components/MarBlockReader'
import MarCode from '@/components/MarCode'
import MarEditorFrame from '@/components/MarEditorFrame'
import { useTheme } from '@/composables/useTheme'
import '@/assets/baseline.css'
import '@fontsource/roboto-mono/400.css'
import '@fontsource/roboto-mono/400-italic.css'
import '@fontsource/roboto-mono/500.css'
import '@fontsource/roboto-mono/700.css'
import { Compartment, EditorState, StateEffect, StateField } from '@codemirror/state'
import { HighlightStyle, LanguageDescription, StreamLanguage, foldAll, foldCode, syntaxHighlighting, unfoldAll, unfoldCode } from '@codemirror/language'
import { tags as t } from '@lezer/highlight'
import { languages } from '@codemirror/language-data'
import { MergeView, getChunks, getOriginalDoc, unifiedMergeView } from '@codemirror/merge'
import { Decoration, EditorView, GutterMarker, gutter, hoverTooltip, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import { copyLineDown, cursorMatchingBracket, deleteLine, indentSelection, insertBlankLine, moveLineDown, moveLineUp, selectParentSyntax, splitLine, toggleBlockComment, toggleComment } from '@codemirror/commands'
import { findNext, findPrevious, openSearchPanel, selectNextOccurrence, selectSelectionMatches } from '@codemirror/search'
import { nextDiagnostic, previousDiagnostic } from '@codemirror/lint'

const grown = new WeakMap()

function grow(v) {
  const stack = grown.get(v) || []
  const before = v.state.selection
  if (stack.length && !stack[stack.length - 1].after.eq(before)) stack.length = 0
  if (selectParentSyntax(v)) {
    stack.push({ before: before, after: v.state.selection })
    grown.set(v, stack)
  }
  return true
}

function shrink(v) {
  const stack = grown.get(v) || []
  const last = stack[stack.length - 1]
  if (!last || !last.after.eq(v.state.selection)) return true
  stack.pop()
  v.dispatch({ selection: last.before, userEvent: 'select' })
  return true
}

function join(v) {
  const doc = v.state.doc
  const range = v.state.selection.main
  const first = doc.lineAt(range.from)
  const last = doc.line(Math.min(doc.lines, Math.max(first.number + 1, doc.lineAt(range.to).number)))
  if (last.number === first.number) return true
  const text = doc.sliceString(first.from, last.to).split('\n').map(function (l, i) { return i ? l.trimStart() : l.trimEnd() }).join(' ')
  v.dispatch({ changes: { from: first.from, to: last.to, insert: text }, selection: { anchor: first.from + first.text.trimEnd().length }, userEvent: 'input' })
  return true
}

function recase(v) {
  v.dispatch(v.state.changeByRange(function (range) {
    const word = range.empty ? v.state.wordAt(range.head) : range
    if (!word) return { range: range }
    const text = v.state.sliceDoc(word.from, word.to)
    return { changes: { from: word.from, to: word.to, insert: text === text.toUpperCase() ? text.toLowerCase() : text.toUpperCase() }, range: range }
  }))
  return true
}

function above(v) {
  const line = v.state.doc.lineAt(v.state.selection.main.head)
  const indent = /^\s*/.exec(line.text)[0]
  v.dispatch({ changes: { from: line.from, insert: indent + '\n' }, selection: { anchor: line.from + indent.length }, userEvent: 'input' })
  return true
}

function block(forward, extend) {
  return function (v) {
    const text = v.state.doc.toString()
    const main = v.state.selection.main
    let depth = 0
    for (let at = forward ? main.head : main.head - 1; at >= 0 && at < text.length; at += forward ? 1 : -1) {
      if ((forward ? '([{' : ')]}').includes(text[at])) depth++
      if ((forward ? ')]}' : '([{').includes(text[at]) && depth-- === 0) {
        const to = forward ? at : at + 1
        v.dispatch({ selection: { anchor: extend ? main.anchor : to, head: to }, scrollIntoView: true, userEvent: 'select' })
        return true
      }
    }
    return true
  }
}

const keys = Prec.highest(keymap.of([
  { key: 'Mod-w', run: grow },
  { key: 'Shift-Mod-w', run: shrink },
  { key: 'Alt-ArrowUp', run: grow },
  { key: 'Alt-ArrowDown', run: shrink },
  { key: 'Mod-d', run: copyLineDown },
  { key: 'Mod-y', run: deleteLine },
  { key: 'Mod-Backspace', run: deleteLine },
  { key: 'Shift-Alt-ArrowUp', run: moveLineUp },
  { key: 'Shift-Alt-ArrowDown', run: moveLineDown },
  { key: 'Shift-Mod-ArrowUp', run: moveLineUp },
  { key: 'Shift-Mod-ArrowDown', run: moveLineDown },
  { key: 'Mod-/', run: toggleComment },
  { key: 'Alt-Mod-/', run: toggleBlockComment },
  { key: 'Shift-Enter', run: insertBlankLine },
  { key: 'Alt-Mod-Enter', run: above },
  { key: 'Mod-Enter', run: splitLine },
  { key: 'Ctrl-Shift-j', run: join },
  { key: 'Shift-Mod-u', run: recase },
  { key: 'Ctrl-Alt-i', run: indentSelection },
  { key: 'Alt-Mod-l', run: function () { tidy(); return true } },
  { key: 'Mod-f', run: openSearchPanel },
  { key: 'Mod-r', run: openSearchPanel },
  { key: 'F3', run: findNext },
  { key: 'Shift-F3', run: findPrevious },
  { key: 'Mod-g', run: findNext },
  { key: 'Shift-Mod-g', run: findPrevious },
  { key: 'Ctrl-g', run: selectNextOccurrence },
  { key: 'Ctrl-Mod-g', run: selectSelectionMatches },
  { key: 'Mod-=', run: unfoldCode },
  { key: 'Mod-+', run: unfoldCode },
  { key: 'Mod--', run: foldCode },
  { key: 'Shift-Mod-=', run: unfoldAll },
  { key: 'Shift-Mod-+', run: unfoldAll },
  { key: 'Shift-Mod--', run: foldAll },
  { key: 'Ctrl-m', run: cursorMatchingBracket },
  { key: 'Alt-Mod-[', run: block(false, false) },
  { key: 'Alt-Mod-]', run: block(true, false) },
  { key: 'Shift-Alt-Mod-[', run: block(false, true) },
  { key: 'Shift-Alt-Mod-]', run: block(true, true) },
  { key: 'F2', run: nextDiagnostic },
  { key: 'Shift-F2', run: previousDiagnostic }
]))

const paint = Prec.highest(syntaxHighlighting(HighlightStyle.define([
  { tag: [t.keyword, t.controlKeyword, t.moduleKeyword, t.operatorKeyword, t.definitionKeyword, t.modifier, t.self], color: '#cf8e6d' },
  { tag: [t.string, t.special(t.string), t.character, t.attributeValue], color: '#6aab73' },
  { tag: [t.regexp, t.escape], color: '#42c3d4' },
  { tag: [t.number, t.integer, t.float, t.unit], color: '#2aacb8' },
  { tag: [t.bool, t.null, t.atom, t.constant(t.variableName), t.standard(t.variableName)], color: '#c77dbb' },
  { tag: [t.comment, t.lineComment, t.blockComment, t.docComment], color: '#7a7e85', fontStyle: 'italic' },
  { tag: [t.function(t.variableName), t.function(t.propertyName), t.function(t.definition(t.variableName)), t.macroName], color: '#56a8f5' },
  { tag: t.definition(t.variableName), color: '#dfe1e5' },
  { tag: [t.variableName, t.name], color: '#bcbec4' },
  { tag: [t.propertyName, t.attributeName], color: '#c9a26d' },
  { tag: [t.typeName, t.className, t.namespace, t.annotation], color: '#57c1c8' },
  { tag: [t.tagName, t.angleBracket], color: '#d5b778' },
  { tag: [t.operator, t.compareOperator, t.arithmeticOperator, t.logicOperator, t.derefOperator, t.definitionOperator, t.updateOperator], color: '#a9b7c6' },
  { tag: [t.punctuation, t.separator, t.bracket, t.brace, t.paren, t.squareBracket], color: '#9aa0a8' },
  { tag: [t.meta, t.processingInstruction, t.documentMeta], color: '#b3ae60' },
  { tag: [t.labelName, t.special(t.variableName)], color: '#e8bf6a' },
  { tag: [t.heading, t.heading1, t.heading2, t.heading3], color: '#56a8f5', fontWeight: '700' },
  { tag: t.strong, fontWeight: '700' },
  { tag: t.emphasis, fontStyle: 'italic' },
  { tag: [t.link, t.url], color: '#56a8f5', textDecoration: 'underline' },
  { tag: t.monospace, color: '#6aab73' },
  { tag: t.quote, color: '#7a7e85', fontStyle: 'italic' },
  { tag: t.inserted, color: '#6aab73' },
  { tag: t.deleted, color: '#f75464' },
  { tag: t.invalid, color: '#f75464', textDecoration: 'underline wavy' }
])))

const keyed = Prec.highest(syntaxHighlighting(HighlightStyle.define([
  { tag: [t.definition(t.propertyName), t.propertyName], color: '#56a8f5' },
  { tag: t.content, color: '#6aab73' },
  { tag: [t.string, t.special(t.string)], color: '#6aab73' },
  { tag: [t.number, t.integer, t.float], color: '#2aacb8' },
  { tag: [t.bool, t.null, t.atom, t.keyword], color: '#cf8e6d' },
  { tag: [t.labelName, t.typeName, t.meta], color: '#c77dbb' },
  { tag: [t.punctuation, t.separator, t.operator], color: '#9aa0a8' }
])))

const mar = { tengo: 'tengo', tmpl: 'gotemplate', gotmpl: 'gotemplate' }

const named = [
  [/^\.env/, 'Properties files'], [/\.(conf|cfg|ini|properties|editorconfig)$/i, 'Properties files'], [/^\.editorconfig$/, 'Properties files'],
  [/^(just|make|gnumake)file$/i, 'Shell'], [/\.(mk|just|fish)$/i, 'Shell'], [/ignore$/, 'Shell'], [/^\.(zsh|bash)/, 'Shell'],
  [/\.(jsonl|jsonc|json5|lock|map)$/i, 'JSON'], [/\.(plist|xib|storyboard|csproj|entitlements)$/i, 'XML'], [/\.(tf|hcl)$/i, 'Ruby']
]

const shebang = [[/\b(ba|z|fi|da)?sh\b/, 'Shell'], [/python/, 'Python'], [/\b(node|deno|bun)\b/, 'JavaScript'], [/ruby/, 'Ruby'], [/perl/, 'Perl'], [/lua/, 'Lua'], [/php/, 'PHP']]

const words = new Set('if else elif for while do done then fi return function func fn def class struct enum type interface import from export package use const let var val true false null nil none end begin switch case match break continue try catch finally throw new public private static async await in of as is not and or'.split(' '))

const generic = StreamLanguage.define({
  startState: () => ({ block: false }),
  token(stream, state) {
    if (state.block) {
      if (stream.skipTo('*/')) { stream.next(); stream.next(); state.block = false } else stream.skipToEnd()
      return 'comment'
    }
    if (stream.eatSpace()) return null
    if (stream.match('/*')) { state.block = true; return 'comment' }
    if (stream.match('//') || stream.match(/^#(?![0-9a-fA-F]{3,8}\b)/) || stream.match(/^--\s/) || (stream.sol() && stream.match(';'))) { stream.skipToEnd(); return 'comment' }
    const quote = stream.match(/^["'`]/)
    if (quote) {
      let escaped = false, ch
      while ((ch = stream.next()) != null) {
        if (ch === quote[0] && !escaped) break
        escaped = !escaped && ch === '\\'
      }
      return 'string'
    }
    if (stream.match(/^-?(0x[0-9a-fA-F]+|\d+(\.\d+)?([eE][-+]?\d+)?)/)) return 'number'
    const word = stream.match(/^[A-Za-z_$][\w$-]*/)
    if (word) {
      if (words.has(word[0].toLowerCase())) return /^(true|false|null|nil|none)$/i.test(word[0]) ? 'atom' : 'keyword'
      if (stream.peek() === '(') return 'variableName.function'
      if (stream.match(/^\s*[:=]/, false)) return 'propertyName'
      return 'variableName'
    }
    if (stream.match(/^[+\-*/%=<>!&|^~?:]+/)) return 'operator'
    stream.next()
    return 'punctuation'
  }
})

function guess(text) {
  const head = text.slice(0, 4000)
  const first = head.split('\n', 1)[0]
  if (first.startsWith('#!')) {
    const hit = shebang.find(function (s) { return s[0].test(first) })
    if (hit) return hit[1]
  }
  const trimmed = head.trimStart()
  if (/^[{[]/.test(trimmed)) {
    try { JSON.parse(text); return 'JSON' } catch (e) {}
  }
  if (/^<\?xml|^<!DOCTYPE\s+(?!html)|^<svg|^<plist/i.test(trimmed)) return 'XML'
  if (/^<!doctype html|^<html/i.test(trimmed)) return 'HTML'
  if (/^diff --git |^--- .*\n\+\+\+ /m.test(head)) return 'diff'
  const lines = head.split('\n').filter(function (l) { return l.trim() && !/^\s*#/.test(l) })
  if (lines.length && lines.filter(function (l) { return /^\s*\[[^\]]+\]\s*$|^\s*[\w.-]+\s*=/.test(l) }).length > lines.length * 0.7) return 'TOML'
  if (first === '---' || (lines.length && lines.filter(function (l) { return /^\s*(- )?[\w."'-]+:(\s|$)/.test(l) }).length > lines.length * 0.7)) return 'YAML'
  return ''
}

async function pick(name, text) {
  const ext = name.includes('.') ? name.split('.').pop().toLowerCase() : ''
  if (mar[ext]) return { language: mar[ext], support: [] }
  const hit = named.find(function (n) { return n[0].test(name) })
  let found = hit ? LanguageDescription.matchLanguageName(languages, hit[1]) : LanguageDescription.matchFilename(languages, name)
  let unknown = null
  if (!found && !/\.(txt|text|log)$/i.test(name)) {
    const by = guess(text)
    found = by ? LanguageDescription.matchLanguageName(languages, by) : null
    unknown = { name: name, guess: found ? found.name : 'generic' }
  }
  if (!found) return { language: 'plaintext', support: unknown ? generic : [], unknown: unknown }
  try {
    const loaded = await found.load()
    return { language: 'plaintext', support: /^(YAML|TOML|Properties files)$/.test(found.name) ? [loaded, keyed] : loaded, unknown: unknown }
  } catch (e) {
    return { language: 'plaintext', support: generic, unknown: unknown }
  }
}

const state = reactive({ path: '', text: '', live: '', kind: '', media: '', url: '', sides: false, locked: false, mode: 'both', language: 'plaintext', diagnostics: [], key: 0, review: null, picking: false })
const zooms = reactive({})
const extra = new Compartment()
const diffed = new Compartment()
let view = null
let support = []
let original = null
let diffing = false
let mounted = null
let sideSupport = []
let current = ''
let timer = 0
let pair = null
let side = 'b'
let fronted = 'code'
let region = -1
let wanted = null

function post(body) {
  return window.webkit.messageHandlers.editor.postMessage(body)
}

class Tally extends GutterMarker {
  constructor(added, removed) {
    super()
    this.added = added
    this.removed = removed
  }
  eq(other) {
    return other.added === this.added && other.removed === this.removed
  }
  toDOM() {
    const el = document.createElement('span')
    el.className = 'tally'
    if (this.added) {
      const up = document.createElement('i')
      up.className = 'up'
      up.textContent = '+' + this.added
      el.appendChild(up)
    }
    if (this.removed) {
      const down = document.createElement('i')
      down.className = 'down'
      down.textContent = '−' + this.removed
      el.appendChild(down)
    }
    return el
  }
}

const tallies = gutter({
  class: 'cm-tallies',
  lineMarker(v, line) {
    const info = getChunks(v.state)
    const before = getOriginalDoc(v.state)
    if (!info) return null
    for (const c of info.chunks) {
      if (c.fromB !== line.from) continue
      const added = c.toB > c.fromB ? v.state.doc.lineAt(Math.min(c.toB, v.state.doc.length) - 1).number - v.state.doc.lineAt(c.fromB).number + 1 : 0
      const removed = c.toA > c.fromA ? before.lineAt(Math.min(c.toA, before.length) - 1).number - before.lineAt(c.fromA).number + 1 : 0
      return new Tally(added, removed)
    }
    return null
  },
  initialSpacer() {
    return new Tally(88, 88)
  }
})

let traced = []
let tracing = true
const retrace = StateEffect.define()

class Trace extends GutterMarker {
  constructor(list) {
    super()
    this.list = list
  }
  eq(other) {
    return other.list.length === this.list.length && other.list.every(function (t, i) { return t === this.list[i] }, this)
  }
  toDOM() {
    const el = document.createElement('span')
    const acts = this.list.map(function (t) { return t.act })
    el.className = 'trace ' + (acts.includes('wrote') ? 'wrote' : acts.includes('edited') ? 'edited' : 'read')
    el.title = this.list.map(function (t) { return t.who + ' ' + t.act + ' ' + (t.from === t.to ? 'line ' + t.from : 'lines ' + t.from + '-' + t.to) + (t.when ? ' · ' + t.when : '') }).join('\n')
    return el
  }
}

const traces = gutter({
  class: 'cm-traces',
  lineMarker(v, line) {
    if (!tracing || !traced.length) return null
    const n = v.state.doc.lineAt(line.from).number
    const hit = traced.filter(function (t) { return n >= t.from && n <= t.to })
    return hit.length ? new Trace(hit) : null
  },
  lineMarkerChange(update) {
    return update.transactions.some(function (tr) { return tr.effects.some(function (e) { return e.is(retrace) }) })
  }
})

function control(type, action) {
  const el = document.createElement('button')
  el.className = 'chunk ' + type
  el.textContent = type === 'accept' ? '✓ keep' : '↺ revert'
  el.title = type === 'accept' ? 'Keep this change and stop showing it' : 'Put back what HEAD has here'
  el.onmousedown = action
  return el
}

const folded = EditorView.domEventHandlers({
  mousedown(event) {
    const chunk = event.target.closest ? event.target.closest('.cm-deletedChunk') : null
    if (!chunk || event.target.closest('button')) return false
    chunk.classList.toggle('open')
    return true
  }
})

function merge() {
  return diffing && original != null ? [unifiedMergeView({ original: original, mergeControls: control, gutter: true, highlightChanges: true, syntaxHighlightDeletions: true, collapseUnchanged: { margin: 3, minSize: 6 } }), tallies, folded] : []
}

function at(pos) {
  const line = view.state.doc.lineAt(pos)
  return { line: line.number - 1, character: pos - line.from }
}

function flat(contents) {
  if (!contents) return ''
  if (typeof contents === 'string') return contents
  if (Array.isArray(contents)) return contents.map(flat).filter(Boolean).join('\n\n')
  return contents.value || ''
}

async function complete(context) {
  const word = context.matchBefore(/[\w$]*/)
  const before = context.state.sliceDoc(Math.max(0, context.pos - 1), context.pos)
  if (!context.explicit && word.from === word.to && !/[.:>/"'@<]/.test(before)) return null
  const reply = await post(Object.assign({ lsp: 'textDocument/completion', path: state.path, text: context.state.doc.toString() }, at(context.pos)))
  const items = reply ? (Array.isArray(reply) ? reply : reply.items || []) : []
  if (!items.length || context.aborted) return null
  return {
    from: word.from,
    options: items.slice(0, 400).map(function (i) {
      const insert = i.insertTextFormat === 2 ? i.label : (i.textEdit && i.textEdit.newText) || i.insertText || i.label
      return { label: i.label, detail: i.detail, apply: insert, info: flat(i.documentation) || undefined, boost: i.sortText ? -i.sortText.charCodeAt(0) / 1000 : 0 }
    })
  }
}

function local(v, pos) {
  const word = v.state.wordAt(pos)
  if (!word) return null
  const name = v.state.sliceDoc(word.from, word.to)
  if (!/^[A-Za-z_$][\w$]*$/.test(name)) return null
  const safe = name.replace(/[$]/g, '\\$')
  const declared = new RegExp('\\b(func|function|fn|def|class|struct|enum|protocol|interface|type|trait|const|let|var|val|static|local)\\s+' + safe + '\\b|^\\s*' + safe + '\\s*(\\(\\)\\s*\\{|:?=(?!=))|\\b(import|from|use|require|include)\\b.*\\b' + safe + '\\b')
  const doc = v.state.doc
  const here = doc.lineAt(pos).number
  const found = []
  for (let n = 1; n <= doc.lines && found.length < 4; n++) {
    const line = doc.line(n).text
    if (n !== here && declared.test(line)) found.push({ line: n, text: line.trim().slice(0, 160) })
  }
  let uses = 0
  const every = new RegExp('\\b' + safe + '\\b', 'g')
  for (let n = 1; n <= doc.lines; n++) uses += (doc.line(n).text.match(every) || []).length
  return { name: name, found: found, uses: uses, from: word.from, to: word.to }
}

const hover = hoverTooltip(async function (v, pos) {
  if (!state.path) return null
  const near = local(v, pos)
  const reply = await post(Object.assign({ lsp: 'textDocument/hover', path: state.path, text: v.state.doc.toString() }, at(pos)))
  const text = reply ? flat(reply.contents) : ''
  if (!text && !near) return null
  return {
    pos: near ? near.from : pos,
    end: near ? near.to : pos,
    create() {
      const dom = document.createElement('div')
      dom.className = 'tip'
      text.split(/```/).forEach(function (part, i) {
        const body = i % 2 ? part.replace(/^\w*\n/, '') : part
        if (!body.trim()) return
        const el = document.createElement(i % 2 ? 'pre' : 'p')
        el.textContent = body.trim()
        dom.appendChild(el)
      })
      if (near) {
        near.found.forEach(function (f) {
          const el = document.createElement('div')
          el.className = 'where'
          const at = document.createElement('b')
          at.textContent = 'line ' + f.line
          el.appendChild(at)
          el.appendChild(document.createTextNode(' ' + f.text))
          el.onmousedown = function () { window.slyc.line(f.line) }
          dom.appendChild(el)
        })
        const el = document.createElement('div')
        el.className = 'uses'
        el.textContent = near.name + ' · ' + near.uses + (near.uses === 1 ? ' use' : ' uses') + ' in this file' + (text ? '' : ' · no language server answer')
        dom.appendChild(el)
      }
      return { dom: dom }
    }
  }
})

function count(text, pattern) {
  return (text.match(pattern) || []).length
}

function stats() {
  const text = current
  const name = (state.path.split('/').pop() || '').toLowerCase()
  const ext = name.includes('.') ? name.split('.').pop() : name
  const words = count(text, /\S+/g)
  const out = [text ? text.split('\n').length + ' lines' : '0 lines', words + ' words', text.length + ' chars']
  function add(n, label) { if (n > 0) out.push(n + ' ' + label) }
  if (/^(md|markdown|mdx|txt|text)$/.test(ext)) {
    add(count(text, /^#{1,6}\s/gm), 'headings')
    add(count(text, /\]\(/g), 'links')
    add(count(text, /^```/gm) >> 1, 'code blocks')
    out.push(Math.max(1, Math.ceil(words / 220)) + ' min read')
  } else if (/^(json|jsonl|jsonc)$/.test(ext)) {
    add(count(text, /"(?:[^"\\]|\\.)*"\s*:/g), 'keys')
    add(count(text, /\[/g), 'arrays')
  } else if (/^(css|scss|less)$/.test(ext)) {
    add(count(text, /\{/g), 'rules')
    add(count(text, /--[\w-]+\s*:/g), 'variables')
    add(count(text, /@media/g), 'media queries')
  } else if (/^(html|htm|vue|svelte|xml|svg)$/.test(ext)) {
    add(count(text, /<[a-zA-Z][^>]*>/g), 'tags')
    add(count(text, /<script\b/gi), 'scripts')
    add(count(text, /<style\b/gi), 'styles')
    add(count(text, /\b(const|let|var)\s+[\w$]+/g), 'variables')
    add(count(text, /\bfunction\b|=>/g), 'functions')
  } else if (/^(yaml|yml|toml|ini|env|conf|cfg|properties)$/.test(ext)) {
    add(count(text, /^\s*[\w."'-]+\s*[:=]/gm), 'keys')
    add(count(text, /^\s*\[[^\]]+\]/gm), 'sections')
  } else if (!state.media) {
    add(count(text, /\b(function|func|fn|def|sub|proc)\b|=>|^[\w:]+\(\)\s*\{/gm), 'functions')
    add(count(text, /\b(const|let|var|val|local|my)\s+[\w$]+|^\s*[A-Za-z_][\w]*\s*:?=(?!=)/gm), 'variables')
    add(count(text, /\b(class|struct|interface|enum|trait|protocol)\s+\w+/g), 'types')
    add(count(text, /^\s*(import|from|use|require|#include|source|package)\b/gm), 'imports')
  }
  add(count(text, /\b(TODO|FIXME|XXX|HACK)\b/g), 'todos')
  const errors = state.diagnostics.filter(function (d) { return d.severity !== 'warning' }).length
  add(errors, 'errors')
  add(state.diagnostics.length - errors, 'warnings')
  let cursor = ''
  if (view) {
    const range = view.state.selection.main
    const line = view.state.doc.lineAt(range.head)
    cursor = 'Ln ' + line.number + ', Col ' + (range.head - line.from + 1) + (range.empty ? '' : ' · ' + (range.to - range.from) + ' selected')
  }
  post({ stats: out, cursor: cursor, path: state.path })
}

let counting = 0

function recount() {
  clearTimeout(counting)
  counting = setTimeout(stats, 120)
}

async function tidy() {
  if (!view) return false
  const before = view.state.doc
  const reply = await post({ lsp: 'textDocument/formatting', path: state.path, text: before.toString(), line: 0, character: 0, options: { tabSize: view.state.tabSize, insertSpaces: !/\t/.test(before.sliceString(0, 4000)) } })
  if (Array.isArray(reply) && reply.length && view.state.doc === before) {
    const changes = reply.map(function (e) {
      const from = before.line(Math.min(e.range.start.line + 1, before.lines))
      const to = before.line(Math.min(e.range.end.line + 1, before.lines))
      return { from: Math.min(from.from + e.range.start.character, from.to), to: e.range.end.line + 1 > before.lines ? before.length : Math.min(to.from + e.range.end.character, to.to), insert: e.newText }
    })
    view.dispatch({ changes: changes })
    return 'server'
  }
  return mounted && mounted.format ? ((await mounted.format()) ? 'editor' : false) : false
}

function attach(code) {
  mounted = code
  view = code && code.view ? code.view() : null
  if (!view) return
  view.dispatch({ effects: StateEffect.appendConfig.of([keys, traces, extra.of(support), paint, EditorView.updateListener.of(function (u) { if (u.selectionSet || u.docChanged) recount() }), diffed.of(merge()),EditorState.languageData.of(function () { return [{ autocomplete: complete }] }), hover]) })
  view.focus()
  recount()
}

function changed(value) {
  current = value
  clearTimeout(timer)
  timer = setTimeout(function () {
    state.live = current
    post({ change: current, path: state.path })
    recount()
  }, 150)
}

function scope(pane) {
  if (pane === 'preview') return 'zoom.preview.' + (state.kind || state.media)
  const name = (state.path.split('/').pop() || '').toLowerCase()
  return 'zoom.code.' + ((name.includes('.') ? name.split('.').pop() : name).replace(/[^a-z0-9_+-]/g, '') || 'plain')
}

function zoom(pane, by) {
  const key = scope(pane)
  const next = by ? Math.min(3, Math.max(0.5, Math.round(((zooms[key] || 1) + by) * 100) / 100)) : 1
  zooms[key] = next
  post({ zoom: key, value: next })
}

function front(event) {
  const frame = event.target.closest && event.target.closest('.mar-editor-frame-code, .mar-editor-frame-preview')
  if (frame) fronted = frame.classList.contains('mar-editor-frame-preview') ? 'preview' : 'code'
}

document.addEventListener('pointerdown', front, true)
document.addEventListener('focusin', front)
window.addEventListener('blur', function () {
  if (document.activeElement) front({ target: document.activeElement })
})

watchEffect(function () {
  const root = document.documentElement.style
  root.setProperty('--code-zoom', String(zooms[scope('code')] || 1))
  root.setProperty('--preview-zoom', String(zooms[scope('preview')] || 1))
  nextTick(function () {
    [view, pair && pair.a, pair && pair.b].forEach(function (ed) { if (ed) ed.requestMeasure() })
  })
})

const probing = String.raw`
  var doc = root.ownerDocument
  var ring = doc.createElement('div')
  var armed = false
  var over = null
  function trail(el) {
    var parts = []
    for (var at = el; at && at.nodeType === 1 && at !== root && parts.length < 6; at = at.parentElement) {
      var names = typeof at.className === 'string' ? at.className.trim() : (at.getAttribute('class') || '').trim()
      parts.unshift(at.localName + (at.id ? '#' + at.id : '') + (names ? '.' + names.split(/\s+/).slice(0, 3).join('.') : ''))
    }
    return parts.join(' > ')
  }
  function arm(on) {
    armed = on
    over = null
    ring.style.cssText = 'display:none'
    root.style.cursor = on ? 'crosshair' : ''
    if (on && !ring.parentNode) (doc.body || doc.documentElement).appendChild(ring)
    send({ armed: on })
  }
  root.addEventListener('mousemove', function (event) {
    var el = event.target
    if (!armed || el === over || el === root || el === ring || el.nodeType !== 1 || el.closest('.zoomer')) return
    over = el
    var box = el.getBoundingClientRect()
    ring.style.cssText = 'position:fixed;z-index:2147483647;pointer-events:none;box-sizing:border-box;border:2px solid #ef8221;border-radius:4px;background:rgba(239,130,33,0.14);left:' + box.left + 'px;top:' + box.top + 'px;width:' + box.width + 'px;height:' + box.height + 'px'
  }, true)
  root.addEventListener('click', function (event) {
    if (!armed || event.target.closest('.zoomer')) return
    event.preventDefault()
    event.stopPropagation()
    var el = over || event.target
    var files = []
    doc.querySelectorAll('link[href], script[src], img[src], source[src], iframe[src]').forEach(function (used) {
      var url = used.href || used.src
      if (url && files.indexOf(url) < 0) files.push(url)
    })
    var picked = { trail: trail(el), id: el.id || '', text: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 300), html: el.outerHTML.slice(0, 1200), files: files }
    arm(false)
    send({ picked: picked })
  }, true)
  doc.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && armed) arm(false)
    if (!own || armed || event.key !== 'c' || event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target.isContentEditable || /^(input|textarea|select)$/.test(event.target.localName)) return
    event.preventDefault()
    arm(true)
  }, true)
  return arm
`
const probe = new Function('root', 'send', 'own', probing)
const framed = '<script>(function () { var arm = (function (root, send, own) {' + probing + '})(document.documentElement, function (said) { parent.postMessage({ slyc: said }, "*") }, true); parent.postMessage({ slyc: { armed: false } }, "*"); addEventListener("message", function (event) { if (event.source === parent && event.data && typeof event.data.slyc === "boolean") arm(event.data.slyc) }) })()</' + 'script>'
let arm = null

function heard(said) {
  if ('armed' in said) state.picking = !!said.armed
  if (!said.picked) return
  const picked = said.picked
  const source = current
  let found = picked.id ? source.indexOf('id="' + picked.id + '"') : -1
  for (let size = Math.min(40, picked.text.length); found < 0 && size >= 3; size = size >> 1) found = source.indexOf(picked.text.slice(0, size))
  const files = picked.files.filter(function (url) { return String(url).startsWith('slyed://file/') }).map(function (url) { return decodeURIComponent(new URL(url).pathname) })
  post({ remark: { trail: picked.trail, text: picked.text, html: picked.html, files: files, line: found < 0 ? 0 : source.slice(0, found).split('\n').length }, path: state.path })
}

function pin(on) {
  const stage = document.querySelector('.mar-editor-frame-preview')
  if (!stage) return
  if (state.kind === 'html') {
    const frame = stage.querySelector('iframe')
    if (frame && frame.contentWindow) frame.contentWindow.postMessage({ slyc: on }, '*')
    return
  }
  if (!arm) arm = probe(stage, heard, false)
  arm(on)
}

window.addEventListener('message', function (event) {
  const frame = document.querySelector('.mar-editor-frame-preview iframe')
  if (frame && event.source === frame.contentWindow && event.data && event.data.slyc) heard(event.data.slyc)
})

document.addEventListener('keydown', function (event) {
  if (event.key === 'Escape' && state.picking) pin(false)
  if (event.key !== 'c' || event.metaKey || event.ctrlKey || event.altKey || state.picking || !state.kind || state.mode === 'code') return
  if (event.target.isContentEditable || /^(input|textarea|select)$/.test(event.target.localName)) return
  const stage = document.querySelector('.mar-editor-frame-preview')
  if (!stage || !stage.matches(':hover')) return
  event.preventDefault()
  pin(true)
})

function drawn(source) {
  const parsed = new DOMParser().parseFromString(source, 'image/svg+xml')
  parsed.querySelectorAll('script, foreignObject').forEach(function (el) { el.remove() })
  parsed.querySelectorAll('*').forEach(function (el) {
    Array.from(el.attributes).forEach(function (a) { if (/^on/i.test(a.name) || /^\s*javascript:/i.test(a.value)) el.removeAttribute(a.name) })
  })
  return parsed.documentElement.localName === 'svg' ? parsed.documentElement.outerHTML : ''
}

const Zoomer = {
  props: { pane: String },
  setup(props) {
    return function () {
      const key = scope(props.pane)
      const value = zooms[key] || 1
      function step(by) {
        zoom(props.pane, by)
      }
      return h('div', { class: 'zoomer', onMousedown: function (event) { event.preventDefault() } }, [
        h('button', { title: 'Zoom out', onClick: function () { step(-0.1) } }, '−'),
        h('button', { class: 'level', title: 'Zoom of ' + key.split('.').pop() + (props.pane === 'preview' ? ' previews' : ' files') + ', click to reset', onClick: function () { step(0) } }, Math.round(value * 100) + '%'),
        h('button', { title: 'Zoom in', onClick: function () { step(0.1) } }, '+')
      ])
    }
  }
}

const readout = ref('')
const owl = (function () {
  const inner = /<svg x=[^>]*viewBox="0 0 1024\.000000 1024\.000000">([\s\S]*?)<\/svg>/.exec(icon)
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">' + (inner ? inner[1] : '') + '</svg>')
})()

const Idle = {
  setup() {
    const el = ref(null)
    let queued = 0
    function aim(event) {
      if (queued) return
      queued = requestAnimationFrame(function () {
        queued = 0
        const box = el.value ? el.value.getBoundingClientRect() : null
        if (!box) return
        el.value.style.setProperty('--tx', ((event.clientX - box.left) / box.width - 0.5).toFixed(3))
        el.value.style.setProperty('--ty', ((event.clientY - box.top) / box.height - 0.5).toFixed(3))
      })
    }
    function cube(n) {
      return h('div', { class: 'cube c' + n }, [1, 2, 3, 4, 5, 6].map(function (f) { return h('i', { class: 'f' + f }) }))
    }
    return function () {
      return h('div', { class: 'idle', ref: el, onMousemove: aim }, [
        h('div', { class: 'sky a' }), h('div', { class: 'sky b' }), h('div', { class: 'sky c' }),
        h('div', { class: 'floor' }, h('i')),
        h('div', { class: 'tunnel' }, [0, 1, 2, 3, 4, 5, 6, 7].map(function (n) { return h('i', { style: 'animation-delay:' + (-n * 1.5) + 's' }) })),
        h('div', { class: 'idle-stage' }, [
          h('i', { class: 'ring one' }), h('i', { class: 'ring two' }), h('i', { class: 'ring three' }),
          h('div', { class: 'orbit' }, [0, 1, 2, 3, 4, 5].map(function (n) { return h('span', { style: '--a:' + n * 60 + 'deg' }, h('img', { src: owl })) })),
          h('div', { class: 'orbit far' }, [cube(1), cube(2), cube(3), cube(4)]),
          h('img', { class: 'idle-owl echo', src: owl, style: 'animation-delay:-2s' }),
          h('img', { class: 'idle-owl echo', src: owl, style: 'animation-delay:-4s' }),
          h('img', { class: 'idle-owl echo', src: owl }),
          h('img', { class: 'idle-owl', src: owl })
        ]),
        h('div', { class: 'idle-text' }, [h('b', 'Slyed'), h('span', 'See every change before it lands'), h('span', 'Open a file from the sidebar · ⌘K to search'), h('span', { class: 'vital' }, readout.value)])
      ])
    }
  }
}

function focused(name) {
  return EditorView.updateListener.of(function (u) {
    if (u.focusChanged && u.view.hasFocus) side = name
    if (u.selectionSet && u.view.hasFocus) recount()
  })
}

const focus = StateEffect.define()
const dim = Decoration.line({ class: 'cm-blurred' })

function blur(doc, from, to) {
  const first = Math.max(1, doc.lineAt(Math.min(from, doc.length)).number - 1)
  const last = Math.min(doc.lines, doc.lineAt(Math.min(Math.max(from, to - 1), doc.length)).number + 1)
  const marks = []
  for (let n = 1; n <= doc.lines; n++) {
    if (n < first || n > last) marks.push(dim.range(doc.line(n).from))
  }
  return Decoration.set(marks)
}

const blurred = StateField.define({
  create() { return Decoration.none },
  update(set, tr) {
    for (const e of tr.effects) {
      if (e.is(focus)) set = blur(tr.state.doc, e.value.from, e.value.to)
    }
    return set
  },
  provide(f) { return EditorView.decorations.from(f) }
})

function nearest(view, pos) {
  const left = view === pair.a
  let best = -1
  let gap = Infinity
  pair.chunks.forEach(function (c, n) {
    const from = left ? c.fromA : c.fromB
    const to = left ? c.toA : c.toB
    const d = pos < from ? from - pos : pos > to ? pos - to : 0
    if (d < gap) {
      gap = d
      best = n
    }
  })
  return best
}

const fenced = EditorView.domEventHandlers({
  mousedown(event, view) {
    if (!pair) return false
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY })
    if (pos == null) return false
    const line = view.state.doc.lineAt(pos)
    let dimmed = false
    view.state.field(blurred).between(line.from, line.from, function () { dimmed = true })
    if (!dimmed) return false
    event.preventDefault()
    const n = nearest(view, pos)
    if (n >= 0) seek(n)
    return true
  }
})

const review = [blurred, fenced, EditorState.readOnly.of(true), EditorState.changeFilter.of(function () { return false }), EditorView.theme({ '.cm-line.cm-blurred': { filter: 'blur(2.5px)', opacity: '0.35', transition: 'filter 0.2s, opacity 0.2s' } })]

let bounds = null
let free = false
let steering = false

function centre() {
  bounds = null
  const dom = pair ? pair.dom.parentElement || pair.dom : null
  if (dom) dom.classList.remove('pinned')
  if (!pair || !state.locked || region < 0 || region >= pair.chunks.length) return
  const c = pair.chunks[region]
  const inB = c.toB > c.fromB
  const ed = inB ? pair.b : pair.a
  const from = inB ? c.fromB : c.fromA
  const to = Math.max(from, (inB ? c.toB : c.toA) - 1)
  const length = ed.state.doc.length
  const offset = ed.documentTop - dom.getBoundingClientRect().top + dom.scrollTop
  const top = offset + ed.lineBlockAt(Math.min(from, length)).top
  const bottom = offset + ed.lineBlockAt(Math.min(to, length)).bottom
  const tall = dom.clientHeight
  const most = Math.max(0, dom.scrollHeight - tall)
  const low = bottom - top <= tall ? top - (tall - (bottom - top)) / 2 : top
  const high = bottom - top <= tall ? low : bottom - tall
  bounds = [Math.min(most, Math.max(0, low)), Math.min(most, Math.max(0, high))]
  steering = true
  dom.scrollTop = bounds[0]
  steering = false
  dom.classList.toggle('pinned', !free && bounds[1] - bounds[0] < 1)
}

function hold(value) {
  return bounds ? Math.min(bounds[1], Math.max(bounds[0], value)) : value
}

function steer(dom) {
  dom.addEventListener('wheel', function (event) {
    if (!state.locked || free || !bounds || event.metaKey || event.ctrlKey || Math.abs(event.deltaX) > Math.abs(event.deltaY)) return
    event.preventDefault()
    steering = true
    dom.scrollTop = hold(dom.scrollTop + event.deltaY)
    steering = false
  }, { passive: false })
  dom.addEventListener('scroll', function () {
    if (steering || free || !bounds || !state.locked) return
    const held = hold(dom.scrollTop)
    if (Math.abs(held - dom.scrollTop) > 0.5) {
      steering = true
      dom.scrollTop = held
      steering = false
    }
  })
  const watch = new ResizeObserver(function () { requestAnimationFrame(centre) })
  watch.observe(dom)
  return watch
}

function seek(target) {
  if (!pair) {
    wanted = target
    return { at: -1, of: 0, done: false }
  }
  const chunks = pair.chunks
  const at = target === 'next' ? region + 1 : target === 'prev' ? region - 1 : target === 'last' ? chunks.length - 1 : target === 'first' ? 0 : target
  if (!chunks.length || at < 0 || at >= chunks.length) return { at: region, of: chunks.length, done: true }
  region = at
  const c = chunks[at]
  const inB = c.toB > c.fromB
  const ed = inB ? pair.b : pair.a
  const length = ed.state.doc.length
  const from = Math.min(inB ? c.fromB : c.fromA, length)
  const to = Math.min(Math.max(from, (inB ? c.toB : c.toA) - 1), length)
  if (state.locked) {
    pair.a.dispatch({ effects: focus.of({ from: c.fromA, to: c.toA }) })
    pair.b.dispatch({ effects: focus.of({ from: c.fromB, to: c.toB }) })
  }
  if (state.locked) {
    free = false
    ed.dispatch({ selection: { anchor: from, head: to } })
    requestAnimationFrame(centre)
  } else {
    ed.dispatch({ selection: { anchor: from, head: to }, effects: EditorView.scrollIntoView(from, { y: 'center' }) })
  }
  side = inB ? 'b' : 'a'
  post({ region: { at: at, of: chunks.length } })
  return { at: at, of: chunks.length, done: false }
}

const Sides = {
  setup() {
    const el = ref(null)
    let both = null
    let watch = null
    onMounted(function () {
      view = null
      region = -1
      side = 'b'
      const editable = state.locked ? [EditorState.readOnly.of(true)] : [EditorView.updateListener.of(function (u) { if (u.docChanged) changed(u.state.doc.toString()) })]
      const room = state.locked ? review : []
      both = new MergeView({
        a: { doc: original || '', extensions: [basicSetup, keys, oneDark, paint, sideSupport, EditorState.readOnly.of(true), focused('a')].concat(room) },
        b: { doc: current, extensions: [basicSetup, keys, oneDark, paint, sideSupport, focused('b')].concat(editable, room) },
        parent: el.value,
        collapseUnchanged: state.locked ? undefined : { margin: 3, minSize: 6 },
        gutter: true
      })
      pair = both
      if (state.locked) watch = steer(el.value)
      post({ region: { at: -1, of: both.chunks.length } })
      if (wanted !== null) {
        const target = wanted
        wanted = null
        seek(target)
      }
    })
    onBeforeUnmount(function () {
      if (watch) watch.disconnect()
      if (pair === both) pair = null
      if (both) both.destroy()
    })
    return function () { return h('div', { class: 'sides', ref: el }) }
  }
}

const Tree = {
  setup() {
    const el = ref(null)
    function centre() {
      nextTick(function () {
        const on = el.value ? el.value.querySelector('.hunk.on') : null
        if (on) on.scrollIntoView({ block: 'center' })
      })
    }
    onMounted(centre)
    watch(function () { return state.review ? state.review.at : -1 }, centre)
    return function () {
      return h('div', { class: 'tree', ref: el }, state.review.files.map(function (file) {
        return h('section', { key: file.n }, [
          h('header', [
            h('b', file.n + '. ' + file.name),
            h('span', { class: 'where' }, file.path),
            h('span', { class: 'what' }, file.title),
            h('span', { class: 'tally' }, [file.added ? h('i', { class: 'up' }, '+' + file.added) : null, file.removed ? h('i', { class: 'down' }, '−' + file.removed) : null])
          ]),
          file.hunks.map(function (hunk) {
            return h('div', { key: hunk.id, class: ['hunk', hunk.status, { on: hunk.id === state.review.at }], onClick: function () { post({ hunk: hunk.id }) } }, [
              h('div', { class: 'head' }, [h('b', hunk.label), h('span', hunk.status), hunk.text ? h('q', hunk.text) : null]),
              hunk.why ? h('p', { class: 'why' }, hunk.why.split(/\b([Qq]\d+)\b/).map(function (part, i) { return i % 2 ? h('b', part) : part })) : null,
              h('div', { class: 'rows' }, hunk.rows.map(function (row) {
                return h('div', { class: row.t === '+' ? 'row add' : row.t === '-' ? 'row del' : 'row' }, [h('i', row.a || ''), h('i', row.b || ''), h('u', row.t), h('code', row.s)])
              }))
            ])
          })
        ])
      }))
    }
  }
}

window.slyc = {
  review(doc) {
    clearTimeout(timer)
    view = null
    state.kind = ''
    state.media = ''
    state.sides = false
    state.locked = false
    state.diagnostics = []
    state.review = doc
    return true
  },
  traces(path, list) {
    if (path !== state.path) return false
    traced = list
    if (view) view.dispatch({ effects: retrace.of(null) })
    return true
  },
  settings(given) {
    const set = Object.assign({ font: 'Liga Roboto Mono', ligatures: true, smoothing: true, traces: true, accent: '#b4632f', read: '#56a8f5', edited: '#ef8221', wrote: '#6aab73' }, given)
    const root = document.documentElement.style
    root.setProperty('--code-font', '"' + String(set.font).replace(/"/g, '') + '", "Roboto Mono", ui-monospace, Menlo, monospace')
    root.setProperty('--code-ligatures', set.ligatures ? 'common-ligatures discretionary-ligatures contextual' : 'none')
    root.setProperty('--code-smoothing', set.smoothing ? 'auto' : 'antialiased')
    root.setProperty('--accent', set.accent)
    root.setProperty('--trace-read', set.read)
    root.setProperty('--trace-edited', set.edited)
    root.setProperty('--trace-wrote', set.wrote)
    tracing = set.traces !== false
    Object.keys(zooms).forEach(function (key) { if (typeof given[key] !== 'number') delete zooms[key] })
    Object.keys(given).forEach(function (key) { if (/^zoom\.(code|preview)\./.test(key) && typeof given[key] === 'number') zooms[key] = given[key] })
    if (view) view.dispatch({ effects: retrace.of(null) })
    return true
  },
  hunk(at, marks) {
    if (!state.review) return false
    state.review.at = at
    state.review.files.forEach(function (file) {
      file.hunks.forEach(function (hunk) {
        if (!marks[hunk.id]) return
        hunk.status = marks[hunk.id].status
        hunk.text = marks[hunk.id].text
      })
    })
    return true
  },
  async show(doc) {
    clearTimeout(timer)
    const picked = doc.media ? { language: 'plaintext', support: [] } : await pick(doc.name, doc.text)
    support = picked.support
    const side = doc.media ? null : LanguageDescription.matchFilename(languages, doc.name)
    sideSupport = side ? await side.load().catch(function () { return [] }) : picked.support
    original = doc.original
    current = doc.text
    state.path = doc.path
    state.text = doc.text
    state.live = doc.text
    state.media = doc.media || ''
    state.url = doc.url || ''
    state.locked = !!doc.locked
    state.review = null
    if (state.picking) pin(false)
    traced = []
    wanted = null
    state.kind = doc.media ? '' : /\.(md|markdown|mdx)$/i.test(doc.name) ? 'markdown' : /\.html?$/i.test(doc.name) ? 'html' : /\.svg$/i.test(doc.name) ? 'svg' : ''
    state.language = picked.language
    state.diagnostics = []
    state.key++
    recount()
    if (picked.unknown) post({ unknown: picked.unknown, path: doc.path })
    return { preview: state.kind !== '', mode: state.mode }
  },
  mode(mode) {
    state.text = current
    state.live = current
    state.mode = mode
    return true
  },
  text() {
    clearTimeout(timer)
    return current
  },
  diff(on, base, sides) {
    diffing = on && !sides
    state.text = current
    state.sides = !!sides && original != null
    if (base !== undefined) original = base
    if (view) view.dispatch({ effects: diffed.reconfigure(merge()) })
    return diffing && original != null
  },
  line(number, end) {
    if (!view) return false
    const line = view.state.doc.line(Math.min(Math.max(1, number), view.state.doc.lines))
    const last = view.state.doc.line(Math.min(Math.max(line.number, end || line.number), view.state.doc.lines))
    view.dispatch({ selection: end ? { anchor: line.from, head: last.to } : { anchor: line.from }, effects: EditorView.scrollIntoView(line.from, { y: 'center' }) })
    view.focus()
    return true
  },
  async declaration() {
    if (!view) return false
    const reply = await post(Object.assign({ lsp: 'textDocument/definition', path: state.path, text: view.state.doc.toString() }, at(view.state.selection.main.head)))
    const first = Array.isArray(reply) ? reply[0] : reply
    if (!first) return false
    const range = first.targetSelectionRange || first.range
    post({ goto: first.targetUri || first.uri, line: range ? range.start.line + 1 : 1 })
    return true
  },
  spot() {
    const ed = pair ? (side === 'a' ? pair.a : pair.b) : view
    if (!ed) return { line: 1, end: 1, text: '', side: '' }
    const range = ed.state.selection.main
    const first = ed.state.doc.lineAt(range.from)
    const last = ed.state.doc.lineAt(range.to)
    return { line: first.number, end: last.number, text: ed.state.sliceDoc(first.from, last.to), side: pair ? (side === 'a' ? 'base' : 'proposed') : '' }
  },
  region(target) {
    return seek(target)
  },
  zoom(step) {
    zoom(state.media === 'image' || state.media === 'pdf' || (fronted === 'preview' && document.querySelector('.mar-editor-frame-preview')) ? 'preview' : 'code', step)
    return true
  },
  loose() {
    free = true
    requestAnimationFrame(centre)
    return true
  },
  format() {
    return tidy()
  },
  stats() {
    stats()
    return true
  },
  vitals(v) {
    readout.value = 'cpu ' + Math.round(v.cpu * 100) + '% · memory ' + Math.round(v.mem * 100) + '% · ' + v.busy + (v.busy === 1 ? ' busy agent' : ' busy agents')
    return true
  },
  focus() {
    if (view) view.focus()
    else if (pair) (side === 'a' ? pair.a : pair.b).focus()
    return true
  },
  diagnose(path, list) {
    if (path === state.path) state.diagnostics = list
    return true
  }
}

const theme = useTheme()
theme.init()
theme.setTheme('dark')

createApp({
  setup() {
    return function () {
      const slots = {
        default: function () {
          if (state.review) return h(Tree)
          if (state.media === 'video') return h('div', { class: 'media' }, h('video', { key: state.url, src: state.url, controls: true, autoplay: false }))
          if (state.media === 'audio') return h('div', { class: 'media' }, h('audio', { key: state.url, src: state.url, controls: true }))
          if (state.media === 'image') return [h('div', { class: 'media' }, h('img', { key: state.url, src: state.url })), h(Zoomer, { pane: 'preview' })]
          if (state.media === 'pdf') return [h('iframe', { key: state.url, class: 'web', src: state.url }), h(Zoomer, { pane: 'preview' })]
          if (state.sides && state.path) return [h(Sides, { key: state.key + ':sides' }), h(Zoomer, { pane: 'code' })]
          return state.path
            ? [h(MarCode, { key: state.key, modelValue: state.text, language: state.language, fill: true, lineWrap: state.kind !== '', 'onUpdate:modelValue': changed, diagnostics: state.diagnostics, 'onUpdate:diagnostics': function (v) { state.diagnostics = v }, onVnodeMounted: function (node) { nextTick(function () { attach(node.component.exposed) }) } }), h(Zoomer, { pane: 'code' })]
            : h(Idle)
        }
      }
      if (state.kind === 'markdown') slots.preview = function () { return [h('div', { class: 'preview' }, h(MarBlockReader, { key: state.path, modelValue: state.live, contentType: 'markdown' })), h(Zoomer, { pane: 'preview' })] }
      if (state.kind === 'html') slots.preview = function () { return [h('iframe', { class: 'web', sandbox: 'allow-scripts', srcdoc: '<base href="slyed://file' + encodeURI(state.path.slice(0, state.path.lastIndexOf('/') + 1)) + '">' + framed + state.live }), h(Zoomer, { pane: 'preview' })] }
      if (state.kind === 'svg') slots.preview = function () { return [state.picking ? h('div', { key: 'drawn', class: 'media checker', innerHTML: drawn(state.live) }) : h('div', { key: 'image', class: 'media checker' }, h('img', { src: 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(state.live) })), h(Zoomer, { pane: 'preview' })] }
      return h(MarEditorFrame, { mode: state.kind ? state.mode : 'code', split: 'columns', diagnostics: state.diagnostics }, slots)
    }
  }
}).mount('#app')

post({ ready: true })
