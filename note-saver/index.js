#!/usr/bin/env node

import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const DATA_FILE = join(__dirname, 'notes.json')

async function readNotes() {
  if (!existsSync(DATA_FILE)) {
    return []
  }

  let raw
  try {
    raw = await readFile(DATA_FILE, 'utf-8')
  } catch (e) {
    throw new Error(`Failed to read notes.json: ${e.message}`)
  }

  if (raw.trim() === '') {
    return []
  }

  try {
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) {
      throw new Error('notes.json does not contain a valid JSON array. Delete or fix the file to continue.')
    }
    return parsed
  } catch (e) {
    if (e instanceof SyntaxError) {
      throw new Error(`notes.json contains malformed JSON. Delete or fix the file to continue.\n  ${e.message}`)
    }
    throw e
  }
}

async function saveNote(text) {
  const notes = await readNotes()

  notes.push({
    text,
    timestamp: new Date().toISOString(),
  })

  await writeFile(DATA_FILE, JSON.stringify(notes, null, 2) + '\n')
}

export { saveNote, readNotes }
