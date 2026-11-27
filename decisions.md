# Decisions

## 2026-11-26 · Every edge carries 34% and 46% white
- Decided by: agent default while the designer has not answered
- Why: the 8–14% white measured about 1.3:1 against the canvas and the 22% that replaced it about 2.05:1 against a
  surface, both short of the 3:1 non-text floor an edge that carries a boundary has to clear
- Rejected: keeping the softer edges for a quieter page
- Rests on: the platform's non-text contrast recommendation

## 2026-11-26 · A failure is a notice at the bottom edge, not an alert
- Decided by: agent default while the designer has not answered
- Why: a dialog stopped the screen for a sentence worth reading once, and took VoiceOver focus away from where the
  reader was
- Rejected: keeping the alert for every failure, and keeping it only for a session that ended
- Rests on: error recovery without losing the screen, and the notice panel every screen already drew

## 2026-11-26 · Undo covers a progress step as well as a removal
- Decided by: agent default while the designer has not answered
- Why: a stray swipe changed a number the reader would have had to remember to correct
- Rejected: a confirmation dialog before each step, which would tax every deliberate one
- Rests on: reversal as the reader's own, and the six-second bar the list already had

## 2026-11-26 · An empty state is the system's own view
- Decided by: agent default while the designer has not answered
- Why: nine screens stated "nothing here" in two grammars, and the system's view is the shape the reader already knows
- Rejected: one hand-built block styled like the app's own cards
- Rests on: platform convention, and the step out of every dead end

## 2026-11-26 · The appearance stays dark only
- Decided by: the designer, in answer to the init interview
- Why: posters glow against the black, and a light appearance would need its own contrast pass on every token
- Rejected: following the system appearance, and shipping both appearances from one token set
- Rests on: `PRODUCT.md` (constraints) and `DESIGN.md` (the world and its tokens)

## 2026-11-26 · The AniList copy is stated in Settings
- Decided by: the designer's record in `PRODUCT.md`, applied in the interface by an agent default
- Why: a reader editing a score could not know a second account had changed, and the mirror is permanent
- Rejected: a separate About page for it, which the reader would have to find
- Rests on: transparent consequences, and the one-way mirror in `PRODUCT.md`

## 2026-11-26 · The shared models use Observation, not `ObservableObject`
- Decided by: agent default while the designer has not answered
- Why: a body now redraws for the properties it reads rather than for every change on the shared model, and the
  deployment target is iOS 17 where the macro is available
- Rejected: keeping `@Published` and `@EnvironmentObject`, which the platform now supersedes
- Rests on: the SwiftUI review, and a green build


## 2026-11-26 · A list says when it has read every entry
- Decided by: agent default while the designer has not answered
- Why: the count's plus sign carried a sentence's worth of meaning in one character, and a list that had read every
  page looked the same as one that stopped
- Rejected: leaving the plus sign alone, and replacing it with a word in the count
- Rests on: natural stopping points, and a reader who can tell a complete list from a partial one

## 2026-11-26 · The tabs answer Command-1 through Command-5
- Decided by: agent default while the designer has not answered
- Why: the tab bar was the only way across the five tabs, and a hardware keyboard had no path to it
- Rejected: visible per-tab controls in each screen's bar, which would add chrome to every page for a shortcut
- Rests on: the one list of tabs in `tabOrder`, and a shortcut that belongs to the tab bar's own action
