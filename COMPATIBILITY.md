# Compatibility — SCOOP Cardlink SDK Demos

The demos are customer-facing examples. A demo release is compatible only when
its Android, iOS, and Flutter dependency pins describe the same verified native
and bridge portfolio.

## Evaluation/Pilot release status (2026-07-22)

`ios/v1.4.5` is an immutable historical tag, but it is not a customer portfolio
release candidate. Its Android version catalog still pins Cardlink 4.0.0, NFC
3.0.0, PoPP Module 0.21.0, and PoPP SDK 2.0.0. Its Flutter demos use sibling path
dependencies rather than immutable bridge refs.

The successful physical iPhone verification proves the tested local integration,
not that a clean checkout of this tag resolves the same complete portfolio. Do
not move or overwrite the tag. The next demo version remains undecided until all
platforms consume one exact candidate matrix.
