# lamport build

A coding agent for the Mac. Open a folder, say what you want, and it reads, edits and runs the code
there. Edits and commands wait for your OK, the diff updates as it works, and a real shell sits next to it.

Native SwiftUI: sessions on the left, the conversation in the middle, diff and terminal on the right.
Models run through lamport.si with your own sign-in; no provider keys are stored on the Mac.

## build

```
brew install xcodegen
xcodegen generate
open LamportBuild.xcodeproj
```

macOS 14+, Apple silicon. `scripts/release.sh` makes a dmg.

The coding engine is built separately and goes in `engine/` (`lamport-engine` + `engine.json`); it is not
in this repo. Without it the app opens but can't run sessions.

The engine is a rebranded build of an MIT-licensed open-source coding agent. Its license and the licenses
of everything bundled with it are in `Resources/THIRD_PARTY_NOTICES`.

## license

MIT
