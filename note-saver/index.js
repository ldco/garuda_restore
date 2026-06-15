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

const USAGE = `Usage: node index.js <command> [args]

Commands:
  save <text>   Append a note with the given text
  read          Print all saved notes`

function printUsage() {
  console.error(USAGE)
  process.exit(1)
}

async function main() {
  const [, , command, ...args] = process.argv

  if (!command) {
    printUsage()
  }

  switch (command) {
    case 'save': {
      const text = args.join(' ')
      if (!text) {
        console.error('Error: "save" requires a text argument.')
        console.error('Usage: node index.js save <text>')
        process.exit(1)
      }
      await saveNote(text)
      console.log('Note saved.')
      break
    }
    case 'read': {
      const notes = await readNotes()
      if (notes.length === 0) {
        console.log('No notes yet.')
      } else {
        for (const note of notes) {
          console.log(`[${note.timestamp}] ${note.text}`)
        }
      }
      break
    }
    default:
      printUsage()
  }
}

const runningDirectly = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]
if (runningDirectly) {
  main().catch((e) => {
    console.error(e.message)
    process.exit(1)
  })
}

export { saveNote, readNotes }
