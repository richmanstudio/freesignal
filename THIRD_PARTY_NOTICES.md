# Third-party notices

FreeSignal is an independent orchestration client. The source repository does **not** bundle zapret, Flowseal strategy packages or WinDivert binaries. Users may download or import independently licensed engine packages through the application.

## zapret

- Project: `bol-van/zapret`
- Copyright: 2016–2026 bol-van and contributors
- License: MIT
- Role: original anti-DPI engine and documentation

## zapret 2

- Project: `bol-van/zapret2`
- Copyright: 2016–2026 bol-van and contributors
- License: MIT, published in `docs/LICENSE.txt`
- Role: experimental next-generation engine adapter target

## Flowseal zapret-discord-youtube

- Project: `Flowseal/zapret-discord-youtube`
- Copyright: Flowseal and contributors
- License: MIT
- Role: Windows distribution, strategy files, domain lists and operational knowledge

FreeSignal's built-in profile names refer to strategy filenames commonly present in that distribution. FreeSignal does not claim authorship of those strategy files.

## WinDivert

- Project: `basil00/Divert`
- Copyright: Basil and contributors
- License: GNU LGPL v3 or GNU GPL v2, with a commercial licensing option from the author
- Role: Windows packet capture/diversion driver used by Windows zapret engines

When distributing a package that contains WinDivert binaries, the distributor is responsible for complying with the selected WinDivert license, including providing the applicable license text and relinking/modification rights required by the LGPL where relevant.
