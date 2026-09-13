# Ezypick

An iOS app that decides where to eat lunch, by doing the research first and then asking you a couple
of yes/no questions.

Built for Advanced iOS Development, Assessment 2, continuing the concept pitched in Assessment 1.

## The problem

Alex is 23 and works in the Sydney CBD. He is surrounded by places to eat and still gets the same
takeaway most days, because choosing is work and by midday he has none left in him. Maps and review
apps do not help: they are built for browsing forty options, and browsing forty options is the
problem, not the solution.

The decision hides a dozen factors at once — what he can eat, what he can afford, how far he will
walk, what is open, what he actually feels like. Ezypick takes the factual ones off him entirely and
turns what is left into a couple of questions he can answer in a second each.

## How it works

```
Your profile: what you can't eat, what you'll spend, how far you'll walk
        │
        ▼
Stage 1 — the research            41 places nearby
  filters on facts                 − 25 can't do gluten-free
  no questions asked                −  7 over $25
                                    −  2 further than 10 minutes
        │                          = 6 fit
        ▼
Stage 2 — the narrowing           "After something light?"  → yes
  questions written from what       6 → 3
  the remaining places disagree
  about. At most five, and it
  stops the moment three remain.
        │
        ▼
Three places, the best one named with its reason.
```

The split between the two stages is the whole design. Anything a phone can determine — price,
opening hours, walking time, dietary listings — is decided silently. Only what lives in a person's
head, or in prose no query can read, is ever asked about.

## Architecture

Five layers, each talking only to the one below it.

| Layer | What lives there |
|---|---|
| **Views** | SwiftUI screens. No decisions. |
| **View Models** | What the screen is showing right now. `ObservableObject`, no rules. |
| **Use Cases** | Every business rule, one struct per operation. |
| **Domain Models** | The vocabulary — restaurants, preferences, questions — plus the protocols for what the app needs from outside. |
| **Data** | The seeded catalogue, `UserDefaults`, the language model. |

The domain and use case layers import nothing but Foundation. They are a Swift package
(`EzypickCore`) that builds and tests without an app target, a simulator, or Xcode.

Full diagram: [`Ezypick-Architecture.excalidraw`](Ezypick-Architecture.excalidraw) — open at
[excalidraw.com](https://excalidraw.com).

### The four use cases

| Use case | The rules it holds |
|---|---|
| `SaveDiningPreferencesUseCase` | A profile must be able to produce a search: a budget, a sane walking time, not every cuisine ruled out. |
| `ShortlistRestaurantsUseCase` | Dietary requirements are absolute. Then budget, walking distance, open at the meal time, and anything already turned down. Counts what each limit excluded, so a failure can name its own cause. |
| `AskNextQuestionsUseCase` | At most five questions. Stop at three or fewer. Never repeat. Never ask anything that would not split the remaining places. |
| `AnswerQuestionUseCase` | An answer may never leave the diner with nowhere to eat. |

### Two protocols, two implementations each

- `RestaurantRepository` — a seeded catalogue of 40 venues today, shaped like a Google Places API
  response so a live adapter can replace it without touching anything above.
- `QuestionGenerator` — `LLMQuestionGenerator` reads the reviews and writes the questions;
  `TemplateQuestionGenerator` picks the most evenly splitting attribute and is used whenever there is
  no key, no network, or nothing usable came back.

The language model is never trusted. `AskNextQuestionsUseCase` checks every question it returns
against the real candidates and discards any that would not narrow anything.

## A note on dietary data

No mainstream places API exposes trustworthy gluten-free, halal or allergen information. Google has
a single sparse `servesVegetarianFood` flag; Apple MapKit has nothing at all.

So Ezypick filters on the dietary data it holds and **never claims to have verified it**. Every
suggestion states where its information came from: *"gluten-free options as listed by the restaurant
— worth confirming when you order"*. A system that implies a safety guarantee it cannot make is the
worst failure this app could have.

## Running it

**The app**

1. Open `EzyPick/EzyPick.xcodeproj` in Xcode 16 or later.
2. Pick an iPhone simulator and run. No key, no account, no network needed.
3. Optional: paste an API key into *Your profile → Question service* to have a language model write
   the questions instead of the built-in ones. Everything works without it.

**The tests**

In Xcode: ⌘U with the `EzypickCore` scheme selected.

From a terminal, without Xcode:

```bash
cd EzypickCore
EZYPICK_STANDALONE_TESTING=1 swift test
```

Xcode bundles Swift Testing; the Command Line Tools toolchain does not, which is what that
environment variable is for.

## Tests

28 tests covering the business rules, not the plumbing. Among them:

- A cheaper, closer restaurant of exactly the right cuisine is still excluded when it cannot serve a
  dietary requirement.
- Priced exactly at budget is in; a dollar over is out. Ten minutes' walk is in; eleven is out.
- The app stops at three, never asks a sixth question, and never repeats one.
- A suggested question that would not narrow anything is discarded and replaced.
- When the question service throws, the diner still gets a sensible question.
- End to end against the shipped catalogue: 40 places → 6 after the research → 3 after one question.

## Project layout

```
EzyPick/                      the iOS app
  EzyPick/
    EzyPickApp.swift          builds the parts, picks the implementations
    ViewModels/               screen state, no rules
    Views/                    five screens
EzypickCore/                  domain + business rules, as a Swift package
  Sources/EzypickCore/
    Domain/                   the vocabulary and the protocols
    UseCases/                 the rules
    Infrastructure/           catalogue, storage, question generators
    Resources/                restaurants.json — 40 seeded venues
  Tests/
Ezypick-Architecture.excalidraw
```
