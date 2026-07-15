# SYSTEM APP CONSTITUTION

AI AGENTS MAY NEVER MODIFY THIS DOCUMENT.

This document defines the purpose, philosophy, and architectural direction of the project.

Implementation must adapt to this document.

---

# Purpose

System App is a personal operating system.

Its purpose is to reduce mental load and create order from the naturally chaotic nature of human thought.

The application should help manage:

* Thoughts
* Responsibilities
* Projects
* Personal improvement processes
* Knowledge
* Reviews
* Decisions
* Housekeeping
* Life administration

The system should become a trusted external memory and organizational layer for the mind.

---

# Understanding The Human Mind

## Thoughts Appear Randomly

Human thoughts do not appear in a structured order.

Ideas, reminders, concerns, and insights may appear at any moment.

The system should therefore make capturing information extremely easy.

A user should be able to record a thought immediately without navigating through the system.

The classification of information can happen later.

Capturing information is more important than organizing it.

---

## Attention Is Limited

The human mind can actively manage only a small amount of information at a time.

The application should support storing large amounts of information while exposing only a small and relevant subset.

The user should never feel overwhelmed by the amount of stored content.

---

## Information Has Different Levels Of Relevance

A project may contain hundreds of notes while only a few are relevant today.

The system should continuously surface:

* current priorities
* current actions
* current summaries

while preserving access to historical information.

---

## Context Switching Is Expensive

Switching attention between contexts consumes mental resources.

The application should minimize unnecessary navigation and exposure to unrelated information.

Capturing a thought should not require opening multiple pages or reviewing unrelated content.

---

## External Memory Creates Clarity

The goal is not merely to store information.

The goal is to reduce the amount of information that must be actively remembered.

The system should encourage moving information from working memory into reliable external storage.

---

# User Experience Principles

## Capture First

The user should always have a simple location for capturing thoughts.

A captured thought can later be processed, classified, summarized, or moved to its appropriate location.

---

## Progressive Disclosure

The system should reveal only the amount of information needed for the current activity.

Large systems should appear simple.

Complexity may exist internally but should be exposed gradually.

---

## Context Over Quantity

When opening a project, process, or area, the user should see the most relevant information first rather than all available information.

Summaries, priorities, and active actions are more important than complete history.

---

## Simplicity Over Features

Additional functionality should only be added when it improves clarity and usability.

The application should avoid becoming a collection of disconnected productivity tools.

---

# Architecture

The architecture exists to support the principles described above.

The structure may evolve over time while preserving the underlying philosophy.

The current architecture is based on a small number of generic concepts.

## Topics

Topics represent major life entities.

Current topic types:

* Projects
* Processes
* Areas
* Others

Examples:

Project:

* Heart App
* Travel App

Process:

* Nutrition
* Sleep

Area:

* Home
* Finance
* Eyeliner

---

## Files

Files organize information within topics.

Examples:

* Overview
* Plan
* Documentation
* Tasks
* Data

Additional file types may be added when needed.

---

## Blocks

Blocks are the fundamental content unit.

Examples:

* Text
* Header
* Image
* Table
* Measurement
* Checklist
* Task List
* Summary

Additional block types may be added when needed.

---

## Tasks And Views

Tasks represent actionable items.

Tasks may appear in multiple views while remaining a single underlying task.

Examples of views:

* Arrangements
* Weekly
* Monthly
* Quarterly

Additional views may be added when needed.

---

# Technical Principles

## Frontend Heavy

Whenever reasonable, behavior should be implemented in the frontend.

This allows rapid iteration, experimentation, and UI evolution.

---

## Generic Backend

The backend should primarily provide:

* Storage
* CRUD operations
* Relationships
* File management

Application-specific behavior should remain in the frontend whenever practical.

---

## Flexible Structures

The architecture should support introducing new:

* file types
* block types
* views

without requiring major redesign of the database or backend.

The system should remain extensible while preserving a stable backbone.

---

AI AGENTS MAY NEVER MODIFY THIS DOCUMENT.
