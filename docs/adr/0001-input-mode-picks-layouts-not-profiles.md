# The input mode picks layouts, not profiles

A player asked for different layouts on the same resolution depending on whether they play with keyboard or controller. We kept a Profile chosen by resolution alone and gave it a Base and Target layout for each Input mode; the current Input mode only picks which of those Edit Mode gets. A Profile's Controller support setting can change the Input mode at login, so if the Input mode chose the Profile, a Profile could switch the mode to one whose Profile switches it back, every login. Picking only layouts keeps the two apart: Controller support never decides which Profile applies, and switching Input mode mid-session only changes layouts, never the addon set or anything else that needs a reload.

## Considered Options

- **Profiles keyed by resolution and Input mode**: each mode gets its own scale, addons, features. Rejected: it can loop through Controller support, and a live switch of Input mode could ask for a reload to change the addon set.
