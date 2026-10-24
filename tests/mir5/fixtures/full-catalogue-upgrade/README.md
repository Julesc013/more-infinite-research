# Full F200 catalogue upgrade fixture

This private two-stage fixture uses the frozen `modern-f200-470.json` oracle to exercise one 4.7.20002 to MIR5 saved-game transition for Base and Space Age. It explicitly level-seeds every recovered non-scripted public technology and each retained Space Age native owner. The two scripted carrier IDs are checked for presence but deliberately not seeded; their runtime behavior belongs to separate scripted-effect qualifications.

The only actual research work is one gear level before and one after the configuration transition. The saved source state retains a 42% current gear queue and a separate force's detached 27% gear progress. The paused force's complete declared technology, recipe, native-force, and gun-effect snapshot is also retained across the upgrade and cold reloads. Recipe bonuses and explicit native force effect fields are snapshotted before and after the upgrade. The named hidden zero-credit carriers are allowed only when their exact private identities are disabled and effect-free.

Native execution is required. The focused Python test proves static oracle closure, data-stage guard behavior, profile closure, and callback boundaries; it does not simulate Factorio research or configuration migration.
