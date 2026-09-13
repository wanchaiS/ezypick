# FoodSwipe — Assessment 1 Content Pack

*App Design Development Process — from Big Idea to Lo-Fi sketch*

**Pitch line:** One gesture, one answer to "where should we eat?" — FoodSwipe picks the restaurant, you enjoy the meal.

> **How to use this doc:** Each stage has two layers — the **notes** (the full thinking + material for the on-screen visuals) and a **🎙 Narration** line (the actual words to say in the video). The narration lines together form your ~2-minute transcript (target ≈ 280 spoken words total, so each stays short). Read only the 🎙 lines aloud; everything else is reference and visual source.

---

## 1. Big Idea

**Decision fatigue** — the mental load of everyday choices.

We make dozens of small decisions a day, and they quietly wear us out. This project looks at one of the most common: *deciding where to eat.*

**🎙 Narration (≈11s):** "We make dozens of tiny decisions every day, and they quietly wear us out. One of the most common? Deciding where to eat. So my big idea is decision fatigue."

---

## 2. Essential Question

**"How might we take the stress out of deciding where to eat?"**

**Rationale:** Deciding where to eat is one of the most common everyday decisions — and a deceptively draining one. It depends on many competing factors at once (craving, weather, time constraints, budget, who you're with), and it gets even harder in a group, where each person may have a different answer to each factor, making it hard to find common ground.

**🎙 Narration (≈12s):** "So my essential question is: how might we take the stress out of deciding where to eat? It sounds simple, but it depends on so many things at once — and it's even harder with a group."

---

## 3. Challenge Statement

**"Create a way to turn all the factors behind choosing a restaurant into a few simple yes/no questions."**

**How it aligns with the essential question:** The essential question is about removing the *stress of choosing a place*. Choosing a restaurant is really a juggling act of many competing factors at once — and that overload *is* the stress. This challenge breaks the tangle into one easy yes/no decision at a time, lets the app auto-handle the factual factors (distance, weather, reviews, opening hours), and then presents the most likely matches — so the user thinks less and still gets a confident answer.

### Challenge Mind Map (describe on screen)

```
      PERSONAL FACTORS  (subjective)          PRACTICAL FACTORS  (factual)
      ├─ Craving / cuisine                     ├─ Distance / location
      ├─ Vibe  (cozy? lively?)                 ├─ Weather right now
 ┌────┤─ Time  (quick bite / long meal)   ─────┤─ Reviews & rating
 │    ├─ Dietary  (veg / halal / allergies)    ├─ Open now?
 │    └─ Budget  ($ – $$$)                      └─ How busy / wait
 │
 DECIDING WHERE TO EAT  =  juggling many factors at once
 │
 ▼   turn every factor into a simple YES / NO question
 ▼   →  point to the best-fit restaurants
```

**🎙 Narration (≈11s):** "That became my challenge: take all those factors — cuisine, vibe, budget, timing — and turn them into a few simple yes-or-no questions anyone can answer in seconds."

---

## 4. Domain Investigation

**Domain:** How people decide where to eat — on their own and in groups.

**Guiding questions I set out to answer:**
- How do people currently decide where to eat, and how long does it take?
- What frustrates them most about the way they do it now?
- How is deciding *alone* different from deciding *with friends*?
- What finally makes them (or the whole group) commit to a place?

**Research method:** I asked friends and classmates — a quick, informal survey about how they choose a restaurant and where they get stuck. It's first-hand input from exactly the kind of people this app is for.

**What I found:** Deciding alone, most people just default to the same few spots. Deciding as a group, they go back and forth for ages — because everyone wants something slightly different. The pain isn't a lack of options; it's *agreeing* on one.

*(Swap in your own real quotes/numbers from asking friends — e.g. "4 of 5 friends said choosing with a group is the worst part.")*

**🎙 Narration (≈12s):** "To dig in, I asked friends how they actually pick a place. On their own, they default to the same spots — but in a group, they go round in circles, because everyone wants something a little different."

---

## 5. Domain Persona

**Alex — 23, works in the heart of the city (young professional)**

| | |
|---|---|
| **Lifestyle** | Works downtown, surrounded by restaurants; eats out or gets takeaway most days, sometimes with colleagues |
| **Behaviour (solo)** | Falls back to the same 4-option Chinese takeaway every time — picks it because it's easy, not because it's best |
| **Behaviour (group)** | Lunches with colleagues stall because everyone pushes the "who picks?" responsibility onto someone else |
| **Goals** | Decide fast without the mental effort; occasionally try somewhere new; end the group "you decide" standoff |
| **Frustrations** | Too many options nearby, no energy to explore, decision fatigue, and no one willing to commit in a group |
| **Quote** | *"I'm surrounded by restaurants, but I still get the same takeaway — it's easier than choosing."* |

Alex represents the core user: spoiled for choice yet stuck in a rut — defaulting to the familiar when alone, and deadlocked when deciding with others.

---

## 6. Problem / Opportunity Statement

**Problem:** Busy young people waste time and energy deciding which restaurant to go to, because review and map apps are built for browsing endless listings — not for making a decision — and offer no way to agree as a group.

**Opportunity:** There's an opportunity to turn "where should we eat?" from a drawn-out negotiation into a fast, confident choice — by compressing all the factors people weigh (craving, vibe, timing, dietary, budget, distance, weather, reviews) into a few simple swipes, letting the app do the heavy lifting, and recommending one restaurant that fits, solo or for the whole group.

---

## 7. Generating Solution Concepts — Mind Map

```
                          ┌── Swipe yes/no on cuisine + vibe             ─┐
                          │      (Italian? cozy? lively?)                 │
                          ├── Swipe yes/no on situation                   ├─ COMBINE → one swipe flow ★
                          │      (quick bite / long meal? veg? budget?)  ─┘
   HELP USER DECIDE ──────┤
     WHERE TO EAT         ├── App auto-weighs facts (distance,           ★
                          │      weather, reviews, open now)
                          │
                          ├── Individual mode (your restaurant)          ★
                          ├── Group mode (blend everyone → one place)    ★
                          │
                          ├── Map / list browse                          (cut → that's the old way)
                          └── "Surprise me" randomiser                    (cut → minor feature)
```

★ = kept in the final concept (see decision matrix).

---

## 8. Selecting ONE Solution Concept — Decision Matrix

My ONE chosen concept is **"a swipe-based restaurant decider, offered in Individual and Group modes."** I scored each candidate idea **1–5** (5 = best), then noticed the two top mechanics are the *same gesture* and merge into one flow, which is simply run solo or shared.

| Solution Concept | Solves the problem | User appeal | Feasibility | Originality | Fits 2-min demo | **Total** | Role in final app |
|---|:--:|:--:|:--:|:--:|:--:|:--:|---|
| **Swipe yes/no on cuisines** ★ | 5 | 5 | 4 | 4 | 5 | **23** | Core flow (what food) |
| **Swipe yes/no on vibe** ★ | 5 | 4 | 4 | 4 | 4 | **21** | Core flow (what setting) |
| **Group swipe & blend** ★ | 5 | 5 | 3 | 5 | 4 | **22** | Group mode |
| Map / list browse | 2 | 3 | 5 | 1 | 3 | 14 | Cut (the current painful way) |
| Surprise me / roulette | 3 | 4 | 5 | 2 | 4 | 18 | Cut (minor feature) |

**Chosen concept: one swipe-based flow (cuisine + vibe → a restaurant), offered in Individual and Group modes.**

**Justification:** The two highest-scoring mechanics — swiping cuisines and swiping vibe — are the *same action*, so instead of choosing between them I merged them into one seamless flow. Group swipe scored just as high and is that *same flow shared*, so it becomes the second mode rather than a separate product. Map/list browsing scored lowest because it *is* the current painful experience, and the roulette is better as a small feature. The result is one focused, original concept: *decide where to eat with a few swipes, alone or together.*

---

## 9. Domain / Applied Investigation — Guiding Questions & Activities

Plan for turning the chosen concept into a prototype:

| Guiding Question | Activity |
|---|---|
| Which factors should we *ask* (swipe) vs *auto-detect*? | Sort factors into "ask the user" (craving, vibe, timing, diet, budget) vs "app knows" (distance, weather, reviews, open now) |
| Which yes/no questions best narrow down a restaurant? | Draft 5–6 swipe cards; test which combos give a good match |
| What should a restaurant result card show to feel trustworthy? | Card-sort: rank attributes (name, cuisine, vibe tags, distance, rating, price) |
| How does Group mode blend everyone's swipes into one place? | Sketch the group flow; define the "best overlap wins" rule |
| Does the swipe flow feel quick and natural in both modes? | Build a clickable prototype; usability test with 5 users |
| What's the minimum flow for version 1? | Map the core screens: home → swipe cards → restaurant result |

---

## 10. App Statement & Lo-Fi Sketch

**App Statement:**
*"FoodSwipe is a mobile app that helps people decide where to eat — alone or in a group. Through quick yes/no swipes about cuisine and vibe, it recommends one restaurant nearby that fits. In group mode it blends everyone's swipes into a place they'll all enjoy. No endless scrolling, no ordering — just a confident answer to 'where should we go?', so you can get on with the meal."*

### Lo-Fi UI Screens (sketch as rough boxes + labels)

**Screen 1 — Home / Choose mode**
- App logo + tagline "Where should we eat? Just swipe."
- Two big buttons: [ 👤 Individual ]  [ 👥 Group ]
- Location bar at top

**Screen 2 — Cuisine card (swipe)**
- One yes/no card: "Feeling Italian?" (next cards: "Thai?", "Burgers?"…)
- ✕ (no)   ♥ (yes) + progress dots

**Screen 3 — Vibe card (swipe)**
- One yes/no card: "Somewhere cozy?" (next: "Lively?", "Quick & casual?", "Budget-friendly?")
- Same ✕ / ♥ gesture — shows the swipe covers both cuisine and vibe

**Screen 4 — Your Spot (Individual result)**
- "Your spot!" + restaurant name (e.g. "Bella Trattoria")
- Tags: "Italian · Cozy · $$" · "0.8 km · 4.5 rating"
- [ Directions ]   [ Try again ]  ← no ordering

**Screen 5 — Group lobby**
- "Room: FOOD42" + who's joined
- "Everyone swipes on their own phone…"
- Live tally: "3 of 4 done"

**Screen 6 — Group's Spot (Group result)**
- "Your group's spot!" + restaurant name (e.g. "Ramen Bar")
- "Matched 3 of 4 · Asian · Casual · $$" · "1.1 km · 4.4 rating"
- [ Directions ]   [ See runner-up ]

*Tip for the video: show two swipes (a cuisine card + a vibe card) landing on the "Your spot!" restaurant screen — that ~10 seconds proves the whole idea. End on the Group's-Spot screen to show mode two.*
