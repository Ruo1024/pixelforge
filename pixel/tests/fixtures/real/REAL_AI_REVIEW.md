# M1 Real AI Fixture Review

Date: 2026-06-13

Source: user-provided local validation images from `/Users/ruo/Desktop/pixelforge/test picture`.

License note: these files are archived for this local project validation pass. External redistribution or publication still needs the user's explicit license confirmation.

## Archived Samples

| File | Original file | Review focus | M1 result |
|---|---|---|---|
| `real_ai_01_character.png` | `11b8df8f-d518-4481-b09f-fc7527401ec5.png` | character silhouette, hair blocks, face detail | Pass for M1 smoke: no crash, cleanup output constrained to target size/color budget; visual source has clear pixel grid and readable silhouette |
| `real_ai_02_robot.png` | `41c0e124-ae38-4b24-b96e-e77913077cdb.png` | hard outline, mechanical straight edges, high contrast blocks | Pass for M1 smoke: no crash, cleanup output constrained to target size/color budget; visual source has strong grid cues |
| `real_ai_03_hair_detail.png` | `66c28e2c-7eaf-4767-a00f-dcbeddc56bb2.png` | long thin hair shapes, dense detail, soft color drift | Pass for M1 smoke with risk note: output remains within budget, but fine hair strands are a known stress case for manual grid/preview tuning |

## Automated Check

`tests/integration/test_cleanup_pipeline.gd::test_real_ai_fixture_samples_cleanup_smoke` loads the three archived PNG files, runs the M1 cleanup pipeline with a `base_size` prior of 128, and asserts:

- output max dimension is at most 320 px;
- output color count is at most 16;
- grid detection report is present.

## Manual Review Notes

The three samples cover the M1 handoff concerns that synthetic fixtures do not fully model: soft AI edges, non-uniform local detail, and mixed hard/soft silhouettes. The current conclusion is that they are acceptable as M1 validation fixtures, while `real_ai_03_hair_detail.png` should remain a regression sample for future grid refine and edge-aware resampling improvements.
