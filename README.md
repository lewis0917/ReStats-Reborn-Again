# ReStats

**ReStats** is a lightweight iOS tweak that brings automated mobile data statistics resetting to iOS 15–18 (Rootless / ElleKit). 

---

## Features

* **Configurable Auto-Reset Intervals:** Choose how often your mobile data statistics automatically reset (*Every 7 Days, Every 14 Days, Monthly (30 Days), Every 60 Days, Every 90 Days*, or *Disabled*).
* **Native Settings Integration:** Injects cleanly directly into the native Mobile Service settings panel.
* **Lightweight & Battery-Friendly:** Avoids heavy persistent background daemons by evaluating reset intervals dynamically when you open your Mobile Service settings.

---

## How It Works & Important Note

ReStats is intentionally designed **without a persistent background daemon** to prevent background battery drain and avoid iOS jetsam memory kills. 

* **On-Demand Evaluation:** The reset check is triggered **only when you open the Mobile Service settings menu**.
* **Billing Cycle Tracking:** If your reset interval elapses while you have not opened the Mobile Service settings, the stats will continue accumulating. The tweak will automatically execute the overdue reset the next time you navigate into the Mobile Service settings page.
* **Best Practice:** For accurate per-cycle app data tracking, open your Mobile Service settings on or near your plan's rollover date to prompt the reset.

---

## Compatibility

* **iOS:** 15.0 – 18.x
* **Architecture:** arm64, arm64e
* **Jailbreak Environment:** Rootless (ElleKit / Dopamine)
