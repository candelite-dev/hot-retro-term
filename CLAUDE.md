# Repository guidance

Read `README.md` for the supported CMake build, `ARCHITECTURE.md` for ownership,
`docs/DEVELOPMENT.md` for the branch workflow, and `docs/CLEANUP_AUDIT.md` for known
remaining work. Keep those documents aligned with code changes.

- Build/test from the repository root using `./scripts/dev.sh test`.
- Use a Release build when assessing performance.
- QMLTermWidget is included source, not a submodule. KDSingleApplication remains pinned.
- Keep session lifetime in TerminalSessionPool, tab/pane state in SplitTreeModel,
  pure geometry in SplitTree.js, and visual placement in TerminalPane/PaneLayout.
- Session events must not depend on whether a terminal has a visible slot.
- Add a setting to ApplicationSettings.qml and SettingsSchema.js together, including
  its type and relevant constraints. Keep JSON rules in SettingsCodec, I/O recovery
  in SettingsPersistence, and profile-list behavior in ProfileCatalog.
- Parse launch arguments only in app/launchoptions.cpp. Keep child arguments after
  -e opaque. Help and argument errors must work before GUI initialization.
- Rebuild shaders with `cmake --build build/dev --target compile_shaders` after
  changing GLSL. Normal builds currently consume committed `.qsb` files.
- Preserve unrelated branches, stashes, and local work. Avoid history rewrites.

## Private APIs

Using an undocumented/private OS API (e.g. macOS `CGSSetWindowBackgroundBlurRadius`) is allowed when it gives a clear enough benefit — meaningfully simpler implementation, a capability with no public equivalent, etc. — but confirm with the user first before writing code that depends on one, and note in a comment near the call site why the public API wasn't sufficient.
