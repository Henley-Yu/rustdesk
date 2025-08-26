import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

bool isEditOsPassword = false;

class TTextMenu {
  final Widget child;
  final VoidCallback onPressed;
  Widget? trailingIcon;
  bool divider;
  TTextMenu(
      {required this.child,
      required this.onPressed,
      this.trailingIcon,
      this.divider = false});

  Widget getChild() {
    if (trailingIcon != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          child,
          trailingIcon!,
        ],
      );
    } else {
      return child;
    }
  }
}

class TRadioMenu<T> {
  final Widget child;
  final T value;
  final T groupValue;
  final ValueChanged<T?>? onChanged;

  TRadioMenu(
      {required this.child,
      required this.value,
      required this.groupValue,
      required this.onChanged});
}

class TToggleMenu {
  final Widget child;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  TToggleMenu(
      {required this.child, required this.value, required this.onChanged});
}

handleOsPasswordEditIcon(
    SessionID sessionId, OverlayDialogManager dialogManager) {
  isEditOsPassword = true;
  showSetOSPassword(
      sessionId, false, dialogManager, null, () => isEditOsPassword = false);
}

handleOsPasswordAction(
    SessionID sessionId, OverlayDialogManager dialogManager) async {
  if (isEditOsPassword) {
    isEditOsPassword = false;
    return;
  }
  final password =
      await bind.sessionGetOption(sessionId: sessionId, arg: 'os-password') ??
          '';
  if (password.isEmpty) {
    showSetOSPassword(sessionId, true, dialogManager, password,
        () => isEditOsPassword = false);
  } else {
    bind.sessionInputOsPassword(sessionId: sessionId, value: password);
  }
}

List<TTextMenu> toolbarControls(BuildContext context, String id, FFI ffi) {
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  final perms = ffiModel.permissions;
  final sessionId = ffi.sessionId;
  final isDefaultConn = ffi.connType == ConnType.defaultConn;

  List<TTextMenu> v = [];

  // paste
  if (isDefaultConn &&
      pi.platform != kPeerPlatformAndroid &&
      perms['keyboard'] != false) {
    v.add(TTextMenu(
        child: Text(translate('Send clipboard keystrokes')),
        onPressed: () async {
          ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
          if (data != null && data.text != null) {
            bind.sessionInputString(
                sessionId: sessionId, value: data.text ?? "");
          }
        }));
  }

  connectWithToken(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTcpTunneling = false}) {
    final connToken = bind.sessionGetConnToken(sessionId: ffi.sessionId);
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTcpTunneling: isTcpTunneling,
        connToken: connToken);
  }

  // transferFile
  if (isDefaultConn && isDesktop) {
    v.add(
      TTextMenu(
          child: Text(translate('Transfer file')),
          onPressed: () => connectWithToken(isFileTransfer: true)),
    );
  }
  // note
  if (isDefaultConn &&
      bind
          .sessionGetAuditServerSync(sessionId: sessionId, typ: "conn")
          .isNotEmpty) {
    v.add(
      TTextMenu(
          child: Text(translate('Note')),
          onPressed: () => showAuditDialog(ffi)),
    );
  }
  // divider
  if (isDefaultConn && (isDesktop || isWebDesktop)) {
    v.add(TTextMenu(child: Offstage(), onPressed: () {}, divider: true));
  }
  // ctrlAltDel
  if (isDefaultConn &&
      !ffiModel.viewOnly &&
      ffiModel.keyboard &&
      (pi.platform == kPeerPlatformLinux || pi.sasEnabled)) {
    v.add(
      TTextMenu(
          child: Text('${translate("Insert Ctrl + Alt + Del")}'),
          onPressed: () => bind.sessionCtrlAltDel(sessionId: sessionId)),
    );
  }
  // restart
  if (isDefaultConn &&
      perms['restart'] != false &&
      (pi.platform == kPeerPlatformLinux ||
          pi.platform == kPeerPlatformWindows ||
          pi.platform == kPeerPlatformMacOS)) {
    v.add(
      TTextMenu(
          child: Text(translate('Restart remote device')),
          onPressed: () =>
              showRestartRemoteDevice(pi, id, sessionId, ffi.dialogManager)),
    );
  }
  // insertLock
  if (isDefaultConn && !ffiModel.viewOnly && ffi.ffiModel.keyboard) {
    v.add(
      TTextMenu(
          child: Text(translate('Insert Lock')),
          onPressed: () => bind.sessionLockScreen(sessionId: sessionId)),
    );
  }

  // refresh
  if (pi.version.isNotEmpty) {
    v.add(TTextMenu(
      child: Text(translate('Refresh')),
      onPressed: () => sessionRefreshVideo(sessionId, pi),
    ));
  }
  // record
  if (!(isDesktop || isWeb) &&
      (ffi.recordingModel.start || (perms["recording"] != false))) {
    v.add(TTextMenu(
        child: Row(
          children: [
            Text(translate(ffi.recordingModel.start
                ? 'Stop session recording'
                : 'Start session recording')),
            Padding(
              padding: EdgeInsets.only(left: 12),
              child: Icon(
                  ffi.recordingModel.start
                      ? Icons.pause_circle_filled
                      : Icons.videocam_outlined,
                  color: MyTheme.accent),
            )
          ],
        ),
        onPressed: () => ffi.recordingModel.toggle()));
  }
  return v;
}

Future<List<TRadioMenu<String>>> toolbarViewStyle(
    BuildContext context, String id, FFI ffi) async {
  final groupValue =
      await bind.sessionGetViewStyle(sessionId: ffi.sessionId) ?? '';
  void onChanged(String? value) async {
    if (value == null) return;
    bind
        .sessionSetViewStyle(sessionId: ffi.sessionId, value: value)
        .then((_) => ffi.canvasModel.updateViewStyle());
  }

  return [
    TRadioMenu<String>(
        child: Text(translate('Scale original')),
        value: kRemoteViewStyleOriginal,
        groupValue: groupValue,
        onChanged: onChanged),
    TRadioMenu<String>(
        child: Text(translate('Scale adaptive')),
        value: kRemoteViewStyleAdaptive,
        groupValue: groupValue,
        onChanged: onChanged)
  ];
}

Future<List<TRadioMenu<String>>> toolbarImageQuality(
    BuildContext context, String id, FFI ffi) async {
  final groupValue =
      await bind.sessionGetImageQuality(sessionId: ffi.sessionId) ?? '';
  onChanged(String? value) async {
    if (value == null) return;
    await bind.sessionSetImageQuality(sessionId: ffi.sessionId, value: value);
  }

  return [
    TRadioMenu<String>(
        child: Text(translate('Good image quality')),
        value: kRemoteImageQualityBest,
        groupValue: groupValue,
        onChanged: onChanged),
    TRadioMenu<String>(
        child: Text(translate('Balanced')),
        value: kRemoteImageQualityBalanced,
        groupValue: groupValue,
        onChanged: onChanged),
    TRadioMenu<String>(
        child: Text(translate('Optimize reaction time')),
        value: kRemoteImageQualityLow,
        groupValue: groupValue,
        onChanged: onChanged),
    TRadioMenu<String>(
      child: Text(translate('Custom')),
      value: kRemoteImageQualityCustom,
      groupValue: groupValue,
      onChanged: (value) {
        onChanged(value);
        customImageQualityDialog(ffi.sessionId, id, ffi);
      },
    ),
  ];
}

Future<List<TRadioMenu<String>>> toolbarCodec(
    BuildContext context, String id, FFI ffi) async {
  final sessionId = ffi.sessionId;
  final alternativeCodecs =
      await bind.sessionAlternativeCodecs(sessionId: sessionId);
  final groupValue = await bind.sessionGetOption(
          sessionId: sessionId, arg: kOptionCodecPreference) ??
      '';
  final List<bool> codecs = [];
  try {
    final Map codecsJson = jsonDecode(alternativeCodecs);
    final vp8 = codecsJson['vp8'] ?? false;
    final av1 = codecsJson['av1'] ?? false;
    final h264 = codecsJson['h264'] ?? false;
    final h265 = codecsJson['h265'] ?? false;
    codecs.add(vp8);
    codecs.add(av1);
    codecs.add(h264);
    codecs.add(h265);
  } catch (e) {
    debugPrint("Show Codec Preference err=$e");
  }
  final visible =
      codecs.length == 4 && (codecs[0] || codecs[1] || codecs[2] || codecs[3]);
  if (!visible) return [];
  onChanged(String? value) async {
    if (value == null) return;
    await bind.sessionPeerOption(
        sessionId: sessionId, name: kOptionCodecPreference, value: value);
    bind.sessionChangePreferCodec(sessionId: sessionId);
  }

  TRadioMenu<String> radio(String label, String value, bool enabled) {
    return TRadioMenu<String>(
        child: Text(label),
        value: value,
        groupValue: groupValue,
        onChanged: enabled ? onChanged : null);
  }

  var autoLabel = translate('Auto');
  if (groupValue == 'auto' &&
      ffi.qualityMonitorModel.data.codecFormat != null) {
    autoLabel = '$autoLabel (${ffi.qualityMonitorModel.data.codecFormat})';
  }
  return [
    radio(autoLabel, 'auto', true),
    if (codecs[0]) radio('VP8', 'vp8', codecs[0]),
    radio('VP9', 'vp9', true),
    if (codecs[1]) radio('AV1', 'av1', codecs[1]),
    if (codecs[2]) radio('H264', 'h264', codecs[2]),
    if (codecs[3]) radio('H265', 'h265', codecs[3]),
  ];
}



Future<List<TToggleMenu>> toolbarDisplayToggle(
    BuildContext context, String id, FFI ffi) async {
  List<TToggleMenu> v = [];
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  final perms = ffiModel.permissions;
  final sessionId = ffi.sessionId;
  final isDefaultConn = ffi.connType == ConnType.defaultConn;

  // show quality monitor
  final option = 'show-quality-monitor';
  v.add(TToggleMenu(
      value: bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: option),
      onChanged: (value) async {
        if (value == null) return;
        await bind.sessionToggleOption(sessionId: sessionId, value: option);
        ffi.qualityMonitorModel.checkShowQualityMonitor(sessionId);
      },
      child: Text(translate('Show quality monitor'))));
  // mute
  if (isDefaultConn && perms['audio'] != false) {
    final option = 'disable-audio';
    final value =
        bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: option);
    v.add(TToggleMenu(
        value: value,
        onChanged: (value) {
          if (value == null) return;
          bind.sessionToggleOption(sessionId: sessionId, value: option);
        },
        child: Text(translate('Mute'))));
  }
  // file copy and paste
  // If the version is less than 1.2.4, file copy and paste is supported on Windows only.
  final isSupportIfPeer_1_2_3 = versionCmp(pi.version, '1.2.4') < 0 &&
      isWindows &&
      pi.platform == kPeerPlatformWindows;
  // If the version is 1.2.4 or later, file copy and paste is supported when kPlatformAdditionsHasFileClipboard is set.
  final isSupportIfPeer_1_2_4 = versionCmp(pi.version, '1.2.4') >= 0 &&
      bind.mainHasFileClipboard() &&
      pi.platformAdditions.containsKey(kPlatformAdditionsHasFileClipboard);
  if (isDefaultConn &&
      ffiModel.keyboard &&
      perms['file'] != false &&
      (isSupportIfPeer_1_2_3 || isSupportIfPeer_1_2_4)) {
    final enabled = !ffiModel.viewOnly;
    final value = bind.sessionGetToggleOptionSync(
        sessionId: sessionId, arg: kOptionEnableFileCopyPaste);
    v.add(TToggleMenu(
        value: value,
        onChanged: enabled
            ? (value) {
                if (value == null) return;
                bind.sessionToggleOption(
                    sessionId: sessionId, value: kOptionEnableFileCopyPaste);
              }
            : null,
        child: Text(translate('Enable file copy and paste'))));
  }
  // lock after session end
  if (isDefaultConn && ffiModel.keyboard && !ffiModel.isPeerAndroid) {
    final enabled = !ffiModel.viewOnly;
    final option = 'lock-after-session-end';
    final value =
        bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: option);
    v.add(TToggleMenu(
        value: value,
        onChanged: enabled
            ? (value) {
                if (value == null) return;
                bind.sessionToggleOption(sessionId: sessionId, value: option);
              }
            : null,
        child: Text(translate('Lock after session end'))));
  }

  if (pi.isSupportMultiDisplay &&
      PrivacyModeState.find(id).isEmpty &&
      pi.displaysCount.value > 1 &&
      bind.mainGetUserDefaultOption(key: kKeyShowMonitorsToolbar) == 'Y') {
    final value =
        bind.sessionGetDisplaysAsIndividualWindows(sessionId: ffi.sessionId) ==
            'Y';
    v.add(TToggleMenu(
        value: value,
        onChanged: (value) {
          if (value == null) return;
          bind.sessionSetDisplaysAsIndividualWindows(
              sessionId: sessionId, value: value ? 'Y' : 'N');
        },
        child: Text(translate('Show displays as individual windows'))));
  }

  final isMultiScreens = !isWeb && (await getScreenRectList()).length > 1;
  if (pi.isSupportMultiDisplay && isMultiScreens) {
    final value = bind.sessionGetUseAllMyDisplaysForTheRemoteSession(
            sessionId: ffi.sessionId) ==
        'Y';
    v.add(TToggleMenu(
        value: value,
        onChanged: (value) {
          if (value == null) return;
          bind.sessionSetUseAllMyDisplaysForTheRemoteSession(
              sessionId: sessionId, value: value ? 'Y' : 'N');
        },
        child: Text(translate('Use all my displays for the remote session'))));
  }

  if (isDefaultConn && isMobile) {
    v.addAll(toolbarKeyboardToggles(ffi));
  }

  return v;
}

List<TToggleMenu> toolbarKeyboardToggles(FFI ffi) {
  final ffiModel = ffi.ffiModel;
  final pi = ffiModel.pi;
  final sessionId = ffi.sessionId;
  List<TToggleMenu> v = [];

  // swap key
  if (ffiModel.keyboard &&
      ((isMacOS && pi.platform != kPeerPlatformMacOS) ||
          (!isMacOS && pi.platform == kPeerPlatformMacOS))) {
    final option = 'allow_swap_key';
    final value =
        bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: option);
    onChanged(bool? value) {
      if (value == null) return;
      bind.sessionToggleOption(sessionId: sessionId, value: option);
    }

    final enabled = !ffi.ffiModel.viewOnly;
    v.add(TToggleMenu(
        value: value,
        onChanged: enabled ? onChanged : null,
        child: Text(translate('Swap control-command key'))));
  }


bool showVirtualDisplayMenu(FFI ffi) {
  if (ffi.ffiModel.pi.platform != kPeerPlatformWindows) {
    return false;
  }
  if (!ffi.ffiModel.pi.isInstalled) {
    return false;
  }
  if (ffi.ffiModel.pi.isRustDeskIdd || ffi.ffiModel.pi.isAmyuniIdd) {
    return true;
  }
  return false;
}

List<Widget> getVirtualDisplayMenuChildren(
    FFI ffi, String id, VoidCallback? clickCallBack) {
  if (!showVirtualDisplayMenu(ffi)) {
    return [];
  }
  final pi = ffi.ffiModel.pi;
  final privacyModeState = PrivacyModeState.find(id);
  if (pi.isRustDeskIdd) {
    final virtualDisplays = ffi.ffiModel.pi.RustDeskVirtualDisplays;
    final children = <Widget>[];
    for (var i = 0; i < kMaxVirtualDisplayCount; i++) {
      children.add(Obx(() => CkbMenuButton(
            value: virtualDisplays.contains(i + 1),
            onChanged: privacyModeState.isNotEmpty
                ? null
                : (bool? value) async {
                    if (value != null) {
                      bind.sessionToggleVirtualDisplay(
                          sessionId: ffi.sessionId, index: i + 1, on: value);
                      clickCallBack?.call();
                    }
                  },
            child: Text('${translate('Virtual display')} ${i + 1}'),
            ffi: ffi,
          )));
    }
    children.add(Divider());
    children.add(Obx(() => MenuButton(
          onPressed: privacyModeState.isNotEmpty
              ? null
              : () {
                  bind.sessionToggleVirtualDisplay(
                      sessionId: ffi.sessionId,
                      index: kAllVirtualDisplay,
                      on: false);
                  clickCallBack?.call();
                },
          ffi: ffi,
          child: Text(translate('Plug out all')),
        )));
    return children;
  }
  if (pi.isAmyuniIdd) {
    final count = ffi.ffiModel.pi.amyuniVirtualDisplayCount;
    final children = <Widget>[
      Obx(() => Row(
            children: [
              TextButton(
                onPressed: privacyModeState.isNotEmpty || count == 0
                    ? null
                    : () {
                        bind.sessionToggleVirtualDisplay(
                            sessionId: ffi.sessionId, index: 0, on: false);
                        clickCallBack?.call();
                      },
                child: Icon(Icons.remove),
              ),
              Text(count.toString()),
              TextButton(
                onPressed: privacyModeState.isNotEmpty || count == 4
                    ? null
                    : () {
                        bind.sessionToggleVirtualDisplay(
                            sessionId: ffi.sessionId, index: 0, on: true);
                        clickCallBack?.call();
                      },
                child: Icon(Icons.add),
              ),
            ],
          )),
      Divider(),
      Obx(() => MenuButton(
            onPressed: privacyModeState.isNotEmpty || count == 0
                ? null
                : () {
                    bind.sessionToggleVirtualDisplay(
                        sessionId: ffi.sessionId,
                        index: kAllVirtualDisplay,
                        on: false);
                    clickCallBack?.call();
                  },
            ffi: ffi,
            child: Text(translate('Plug out all')),
          )),
    ];
    return children;
  }
  return [];
}
