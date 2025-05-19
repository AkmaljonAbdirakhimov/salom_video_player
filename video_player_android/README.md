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

[1]: https://pub.dev/packages/video_player
[2]: https://flutter.dev/to/endorsed-federated-plugin
