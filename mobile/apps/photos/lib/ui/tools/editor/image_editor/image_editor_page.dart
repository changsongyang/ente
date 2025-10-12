import "dart:async";
import "dart:io";
import "dart:math";
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:flutter_image_compress/flutter_image_compress.dart";
import "package:logging/logging.dart";
import 'package:path/path.dart' as path;
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart' as ente;
import "package:photos/models/location/location.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/navigation_util.dart";
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditorPage extends StatefulWidget {
  final ente.EnteFile originalFile;
  final File file;
  final DetailPageConfiguration detailPageConfig;

  const ImageEditorPage({
    super.key,
    required this.file,
    required this.originalFile,
    required this.detailPageConfig,
  });

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  final editorKey = GlobalKey<ProImageEditorState>();
  final _logger = Logger("ImageEditor");

  Future<void> saveImage(Uint8List? bytes) async {
    if (bytes == null) return;

    final dialog =
        createProgressDialog(context, AppLocalizations.of(context).saving);
    await dialog.show();

    debugPrint("Image saved with size: ${bytes.length} bytes");
    final DateTime start = DateTime.now();

    final ui.Image decodedResult = await decodeImageFromList(bytes);
    final result = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: decodedResult.width,
      minHeight: decodedResult.height,
    );
    _logger.info('Size after compression = ${result.length}');
    final Duration diff = DateTime.now().difference(start);
    _logger.info('image_editor time : $diff');

    try {
      final fileName =
          path.basenameWithoutExtension(widget.originalFile.title!) +
              "_edited_" +
              DateTime.now().microsecondsSinceEpoch.toString() +
              ".JPEG";
      //Disabling notifications for assets changing to insert the file into
      //files db before triggering a sync.
      await PhotoManager.stopChangeNotify();
      final AssetEntity newAsset =
          await (PhotoManager.editor.saveImage(result, filename: fileName));
      final newFile = await ente.EnteFile.fromAsset(
        widget.originalFile.deviceFolder ?? '',
        newAsset,
      );

      newFile.creationTime = widget.originalFile.creationTime;
      newFile.collectionID = widget.originalFile.collectionID;
      newFile.location = widget.originalFile.location;
      if (!newFile.hasLocation && widget.originalFile.localID != null) {
        final assetEntity = await widget.originalFile.getAsset;
        if (assetEntity != null) {
          final latLong = await assetEntity.latlngAsync();
          newFile.location = Location(
            latitude: latLong.latitude,
            longitude: latLong.longitude,
          );
        }
      }
      newFile.generatedID = await FilesDB.instance.insertAndGetId(newFile);
      Bus.instance.fire(LocalPhotosUpdatedEvent([newFile], source: "editSave"));
      unawaited(SyncService.instance.sync());
      showShortToast(context, AppLocalizations.of(context).editsSaved);
      _logger.info("Original file " + widget.originalFile.toString());
      _logger.info("Saved edits to file " + newFile.toString());
      final files = widget.detailPageConfig.files;

      // the index could be -1 if the files fetched doesn't contain the newly
      // edited files
      int selectionIndex =
          files.indexWhere((file) => file.generatedID == newFile.generatedID);
      if (selectionIndex == -1) {
        files.add(newFile);
        selectionIndex = files.length - 1;
      }
      await dialog.hide();
      replacePage(
        context,
        DetailPage(
          widget.detailPageConfig.copyWith(
            files: files,
            selectedIndex: min(selectionIndex, files.length - 1),
          ),
        ),
      );
    } catch (e, s) {
      await dialog.hide();
      showToast(context, AppLocalizations.of(context).oopsCouldNotSaveEdits);
      _logger.severe(e, s);
    } finally {
      await PhotoManager.startChangeNotify();
    }
  }

  Future<void> _showExitConfirmationDialog(BuildContext context) async {
    final actionResult = await showActionSheet(
      context: context,
      buttons: [
        ButtonWidget(
          labelText: AppLocalizations.of(context).yesDiscardChanges,
          buttonType: ButtonType.critical,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          isInAlert: true,
        ),
        ButtonWidget(
          labelText: AppLocalizations.of(context).no,
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          buttonAction: ButtonAction.second,
          shouldStickToDarkTheme: true,
          isInAlert: true,
        ),
      ],
      body: AppLocalizations.of(context).doYouWantToDiscardTheEditsYouHaveMade,
      actionSheetType: ActionSheetType.defaultActionSheet,
    );
    if (actionResult?.action != null &&
        actionResult!.action == ButtonAction.first) {
      replacePage(context, DetailPage(widget.detailPageConfig));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final colorScheme = getEnteColorScheme(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showExitConfirmationDialog(context);
      },
      child: Scaffold(
        backgroundColor: colorScheme.backgroundBase,
        body: ProImageEditor.file(
          key: editorKey,
          widget.file,
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {
              await saveImage(bytes);
            },
            onCloseEditor: (value) {
              _showExitConfirmationDialog(context);
              return true;
            },
          ),
          configs: ProImageEditorConfigs(
            designMode: ImageEditorDesignMode.material,
            theme: ThemeData(
              scaffoldBackgroundColor: colorScheme.backgroundBase,
              appBarTheme: AppBarTheme(
                backgroundColor: colorScheme.backgroundBase,
                foregroundColor: colorScheme.textBase,
                elevation: 0,
              ),
              brightness: isLightMode ? Brightness.light : Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor:
                    Theme.of(context).colorScheme.imageEditorPrimaryColor,
                brightness: isLightMode ? Brightness.light : Brightness.dark,
              ),
            ),
            i18n: I18n(
              cancel: AppLocalizations.of(context).cancel,
              done: AppLocalizations.of(context).done,
              undo: AppLocalizations.of(context).undo,
              redo: AppLocalizations.of(context).redo,
            ),
            mainEditor: const MainEditorConfigs(
              enableZoom: true,
            ),
            paintEditor: const PaintEditorConfigs(),
            textEditor: const TextEditorConfigs(
              enabled: true,
            ),
            cropRotateEditor: const CropRotateEditorConfigs(),
            filterEditor: const FilterEditorConfigs(),
            tuneEditor: const TuneEditorConfigs(),
            blurEditor: const BlurEditorConfigs(
              enabled: false,
            ),
            emojiEditor: const EmojiEditorConfigs(
              checkPlatformCompatibility: true,
            ),
            stickerEditor: const StickerEditorConfigs(
              enabled: false,
            ),
          ),
        ),
      ),
    );
  }
}
