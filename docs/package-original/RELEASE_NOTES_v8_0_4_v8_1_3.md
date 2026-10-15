# v8.0.4 / Service v8.1.3 Candidate

- Parent engine: v8.0.3 SHA-256 `f474dd21da1357db802113b8e0b906075a1e5ee32c84475e394c42c75c006485`
- New engine source SHA-256: `344a9572c2ada2b3c4e2839f2a91a8416eddb5236eb06963e1b6c0d1b54b3398`
- Audio/USB playback/capture implementation is unchanged.
- Existing actual-Tempo-Master trash LED behavior is retained.
- Master Beat Phase is mirrored to that deck's Play/Pause LED.
- Normal Play/Pause LED output is cached and suppressed only while that deck is actual Tempo Master.
- Cached normal Play/Pause LED state is restored when the deck stops being master.
- No Traktor mapping change is required.
- Installer compiles v8.0.4 before stopping the currently running v8.1.2 service.
