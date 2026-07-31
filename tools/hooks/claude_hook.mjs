#!/usr/bin/env node
// PostToolUse hook for Claude Code. Reads the hook payload on stdin, looks at
// the one file that was just written, and answers in the same turn:
//
//   *.gd    gdlint from the project venv
//   *.tscn  tools/hooks/check_scene.tscn loads and instantiates that scene
//
// Anything else exits 0 without spawning a process, so the hook is free on
// markdown, .tres and everything outside the project.
//
// Exit codes are the Claude Code contract, not the linter's:
//   0  nothing to say
//   2  findings — stderr is shown to Claude, and PostToolUse cannot block, so
//      this reports without stopping the turn (the rule in
//      godot-pixel-stack-setup.md §5.3: warnings must not halt the agent)
//
// A tool crash or a timeout also exits 0. A broken hook must never be the
// reason a session stops.
//
// Nothing here is machine-specific: both tools are discovered, and either can
// be pinned with an environment variable. A fresh clone with no toolchain says
// so once per edit and names the script that fixes it, rather than failing
// silently — see tools/setup_claude.sh.

import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

// Derived from this file's own location, not from cwd or an environment
// variable: the hook has to find the venv and the probe scene whatever the
// harness happens to set.
const PROJECT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')

const LINT_TIMEOUT_MS = 30_000
// A scene check boots the whole project; warm, it comes back in well under a
// second. 90 s is slack, not an expectation — the point of the cap is that a
// scene which opens a dialog or spins in _init cannot hang the session.
const SCENE_TIMEOUT_MS = 90_000

const SETUP_HINT = 'Run: bash tools/setup_claude.sh'

function readStdin() {
  try {
    return readFileSync(0, 'utf8')
  } catch {
    return ''
  }
}

/** First existing path, or null. */
function firstExisting(candidates) {
  for (const c of candidates) {
    if (c && existsSync(c)) return c
  }
  return null
}

/** A bare command name that the OS can resolve on PATH, or null. */
function onPath(command) {
  const probe = spawnSync(command, ['--version'], { encoding: 'utf8', timeout: 10_000 })
  return !probe.error && probe.status === 0 ? command : null
}

function findGdlint() {
  const found = firstExisting([
    process.env.GDLINT,
    path.join(PROJECT_DIR, '.venv', 'Scripts', 'gdlint.exe'),
    path.join(PROJECT_DIR, '.venv', 'bin', 'gdlint'),
  ])
  return found ?? onPath('gdlint')
}

function findGodot() {
  const explicit = firstExisting([process.env.GODOT_CLI, process.env.GODOT])
  if (explicit) return explicit

  // The standalone download unpacks as Godot_v<version>-stable_win64_console.exe.
  // Take the last by name so a newer version wins when both are kept.
  const toolsDir = process.env.GODOT_DIR || 'C:/tools/godot'
  try {
    const consoles = readdirSync(toolsDir)
      .filter((f) => f.includes('console') && f.endsWith('.exe'))
      .sort()
    if (consoles.length > 0) return path.join(toolsDir, consoles[consoles.length - 1])
  } catch {
    // no such directory — fall through
  }

  return onPath('godot')
}

function main() {
  let payload
  try {
    payload = JSON.parse(readStdin() || '{}')
  } catch {
    return 0
  }

  const raw = payload.tool_input?.file_path
  if (typeof raw !== 'string' || raw === '') return 0

  // Claude passes an absolute path; a relative one is resolved against the
  // project, which is the only root a relative path here could mean.
  const file = path.resolve(PROJECT_DIR, raw)
  const ext = path.extname(file).toLowerCase()
  if (ext !== '.gd' && ext !== '.tscn') return 0
  if (!existsSync(file)) return 0

  // Addons are somebody else's code; the project does not lint them.
  const rel = path.relative(PROJECT_DIR, file).split(path.sep).join('/')
  if (rel.startsWith('..') || rel.startsWith('addons/') || rel.startsWith('.venv/')) return 0

  return ext === '.gd' ? lintScript(file, rel) : checkScene(rel)
}

function lintScript(file, rel) {
  const gdlint = findGdlint()
  if (!gdlint) {
    process.stderr.write(`gdlint not installed, so ${rel} went unchecked. ${SETUP_HINT}\n`)
    return 2
  }

  const run = spawnSync(gdlint, [file], {
    cwd: PROJECT_DIR,
    encoding: 'utf8',
    timeout: LINT_TIMEOUT_MS,
  })
  if (run.error || run.status === null) return 0
  if (run.status === 0) return 0

  const report = `${run.stdout || ''}${run.stderr || ''}`.trim()
  process.stderr.write(`gdlint — ${rel}\n${report}\n`)
  return 2
}

function checkScene(rel) {
  const godot = findGodot()
  if (!godot) {
    process.stderr.write(
      `no Godot binary found, so ${rel} went unchecked. ${SETUP_HINT}, or set GODOT_CLI ` +
        'to the console build (the GUI exe writes nothing to a terminal).\n'
    )
    return 2
  }

  const run = spawnSync(
    godot,
    ['--headless', '--path', PROJECT_DIR, 'tools/hooks/check_scene.tscn', '--', `res://${rel}`],
    { cwd: PROJECT_DIR, encoding: 'utf8', timeout: SCENE_TIMEOUT_MS }
  )
  if (run.error || run.status === null) return 0

  // Two noises every headless run of this project emits at exit, unrelated to
  // whatever was just edited. Keeping them would train the reader to skim.
  const noise =
    /ObjectDB instances were leaked|resources still in use at exit|^\s*at: |^\s*GDScript backtrace|^\s*\[\d+\] /
  const report = `${run.stdout || ''}\n${run.stderr || ''}`
    .split('\n')
    .filter((line) => line.trim() !== '' && !noise.test(line))

  // A scene whose ext_resource is gone still produces a PackedScene, so the
  // exit code alone is not the whole answer — Godot reports the casualty and
  // carries on. Any surviving ERROR/SCRIPT ERROR line is a finding.
  const broken = report.some((line) => /^(ERROR|SCRIPT ERROR|WARNING: Error)/.test(line))
  if (run.status === 0 && !broken) return 0

  process.stderr.write(`scene did not load clean — ${rel}\n${report.join('\n')}\n`)
  return 2
}

process.exit(main())
