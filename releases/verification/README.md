# Permanent release records

Each folder identifies one app version and build. Its `verification.json` records the tested source, workflow, host compilers, results, and limits. `assets.json` retains the exact package sizes and SHA-256 digests. `notes.md` preserves the public notes. When a release retires older listings, `retired-releases.json` retains their notes, asset metadata, and preserved tag objects, with the reviewed plan alongside it.

These files are committed to the repository so the essential release evidence survives Actions artifact expiry. Full build logs and interface captures remain temporary workflow artifacts. App and crash-symbol ZIPs are public release assets, rather than duplicate binaries in the source repository.

After a release completes, download its successful publication record and both host logs. Verify the artifact digests, public package hashes, release tag, and protected references. Copy the publication record here, add a compact `verification.json` based on the completed jobs, and commit the records with `[skip ci]`. Record unverified hardware checks separately from passed simulations and builds. Do not rebuild an already verified app to add this documentation.

- [2.0.5, build 156](2.0.5-156/verification.json): unpublished buffer correction. Both host jobs passed 123 Swift tests, 55 fixtures, both app builds, and native interfaces; local package checks passed. The final native download check is blocked before execution by Mac runner allocation. Physical confirmation and the final handover remain pending.
- [2.0.5, build 155](2.0.5-155/verification.json): unpublished connection-correction candidate with a diagnosed USB buffer crash on macOS 14.7.1. Its earlier hosted checks passed; preserve its source and symbols for comparison.
- [2.0.4, build 154](2.0.4-154/verification.json): current release, with the completed Help review, both host builds, native download verification, and the subsequent requested retirement of 2.0.3. Only 1.5.1 and 2.0.4 remain published.
- [2.0.3, build 153](2.0.3-153/verification.json): retired modern release, with its original verification and the retirement of both 2.0.2 listings preserved. Its own retirement is recorded under 2.0.4.
- [2.0.2, build 152](2.0.2-152/verification.json): retired maintenance reissue and verified retirement of the build 151 listing.
- [2.0.2, build 151](2.0.2-151/verification.json): retired original release and retirement of the older 1.x and 2.0 listings.
