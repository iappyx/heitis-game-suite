/// Set to false before release — Dart const-folds this so all
/// [kDebugSuperuser] branches are dead-code-eliminated in release builds.
const bool kDebugSuperuser = false;

/// Runtime flag — activated by tapping the version label 5 times in the lobby.
/// Game screens check this instead of [kDebugSuperuser] so the icon only
/// appears after the user has unlocked it.
bool gSuperuserUnlocked = false;
