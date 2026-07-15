# Published Source Snapshots

This directory keeps complete tracked source-tree snapshots for every published line used by the final MIR 3.1.9 backport and museum campaign.

Each version directory is an exact export of the corresponding annotated or lightweight Git tag. It includes that line's code, data, tests, scripts, documentation, evidence, and historical distribution inventory. The authoritative release ZIP for each version is also available at `dist/more-infinite-research_<version>.zip` in the `dev` root.

An exact tag snapshot can contain a tag-time publication record. For current GitHub release IDs, asset IDs, hashes, timestamps, and Mod Portal status, use the root `.mir/evidence/<version>/publication.json` files or `.mir/evidence/lower-wave/final-release-ledger.json`; those records are intentionally written after publication and are not retroactively inserted into an immutable tag tree.

These snapshots are development and historical material. They are under `.mir/`, which the release packager must exclude. They do not participate in the modern Factorio 2.1 module graph, compatibility compiler, settings surface, tests, or generated release package.

Use the modern repository root for new development. Use a version directory only to inspect or copy target-specific implementation, test, data, changelog, notes, and documentation. Do not merge a target directory over the modern root: target metadata and API reductions are intentionally local to that historical line.

`index.json` binds every snapshot to its Git commit, root tree object, file count, byte count, and exact distribution SHA-256.
