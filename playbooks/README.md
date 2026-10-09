# Playbooks

Where a section of *Hand-Me-Down Homelab* installs something, the book tells
you what I built and why. The playbook here is the build itself, written for
your AI assistant to carry out on **your** network.

| Playbook | Section | Builds | Tested |
|---|---|---|---|
| [`3.1-pihole.md`](3.1-pihole.md) | 3.1 Pi-hole: ad blocking and local names | Pi-hole v6 as the house's DNS resolver, with local names | 2026-10-08 |

## How to use one

1. **Read it first.** A playbook is a set of instructions an AI will carry
   out with your permissions. Look at it the way you'd look at an install
   script before running it.
2. **Use a tagged release**, not the live file, so what you read is what
   runs.
3. Start a session with your assistant (the book uses Claude Code; any
   capable assistant that can run commands will do), give it the file, and
   say: *"Follow this playbook. Ask me before every step marked CONFIRM."*
4. Answer its *Discover first* questions with your own values. Nothing in a
   playbook assumes the book's addresses or names.

No AI? Each playbook reads as a checklist. Do the steps yourself, using the
project's own install documentation.

## What every playbook contains

The same sections, in this order, so you know where to look:

- **Rules for the assistant:** discover before assuming, show every command
  and the machine it runs on, ask before risky steps, get current install
  commands from the project's own documentation, keep secrets off command
  lines, verify by effect.
- **Goal:** a checklist of what "done" looks like. It matches the book
  chapter's end-of-chapter checklist.
- **Discover first:** your values, found before anything is installed.
- **Steps:** each with the reason for it and a **Verify** check. Steps that
  change something important are marked **CONFIRM**.
- **Gotchas:** the book's war stories, turned into checks.
- **Rollback:** how to undo it.
- **Next:** where the book goes from here.

## How they're tested

Before a playbook is published, it is run on a clean machine (a fresh
container or virtual machine) and every **Verify** check has to pass. Its
header records what was tested, on what, and which steps were not
exercised. Whatever the test found was folded back into the playbook.
