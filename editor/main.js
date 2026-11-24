import { createApp, h, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import icon from "./icon.svg?raw"
import { basicSetup } from 'codemirror'
import { oneDark } from '@codemirror/theme-one-dark'
import MarBlockReader from '@/components/MarBlockReader'
import MarCode from '@/components/MarCode'
import MarEditorFrame from '@/components/MarEditorFrame'
import { useTheme } from '@/composables/useTheme'
import '@/assets/baseline.css'
import { Compartment, EditorState, StateEffect, StateField } from '@codemirror/state'
import { HighlightStyle, LanguageDescription, StreamLanguage, syntaxHighlighting } from '@codemirror/language'
import { tags as t } from '@lezer/highlight'
import { languages } from '@codemirror/language-data'
import { MergeView, getChunks, getOriginalDoc, unifiedMergeView } from '@codemirror/merge'
import { Decoration, EditorView, GutterMarker, gutter, hoverTooltip, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import { copyLineDown, deleteLine, moveLineDown, moveLineUp, selectParentSyntax } from '@codemirror/commands'
import { openSearchPanel } from '@codemirror/search'

const keys = Prec.highest(keymap.of([
  { key: 'Mod-d', run: copyLineDown },
  { key: 'Mod-Backspace', run: deleteLine },
  { key: 'Shift-Alt-ArrowUp', run: moveLineUp },
  { key: 'Shift-Alt-ArrowDown', run: moveLineDown },
  { key: 'Shift-Mod-ArrowUp', run: moveLineUp },
  { key: 'Shift-Mod-ArrowDown', run: moveLineDown },
  { key: 'Alt-ArrowUp', run: selectParentSyntax },
  { key: 'Mod-r', run: openSearchPanel }
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

const state = reactive({ path: '', text: '', live: '', kind: '', media: '', url: '', sides: false, locked: false, mode: 'both', language: 'plaintext', diagnostics: [], key: 0, review: null })
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
  view.dispatch({ effects: StateEffect.appendConfig.of([keys, extra.of(support), paint, EditorView.updateListener.of(function (u) { if (u.selectionSet || u.docChanged) recount() }), diffed.of(merge()),EditorState.languageData.of(function () { return [{ autocomplete: complete }] }), hover]) })
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
        a: { doc: original || '', extensions: [basicSetup, oneDark, paint, sideSupport, EditorState.readOnly.of(true), focused('a')].concat(room) },
        b: { doc: current, extensions: [basicSetup, oneDark, paint, sideSupport, focused('b')].concat(editable, room) },
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
          file.why ? h('p', { class: 'why' }, file.why) : null,
          file.hunks.map(function (hunk) {
            return h('div', { key: hunk.id, class: ['hunk', hunk.status, { on: hunk.id === state.review.at }], onClick: function () { post({ hunk: hunk.id }) } }, [
              h('div', { class: 'head' }, [h('b', hunk.label), h('span', hunk.status), hunk.text ? h('q', hunk.text) : null]),
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
          if (state.media === 'image') return h('div', { class: 'media' }, h('img', { key: state.url, src: state.url }))
          if (state.media === 'pdf') return h('iframe', { key: state.url, class: 'web', src: state.url })
          if (state.sides && state.path) return h(Sides, { key: state.key + ':sides' })
          return state.path
            ? h(MarCode, { key: state.key, modelValue: state.text, language: state.language, fill: true, lineWrap: state.kind !== '', 'onUpdate:modelValue': changed, diagnostics: state.diagnostics, 'onUpdate:diagnostics': function (v) { state.diagnostics = v }, onVnodeMounted: function (node) { nextTick(function () { attach(node.component.exposed) }) } })
            : h(Idle)
        }
      }
      if (state.kind === 'markdown') slots.preview = function () { return h('div', { class: 'preview' }, h(MarBlockReader, { key: state.path, modelValue: state.live, contentType: 'markdown' })) }
      if (state.kind === 'html') slots.preview = function () { return h('iframe', { class: 'web', sandbox: 'allow-scripts', srcdoc: '<base href="slyed://file' + encodeURI(state.path.slice(0, state.path.lastIndexOf('/') + 1)) + '">' + state.live }) }
      if (state.kind === 'svg') slots.preview = function () { return h('div', { class: 'media checker' }, h('img', { src: 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(state.live) })) }
      return h(MarEditorFrame, { mode: state.kind ? state.mode : 'code', split: 'columns', diagnostics: state.diagnostics }, slots)
    }
  }
}).mount('#app')

post({ ready: true })
