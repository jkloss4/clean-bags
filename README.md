# Clean Bags

Sorts Blizzard's own bags and bank into labeled sections. There's no new bag window: the items stay Blizzard's item
buttons, so clicking, dragging and tooltips work as normal.

Made for WoW: Forever (Interface 16001); also lists retail (Interface 120100), which uses the same bag code.

The bag and bank code comes from the Clean Bags, Clean Bank and Quick Swap features of
[ForeverForge](https://www.curseforge.com/wow/addons/foreverforge) (MIT), without the rest of that suite, its menu or
its minimap button.

## Features

- **Sort Bags into Sections:** the combined backpack (bag menu: *Combine Bags*) is grouped into Quest Items,
  Consumables, Quiver, Reagents, Crafting, Profession Equipment, one section per equipment set, Gear, General, Junk
  and Empty, in an order you choose in the options. Items in a
  section are sorted by quality.
- **Sort Bank into Sections:** the open bank is grouped into the same sections.
- **Quick Swap Buttons:** while the bank is open, each section title gets a button that moves the whole section
  between your bags and the bank. Your Hearthstone always stays in your bags.

Each one can be turned on or off in **Options > AddOns > Clean Bags** (or `/cleanbags`).

## Install

Download `CleanBags-<version>.zip` from the [latest release](../../releases/latest) and extract the `CleanBags` folder
into `World of Warcraft\_classic_beta_\Interface\AddOns\` (retail: `_retail_`).

An addon manager that installs from GitHub releases (e.g. WowUp: *Install from URL* with this repo's URL) can also
install and update it.

Don't run it alongside ForeverForge with its Clean Bags or Clean Bank features on, since both would sort the same bags.

## Developing / releasing

- Test local changes: `.\scripts\install-local.ps1` copies the addon folder into the Forever `AddOns`, then `/reload`.
- After a WoW patch: bump `## Interface:` in `CleanBags/CleanBags.toc`.
- Release: `git tag v1.0.1 && git push --tags`. The [Release workflow](.github/workflows/release.yml) stamps the
  version into the TOC, builds the zip (with a `release.json` for addon managers), and publishes the GitHub release.

## License

MIT ([`LICENSE`](LICENSE), also included in the addon folder), covering both this addon and the ForeverForge code it
is based on.
