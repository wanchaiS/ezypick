# Ezypick

An iOS app that decides where to eat lunch, by doing the research first and then asking you a couple
of yes/no questions.

Built for Advanced iOS Development, Assessment 2, continuing the concept pitched in Assessment 1.

## The problem

Alex is 23 and works in the Sydney CBD. He is surrounded by places to eat and still gets the same
takeaway most days, because choosing is work and by midday he has none left in him. Maps and review
apps do not help: they are built for browsing forty options, and browsing forty options is the
problem, not the solution.

The decision hides a dozen factors at once: what he can eat, what he can afford, how far he will
walk, what is open, what he actually feels like. Ezypick takes the factual ones off him entirely and
turns what is left into a couple of questions he can answer in a second each.

## How it works

```
Your profile: what you'll spend, how far you'll walk
        │
        ▼
Stage 1, the research             41 places nearby
  filters on facts                 − 25 over $25 a head
  no questions asked                −  7 further than 10 minutes
                                    −  3 shut right now
        │                          = 6 fit
        ▼
Stage 2, the narrowing            "After something light?"  → yes
  questions written from what       6 → 3
  the remaining places disagree
  about. At most five, and it
  stops the moment three remain.
        │
        ▼
Three places, the best one named with its reason.
```

The split between the two stages is the whole design. Anything a phone can determine, from price to
opening hours to walking time, is decided silently. Only what lives in a person's head, or in prose
no query can read, is ever asked about.

## Architecture

Five layers, each talking only to the one below it.

| Layer | What lives there |
|---|---|
| **Views** | SwiftUI screens. No decisions. |
| **View Models** | What the screen is showing right now. `ObservableObject`, no rules. |
| **Use Cases** | Every business rule, one struct per operation. |
| **Domain Models** | The vocabulary of restaurants, preferences and questions, plus the protocols for what the app needs from outside. |
| **Data** | The Google Places API, `UserDefaults`, the language model. |

The domain and use case layers import nothing but Foundation. No SwiftUI, no UIKit, no Core
Location: the rules know nothing about screens or hardware, which is what lets every one of them be
tested without launching the app.

Full diagram: [`Ezypick-Architecture.excalidraw`](Ezypick-Architecture.excalidraw), open at
[excalidraw.com](https://excalidraw.com).

### The five use cases

| Use case | The rules it holds |
|---|---|
| `SurveyNearbyRestaurantsUseCase` | None, deliberately. It describes what the search found without removing anything, so the diner sees the size of the problem before the app starts solving it. |
| `SaveDiningPreferencesUseCase` | A profile must be able to produce a search: a budget, and a walking time a lunch break can absorb. |
| `ShortlistRestaurantsUseCase` | Budget, walking distance, open on the clock right now, and anything already turned down. Counts what each limit excluded, so a failure can name its own cause. |
| `AskNextQuestionsUseCase` | At most five questions. Stop at three or fewer. Never repeat. Never ask anything that would not split the remaining places. |
| `AnswerQuestionUseCase` | An answer may never leave the diner with nowhere to eat. |

### The two protocols

- `RestaurantRepository`: `GooglePlacesRestaurantRepository` asks the device where it is, calls
  `places:searchNearby`, and maps what comes back onto the app's own restaurant type. It is the only
  source of restaurants the app has. It was built against stand-in data shaped like that response,
  and going live cost one new type and not a line of any rule or screen, which is the whole argument
  for putting the protocol there in the first place.
- `QuestionGenerator`: `LLMQuestionGenerator` reads the reviews and writes the questions;
  `TemplateQuestionGenerator` picks the most evenly splitting attribute and covers a service that is
  configured but fails: no network, or nothing usable came back. With **no** service configured the
  app does not fall back at all — it shows what the search found and stops, because narrowing by the
  few booleans a places API asserts is a weaker thing than the app claims to do.

The language model is never trusted. `AskNextQuestionsUseCase` checks every question it returns
against the real candidates and discards any that would not narrow anything.

## A note on dietary data

**Ezypick does not filter on dietary requirements, and that is the most deliberate decision in it.**

It used to, and the veto was the app's hardest business rule. Measuring live data killed it, and the
three settings failed in three different ways. No mainstream places API records gluten-free,
nut-free or allergen information at all, so that one was never answerable. `halal_restaurant` is a
venue category almost nobody publishes — one venue across the whole of the inner city — so ticking
it returned **nothing at all**, wherever the diner stood. `servesVegetarianFood` is the subtle one:
across 57 restaurants probed in the CBD, Surry Hills and Chinatown it came back **48 true, 2 false,
7 absent**, and absent never means no, so a vegetarian veto ruled out two venues in fifty-seven
while looking exactly like a safety check.

Empty, vacuous or absent, not one of the three protected anybody. A veto like that either refuses
everything or changes nothing, teaches the diner to turn it off, and implies the app checked
something it never could. So the filter is gone rather than hedged, and the profile is two honest
settings instead of four, two of which lied.

Anyone building this properly needs a source that records what kitchens actually do. Google is not
one, and saying so is the finding, not the excuse.

## Running it

**The app**

1. Put a Google Places API (New) key in a `.env` at the repository root, as
   `GOOGLE_PLACES_API_KEY=your-key`. The build copies that file into the app bundle. It is
   gitignored, so a fresh clone arrives without one, and with no key the app says so plainly
   instead of pretending to know what is nearby.
2. Open `EzyPick/EzyPick.xcodeproj` in Xcode 16 or later.
3. Pick an iPhone simulator and run, and allow location when it is asked for. The search starts
   from wherever the device says it is, so a simulator needs a location set under Features >
   Location.
4. Optional: add `AI_BASE_URL` and `AI_API_KEY` to the same `.env` for a language model to write the
   questions. Without them the app still does the whole search and shows what it found, then stops
   and says it has not been set up to write questions.

**The tests**

No key, no account, no network. The suite replays a recorded Places response, so it runs the same
on any machine.

In Xcode: ⌘U. The `EzyPick` scheme is shared and runs the `EzyPickTests` target.

From a terminal:

```bash
cd EzyPick
xcodebuild -project EzyPick.xcodeproj -scheme EzyPick \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Tests

Tests covering the business rules, not the plumbing. Among them:

- Priced exactly at budget is in; a dollar over is out. Ten minutes' walk is in; eleven is out.
- A place that shut before the diner looked is ruled out, and when nothing fits at all the failure
  names the limit that did the most damage rather than shrugging.
- The app stops at three, never asks a sixth question, and never repeats one.
- A suggested question that would not narrow anything is discarded and replaced.
- When the question service throws, the diner still gets a sensible question.
- A walking time, a price and an opening hour read out of a Places response stay with the venue
  they belong to, and an attribute the API never asserted is never claimed.
- End to end against a recorded Places response, replayed through a URL stub so the journey never
  touches the network: a real search narrowed by the research, then by the questions, down to a
  shortlist.

## Project layout

```
EzyPick/
  EzyPick.xcodeproj
  EzyPick/                    the app target
    EzyPickApp.swift          builds the parts, picks the implementations
    Domain/                   the vocabulary, and Ports/ for what the app needs from outside
    UseCases/                 the rules
    Infrastructure/           the Places client, location, storage, question generators
    ViewModels/               screen state, no rules
    Views/                    six screens
  EzyPickTests/               the unit tests, and Fixtures/ for recorded API responses
Ezypick-Architecture.excalidraw
.env                          local keys, gitignored
```
