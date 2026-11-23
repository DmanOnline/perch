# Plan: Perch, de beste notch-app op GitHub

Naam: **Perch**: een vogel op de richel, zoals de app bovenop de notch zit. Opgesteld 2026-11-23.

## 1. Doel

Een open-source macOS-app die de MacBook-notch verandert in een Dynamic Island, en die op GitHub de standaard wordt. Niet de meeste features, maar de beste ervaring: stabiel, snel, mooi, en een project dat zichtbaar leeft.

Maatstaf is [boring.notch](https://github.com/TheBoredTeam/boring.notch) (11,4k sterren). Hun zwakke plekken zijn onze kans:

| Zwakte boring.notch | Ons antwoord |
|---|---|
| Laatste stabiele release ruim een jaar oud | Vaste releaseritme, elke 2 à 4 weken |
| 169 open PR's, merges liggen stil sinds oktober | PR's binnen een week beoordeeld; duidelijke CONTRIBUTING |
| Extensieplatform al maanden in 15 ongemergde PR's | Modules en extensies vanaf dag één in de architectuur |
| Notch verdwijnt na slaapstand (#336, 45 reacties) | Slaap/wake, schermwissel en Spaces als eerste testgevallen |
| Views van 1000+ regels, alles aan elkaar gegroeid | Kleine modules met een vast contract |
| Ongetekend, gebruikers moeten quarantaine handmatig verwijderen | Homebrew-cask als hoofdroute; later Developer ID |

## 2. Principes

1. **De notch is het product.** Het venster, de animatie en het gedrag bij hover moeten perfect zijn voordat er features bijkomen.
2. **Alles is een module.** Muziek, batterij, HUD en Claude Code gebruiken allemaal hetzelfde contract. Wat wij intern kunnen, kan een extensie later ook.
3. **Eén ding tegelijk in beeld, met duidelijke voorrang.** Een vaste scheidsrechter bepaalt welke activiteit de notch krijgt, in plaats van dat modules met elkaar vechten.
4. **Zuinig.** Stilstaand onder 1% CPU, geen polling waar een event kan.
5. **Eigen gezicht.** Geen kopie van Alcove of boring.notch; eigen vormtaal, eigen naam, eigen icoon.

## 3. Licentie en hergebruik

Licentie: **GPL-3.0**. Daardoor mogen we code uit boring.notch overnemen, mits met bronvermelding in `THIRD_PARTY_LICENSES` en in de commit. We nemen alleen over wat aantoonbaar werkt en lastig is; de architectuur is van ons.

Gevolg voor extensies: een extensie die in het Perch-proces laadt, moet GPL-compatibel zijn (open source). Een uitzondering voor gesloten extensies, zoals boring.notch nu voorstelt in #1766, kan alleen met toestemming van alle auteurs, dus niet meer zodra we boring.notch-code overnemen. Dat accepteren we: Perch is open source en extensies ook.

| Bouwsteen | Licentie | Gebruik |
|---|---|---|
| [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) | BSD-3 | Now Playing op macOS 15.4+ (privé-framework MediaRemote, via los proces) |
| [Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) | MIT | Venster dat ook boven lockscreen en fullscreen kan staan |
| [MrKai77/DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | MIT | Referentie voor notch-geometrie en animaties; geen harde afhankelijkheid |
| [sindresorhus/Defaults](https://github.com/sindresorhus/Defaults), KeyboardShortcuts, LaunchAtLogin-Modern | MIT | Instellingen, sneltoetsen, opstarten bij inloggen |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT-achtig | Automatische updates |
| boring.notch | GPL-3 | Selectief: NowPlaying-aansturing, HUD-vervanging, slaap/wake-afhandeling |

## 4. Architectuur

```
App (SwiftUI + AppKit, macOS 15+)
├── NotchWindow        venster per scherm, notch-geometrie, hover, slaap/wake, Spaces
├── Arbiter            kiest welke activiteit zichtbaar is (prioriteit, wachtrij, timeouts)
├── ModuleHost         laadt modules, geeft ze een vast contract
│   ├── Module: Music
│   ├── Module: Battery
│   ├── Module: HUD (volume/helderheid)
│   ├── Module: Claude Code
│   └── (later) externe extensie-bundels
├── Services           NowPlaying, Instellingen, Updates, Logging
└── Helper (XPC)       alleen voor wat rechten vraagt (HUD onderscheppen)
```

**Modulecontract** (concept):

| Onderdeel | Wat |
|---|---|
| `compact` | Klein beeld links/rechts van de notch (live activity) |
| `expanded` | Groot beeld als de notch openklapt (tab) |
| `priority` | Hoe belangrijk nu: achtergrond, info, aandacht, urgent |
| `events` | Wanneer de module de notch wil laten "oplichten" |
| `settings` | Eigen instellingenpagina |

**Sandbox: nee.** We gaan niet naar de App Store, en modules zoals Claude Code moeten bestanden buiten de sandbox lezen. Hardened runtime wel.

## 5. Roadmap

| Versie | Thema | Inhoud | Klaar als |
|---|---|---|---|
| **0.1** | Fundament | NotchWindow op alle schermen, hover open/dicht, slaap/wake-bestendig; Music-module (nu speelt, bediening, artwork); instellingen; CI-build; Homebrew-cask | Een week dagelijks gebruik zonder dat de notch verdwijnt |
| **0.2** | Onderscheidend | Claude Code-module (welke sessie werkt, welke wacht op jou, via de officiële Claude Code-hooks); permanent zichtbare sneak peek (#797) | Eerste publieke release met README en demo-GIF |
| **0.3** | Pariteit | HUD-vervanging, batterij en Bluetooth, agenda, bestandsplank met AirDrop | Alles wat boring.notch kan, minimaal even goed |
| **0.4** | Platform | Externe extensies (losse bundels), notificaties spiegelen (#592, meest gevraagd), Liquid Glass-stijl (#922) | Eerste extensie van iemand anders |

Gekozen op basis van de meest gevraagde boring.notch-issues (2026-11-23): notificaties (#592, 13 duimen), altijd zichtbare sneak peek (#797), Liquid Glass (#922), Claude Code-monitoring (#951).

## 6. Kwaliteitslat

- **Tests** op de lastige randen: slaap/wake, scherm erbij/eraf, fullscreen, wisselende notch-maten, Macs zonder notch.
- **Prestatiebudget**: stilstaand < 1% CPU, < 80 MB geheugen; meten in CI.
- **Releases** via GitHub Actions: build, tekenen, dmg, cask bijwerken.
- **README** met demo-GIF in het eerste scherm, installatie in één regel.

## 7. Risico's

| Risico | Aanpak |
|---|---|
| MediaRemote is privé; Apple breekt het per macOS-versie (zie boring.notch #779 op macOS 26) | Achter een interface; fallback naar AppleScript voor Spotify en Music |
| SkyLight is privé-API | Alleen voor lockscreen; zonder valt het terug op een gewoon venster |
| Zonder Developer ID schrikt de installatie mensen af | Homebrew-cask als hoofdroute; Developer ID ($99/jr) overwegen bij 0.2 |
| Te veel tegelijk willen | Per versie één thema; niets van 0.3 vóór 0.2 af is |

## 8. Open keuzes voor Dion

- [x] Naam van de app: Perch (2026-11-23)
- [ ] Bundle-ID en domein (bv. perch.dev of getperch.app)
- [x] Minimum-macOS: 15 Sequoia (2026-11-23). Elke MacBook met notch kan naar 15; alleen oudere Macs zonder notch vallen af
- [ ] Apple Developer ID nemen, nu of bij 0.2
- [ ] Xcode installeren (alleen macOS-platform)
