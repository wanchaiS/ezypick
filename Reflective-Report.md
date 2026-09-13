# Reflective Report — Ezypick

**Peter Wanchai · Advanced iOS Development · Assessment 2**

## What the domain taught me

I started Assessment 2 assuming I would build what I pitched in Assessment 1: a swipe deck of cuisine
and vibe cards ending on one restaurant. Two things I found in the domain changed that.

The first was about the questions. I had assumed "Feeling Italian?" was doing useful work. It is not.
In forty city restaurants only a couple are Thai, so answering no to one cuisine rules out almost
nothing, while "Got time for a proper sit-down?" splits the same set roughly in half. My A1 deck was
the weakest possible narrowing tool, and I had chosen it because it looked good as an interaction
rather than because it decided anything. So the app now generates questions from the restaurants
still in the running instead of a list written in advance.

The second was about dietary requirements. I assumed the data would be there. It is not. Google
Places has one sparse `servesVegetarianFood` flag and no gluten-free field at all, and Apple MapKit
exposes no attributes whatsoever. The hardest rule in my app turned out to be the one rule no data
source will underwrite. I could have hidden that by filtering quietly, but a nut allergy is not
something you quietly get wrong. So the app filters on what it has and says where that came from:
"gluten-free options as listed by the restaurant, worth confirming when you order". It never says
"safe". That wording is a business rule in the code now, not a UI decision.

## Why these use cases

I ended up with four, and each one owns a rule that would cause a real problem if it broke.

`ShortlistRestaurantsUseCase` holds the hard limits: dietary requirements, budget, walking distance,
opening hours, and anything already turned down. It runs before a single question is asked, which
means nothing unsafe or unaffordable ever reaches the part of the app that is less careful. That
ordering is deliberate. It is what lets the question step be simple without being dangerous.

`AskNextQuestionsUseCase` holds the rules about asking: at most five questions, stop as soon as three
restaurants remain, never repeat, and never ask anything the remaining restaurants would all answer
the same way. These matter because the whole point of the app is to reduce effort. An app built to
save someone from choosing cannot then put them through a quiz. In testing it usually stops after one
or two questions, which is better than the five it is allowed.

The other two are smaller but real. `SaveDiningPreferencesUseCase` stops someone saving a profile
that could never return a result, and `AnswerQuestionUseCase` refuses an answer that would leave
them with nowhere to eat.

Putting the language model behind a protocol mattered more than I expected. The model writes the
questions, but the use case checks each one against the real candidates and discards it if it would
not narrow anything. With no key or no network a deterministic generator takes over. The model
phrases; it never decides.

## Where a person can go wrong

The moment I worried about most is the profile screen. Someone sets their walking limit to five
minutes on a rainy day and forgets. Every lunch after that is quietly starved of options, and they
would blame the app rather than the setting.

My answer was to make failure name its own cause. The filtering step counts what each limit excluded,
so when nothing survives, the app can say "the places that fit are all further than you said you'd
walk" and offer to widen it, instead of showing "no results". The count is four integers and it
turns a dead end into something the person can act on in one tap.

The same thinking shaped the profile screen itself. What you cannot eat and what you would rather
not eat sit in separate sections with different explanations, because the app treats them completely
differently. One is never traded away; the other is. If they looked the same on screen, the person
would have no way of knowing that.

## What I would do next

The obvious next step is live restaurant data. Everything sits behind `RestaurantRepository` already,
and the seeded catalogue is shaped like a Google Places response, so the swap should be one new type
and no change to any rule or screen. The harder part is cost: Places charges per field for reviews
and atmosphere data, so a real version has to decide which restaurants are worth fetching in detail,
and when.

After that, group lunches, which I cut from this version. It is the same flow with several people
answering rather than a different problem, and I would rather ship one honest single-user version
than a half-working group one.
