# Agent handoff: package testing

Read `docs/package-testing.md` before changing build configuration or claiming
cross-platform support. The shared harness is `.github/package-check/`.

- Preserve the user's working tree and existing libraries, containers and results.
- Build one source tarball and test its identical SHA256 on every platform.
- Windows diagnostic stubs are not a functional FAISS pass.
- Linux SIFs isolate user space, not the kernel. CPU tests do not validate CUDA.
- Keep host addresses and authentication details in an untracked local config.
- Never publish private keys, alter SSH authorization, or replace system BLAS.
- On the configured Linux host, use the secondary test disk, not the full root disk.
- Do not put test artifacts in the HPC rclone synchronization tree.
- Keep failed runs and logs; use new run directories after fixes.
- A check passes only after its final log exists, completion is recorded, and
  errors/warnings are absent. Explain NOTEs and skipped capability-specific tests.
