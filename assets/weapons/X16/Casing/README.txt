X16 — Spent 9mm casing for OpenSRS

X16-Spent-Casing.fbx
  One mesh, one material, 284 triangles, 144 geometric vertices.
  At 40 visible instances: 11,360 rendered triangles total.
  Share the mesh and textures between instances; do not duplicate uploads.

Dimensions in studs (X × Y × Z):
  0.09875362 × 0.05145008 × 0.05145008

Origin is at the bounding-box center, (0, 0, 0).
The long axis is X. The open mouth faces +X; the closed case head faces -X.
The export has unit scale. Verify these dimensions in the Roblox import
preview if the importer applies automatic unit conversion.

SOURCE AND SCALE
Derived from Reference cartridge | case exterior in the source project.
The source case is 0.55342084 art units long and 0.28832912 across.
The same source-to-game factor as the FP pistol was used:
  0.17844217530091586
This preserves the source case's proportions and its size relative to FP.
The projectile tip is not included.

GEOMETRY
A 12-sided radial mesh samples the source case's stepped exterior profile.
The rim, extractor groove, body taper and mouth bevel are geometry.
An annular mouth connects to a recessed interior wall and interior floor;
the mouth is genuinely open, not a dark circle painted on a cap.
The case has a continuous, watertight shell despite its visible cavity.
The 284-triangle total includes the interior, lip and closed head.
Circular silhouettes are intentionally faceted to keep the asset light.
This is a visual game prop, with the source artwork's proportions.

TEXTURES — 512 × 512 PNG
X16_Casing_Color.png       sRGB base color
X16_Casing_Normal.png      OpenGL tangent-space normal, positive Y/green
X16_Casing_Roughness.png   non-color; white = rough
X16_Casing_Metalness.png   non-color; white = metal

The exterior is baked from the source case's brass material and evaluated
surface. The new inner wall uses darker, rougher brass. The mouth receives
restrained discoloration. No reference photos are included in these maps.
All four maps share a non-overlapping UV layout and one material.
Assign them to a SurfaceAppearance on the imported MeshPart. Keep the part's
base color white. The normal map's green channel does not need inversion.

EXTRAS AND CHECKS
X16-Spent-Casing.blend is an editable copy with the four textures packed.
X16-Casing-Mouth.png, X16-Casing-Side.png and X16-Casing-Base.png show the
actual re-imported geometry with the delivered textures.
casing-validation.json records the FBX round-trip measurements, count,
center, scale factor and manifold wall check.
release-validation.json records the separate source-cleanup checks.
The original source file and the previously delivered FP/TP assets remain
unchanged. Collision behavior, lifetime and pooling belong to the game.

PUBLIC SOURCE COPY
The cleaned source is X16-2027-Edition-release.blend in the project folder,
two directories above this Casing folder. It retains the source model;
this low-poly spent casing is a separate asset, not a replacement inside it.
Brand-specific names and text are replaced with neutral X16 names, and the
two unlicensed reference photos and their packed data are removed.
The release contains a CC BY 4.0 note for the OpenSRS publication.

Final release audit: all 47 evaluated mesh instances and all 20 material
graphs retain their original geometry, settings and bindings (with neutral
ID names). The unused source finish is retained. The release was reopened
and scanned; only the four original procedural wear/scuff images remain.
