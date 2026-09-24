# Trainer

An iPhone workout logger for the 5-week **High Intensity Volume Training (H.I.V.T.)** program. Open the app at the gym and it shows today's workout. Swipe through the exercises and tap a set to log it. The rest timer starts on its own.

<p align="center">
  <img src="docs/screenshots/today.png" width="220" alt="Today's workout with rest timer">
  <img src="docs/screenshots/calendar.png" width="220" alt="Program calendar">
  <img src="docs/screenshots/today-dark.png" width="220" alt="Workout in dark mode">
  <img src="docs/screenshots/settings.png" width="220" alt="Settings">
</p>

## Features

- **Today's workout.** The app maps the current date to a program day: a workout, a rest day, or a date outside the program. Swipe between exercises, or jump to one from the numbered strip. The header tracks sets done and total workout time.
- **Quick set logging.** Each set and drop set has weight and rep steppers and a big check button. Weights are prefilled from the set above or from your last session. The "Last 50 × 12" hint shows what you did last time.
- **Rest timer.** Checking a set starts that set's rest countdown, with +15s and Skip buttons. A local notification fires when rest ends, even if the phone is locked or you're in another app.
- **Exercise timers.** A per-exercise stopwatch starts when you log the first set and stops after the last one. You can also pause, resume, or reset it manually. Only one exercise timer runs at a time.
- **Reference photos and coach tips.** Every exercise has a start and end photo (tap to view full screen, pinch to zoom) and the program's coaching notes.
- **Calendar.** Days are color-coded by muscle group, with markers for completed and partial workouts. Tap a day to see its exercises, per-exercise times, and total workout time, or to open that day's workout.
- **Extra sets.** Add sets beyond the plan; long-press an extra set to delete it.
- **Settings.** Choose the Day 1 start date or pick which program day today is. Choose whether the 5-week cycle repeats, and whether weights are in kg or lb.
- Supports light and dark mode. The screen stays awake during a workout.

## The program

The program comes from the H.I.V.T. PDF and is bundled as [`Trainer/Resources/program.json`](Trainer/Resources/program.json). It runs 35 days (5 weeks), with 6 training days and 1 rest day each week. The split is:

| Day | Workout |
| --- | --- |
| 1 | Shoulder (Push Emphasis) & Triceps |
| 2 | Back (Width / Thickness Emphasis) |
| 3 | Chest (Upper) & Biceps |
| 4 | Shoulder (Pull Emphasis) & Triceps |
| 5 | Chest (Mid/Lower) & Biceps |
| 6 | Legs (Quad / Hamstring Emphasis) |
| 7 | Rest |

Each exercise lists its muscle group, equipment, optional tip, reference image, and its sets. A set has a target (such as `"10 to 12 reps"` or `"To failure"`), the rest time in seconds, and any drop sets:

```json
{
  "name": "Seated Dumbbell Press",
  "muscle": "Shoulders",
  "equipment": "Dumbbell",
  "tip": null,
  "sets": [
    { "kind": "Standard", "target": "12 reps", "rest": 45, "drops": [] }
  ],
  "image": "ex-seated-dumbbell-press"
}
```

Edit this file to change the program. Images are looked up by name in `Trainer/Resources/ExercisePhotos/`.

## Requirements

- Xcode 16 or later
- iOS 17.0 or later (iPhone only)
- No third-party dependencies. The app uses SwiftUI, SwiftData, and UserNotifications.

## Getting started

1. Open `Trainer.xcodeproj` in Xcode.
2. Select the **Trainer** scheme and an iPhone simulator or device.
3. Build and run (⌘R).

On first launch, the program starts today. Allow notifications so the rest timer can alert you. To run on a physical device, set your own signing team in **Signing & Capabilities**.

## Project structure

```
Trainer/
├── TrainerApp.swift          # App entry, notification delegate, tab bar
├── Models/
│   ├── Program.swift         # Program JSON types, schedule → program-day mapping, settings keys
│   ├── SetLog.swift          # SwiftData: one logged set/drop per date
│   ├── ExerciseTiming.swift  # SwiftData: per-exercise stopwatch + timing rules
│   └── RestTimer.swift       # Rest countdown + local notification
├── Views/
│   ├── WorkoutDayView.swift  # Today tab, rest-day view, swipeable workout pager
│   ├── ExercisePage.swift    # One exercise: timer, photo, tip, set rows
│   ├── SetRow.swift          # Weight/reps steppers + done button
│   ├── RestTimerBanner.swift # Floating rest countdown
│   ├── CalendarScreen.swift  # Month grid + selected-day summary
│   └── SettingsView.swift    # Start date, repeat, units
└── Resources/
    ├── program.json          # The 5-week program
    └── ExercisePhotos/       # Start/end reference photos
Scripts/
└── make-icon.swift           # Generates the app icon variants
```

Workout history is stored on the device with SwiftData. Settings are kept in `UserDefaults`.

## App icon

`Scripts/make-icon.swift` draws the icon with Core Graphics. It generates the default, dark, and tinted variants:

```sh
swift Scripts/make-icon.swift default Trainer/Assets.xcassets/AppIcon.appiconset/icon.png
swift Scripts/make-icon.swift dark    Trainer/Assets.xcassets/AppIcon.appiconset/icon-dark.png
swift Scripts/make-icon.swift tinted  Trainer/Assets.xcassets/AppIcon.appiconset/icon-tinted.png
```
