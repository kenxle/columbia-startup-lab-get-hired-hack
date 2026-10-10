# Embedded Noto fonts

Unmodified Noto Sans Regular, Noto Sans Bold, and Noto Sans Symbols 2 Regular.
Downloaded 2026-10-10 from the `notofonts/noto-fonts` repository:

- https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf/NotoSans
- https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf/NotoSansSymbols2

These fonts are distributed under the SIL Open Font License 1.1 in `LICENSE`.
They are embedded in generated PDFs so exact engineering symbols survive on
machines without the fonts installed. Unsupported characters fail explicitly;
they are never transliterated or silently replaced.
