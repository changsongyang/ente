import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// A mixin providing access to simple editor configurations.
mixin SimpleConfigsAccess on StatefulWidget {
  ProImageEditorConfigs get configs;
  ProImageEditorCallbacks get callbacks;
}

mixin SimpleConfigsAccessState<T extends StatefulWidget> on State<T> {
  SimpleConfigsAccess get _widget => (widget as SimpleConfigsAccess);

  ProImageEditorConfigs get configs => _widget.configs;

  ProImageEditorCallbacks get callbacks => _widget.callbacks;
}
