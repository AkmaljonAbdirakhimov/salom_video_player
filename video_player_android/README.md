# video\_player\_android

The Android implementation of [`video_player`][1].

## Usage

This package is [endorsed][2], which means you can simply use `video_player`
normally. This package will be automatically included in your app when you do,
so you do not need to add it to your `pubspec.yaml`.

However, if you `import` this package to use any of its APIs directly, you
should add it to your `pubspec.yaml` as usual.

## Picture-in-Picture (PiP) Support

To properly handle Picture-in-Picture mode changes in your Android application, you need to override the `onPictureInPictureModeChanged` method in your Flutter activity. This method is called when the PiP mode changes.

In your Flutter Android activity (typically `MainActivity.java` or `MainActivity.kt`), add:

```java
// Java
@Override
public void onPictureInPictureModeChanged(boolean isInPictureInPictureMode) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode);
    // For Android 12+ (API 31+), you'll need:
    // public void onPictureInPictureModeChanged(boolean isInPictureInPictureMode, Configuration newConfig)
}
```

```kotlin
// Kotlin
override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode)
    // For Android 12+ (API 31+), you'll need:
    // override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration)
}
```

### Avoiding Activity Lifecycle Issues

To prevent errors like "Performing pause of activity that is not resumed", make sure your Activity correctly handles lifecycle transitions with PiP. Add these to your MainActivity:

```java
// Java
@Override
public void onUserLeaveHint() {
    super.onUserLeaveHint();
    // This is a good place to automatically enter PiP mode if a video is playing
}

@Override
public void onStop() {
    // Make sure to handle any cleanup before calling super
    super.onStop();
}

@Override
public void onResume() {
    super.onResume();
    // Delay any PiP operations to ensure activity is fully resumed
    new Handler().postDelayed(() -> {
        // Safe to perform PiP operations here
    }, 300);
}
```

```kotlin
// Kotlin
override fun onUserLeaveHint() {
    super.onUserLeaveHint()
    // This is a good place to automatically enter PiP mode if a video is playing
}

override fun onStop() {
    // Make sure to handle any cleanup before calling super
    super.onStop()
}

override fun onResume() {
    super.onResume()
    // Delay any PiP operations to ensure activity is fully resumed
    Handler().postDelayed({
        // Safe to perform PiP operations here
    }, 300)
}
```

Also, avoid rapidly toggling PiP mode and ensure you don't call `enterPictureInPictureMode()` during activity transitions.

[1]: https://pub.dev/packages/video_player
[2]: https://flutter.dev/to/endorsed-federated-plugin
