# Mitsuri theme assets

These assets are local, project-bound visual resources for the built-in
Mitsuri theme. They are kept separate from media posters and are never used by
the default cinema theme.

- `atmosphere-v2.jpg`: original character-free plum silk / blossom atmosphere
  generated for this project through the configured SD WebUI-compatible worker.
- `ribbon-edge.svg`: hand-authored transparent banner-edge ribbon artwork;
  `ribbon-edge.png` is its alpha-preserving 960x560 rasterization for Flutter.
- `signature.png`: earlier signature study retained as an unused source asset.
- `character-hero-cropped.png` is a non-destructive alpha-bound crop derived
  from the existing `character-hero.png`; the original artwork is retained.
- `character-hero.png`, `character-bust.png`, `character.png`: existing
  transparent character artwork retained in the project.
- `chibi-transparent.png`: transparent promotional character artwork already
  present in the project.
- `../../fonts/mitsuri/ZCOOLXiaoWei-Regular.ttf` is the Chinese display face and
  `Allura-Regular.ttf` is used for the Latin signature. Both are from Google
  Fonts and distributed under SIL Open Font License 1.1; the OFL texts are
  included beside the font files.

The configured image worker was tested for a ribbon, but returned an opaque
checkerboard JPEG instead of transparent artwork; that output was rejected.
The app uses the local SVG ribbon and its transparent PNG render instead.
