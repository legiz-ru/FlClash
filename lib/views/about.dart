import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/services/hwid_service.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class Contributor {
  final String avatar;
  final String name;
  final String link;

  const Contributor({
    required this.avatar,
    required this.name,
    required this.link,
  });
}

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  _checkUpdate(BuildContext context) async {
    final commonScaffoldState = context.commonScaffoldState;
    if (commonScaffoldState?.mounted != true) return;
    final data = await commonScaffoldState?.loadingRun<Map<String, dynamic>?>(
      request.checkForUpdate,
      title: appLocalizations.checkUpdate,
    );
    globalState.appController.checkUpdateResultHandle(
      data: data,
      handleError: true,
    );
  }

  List<Widget> _buildMoreSection(BuildContext context) {
    return generateSection(
      separated: false,
      title: appLocalizations.more,
      items: [
        ListItem(
          title: Text(appLocalizations.checkUpdate),
          onTap: () {
            _checkUpdate(context);
          },
        ),
        ListItem(
          title: const Text("Telegram"),
          onTap: () {
            globalState.openUrl(
              "https://t.me/FlClash",
            );
          },
          trailing: const Icon(Icons.launch),
        ),
        ListItem(
          title: Text(appLocalizations.project),
          onTap: () {
            globalState.openUrl(
              "https://github.com/$repository",
            );
          },
          trailing: const Icon(Icons.launch),
        ),
        ListItem(
          title: Text(appLocalizations.core),
          onTap: () {
            globalState.openUrl(
              "https://github.com/chen08209/Clash.Meta/tree/FlClash",
            );
          },
          trailing: const Icon(Icons.launch),
        ),
      ],
    );
  }

  List<Widget> _buildContributorsSection() {
    const contributors = [
      Contributor(
        avatar: "assets/images/avatars/june2.jpg",
        name: "June2",
        link: "https://t.me/Jibadong",
      ),
      Contributor(
        avatar: "assets/images/avatars/arue.jpg",
        name: "Arue",
        link: "https://t.me/xrcm6868",
      ),
    ];
    return generateSection(
      separated: false,
      title: appLocalizations.otherContributors,
      items: [
        ListItem(
          title: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Wrap(
              spacing: 24,
              children: [
                for (final contributor in contributors)
                  Avatar(
                    contributor: contributor,
                  ),
              ],
            ),
          ),
        )
      ],
    );
  }

  List<Widget> _buildDeviceInfoSection() {
    return generateSection(
      separated: false,
      title: "Device Information",
      items: [
        FutureBuilder<DeviceInfo>(
          future: hwidService.getDeviceInfo(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final deviceInfo = snapshot.data!;
              return Column(
                children: [
                  ListItem(
                    title: const Text("Hardware ID"),
                    subtitle: Text(deviceInfo.hwid),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: deviceInfo.hwid));
                        context.showNotifier("Hardware ID copied to clipboard");
                      },
                    ),
                  ),
                  ListItem(
                    title: const Text("Device OS"),
                    subtitle: Text(deviceInfo.deviceOS),
                  ),
                  ListItem(
                    title: const Text("OS Version"),
                    subtitle: Text(deviceInfo.osVersion),
                  ),
                  ListItem(
                    title: const Text("Device Model"),
                    subtitle: Text(deviceInfo.deviceModel),
                  ),
                ],
              );
            } else if (snapshot.hasError) {
              return ListItem(
                title: const Text("Device Information"),
                subtitle: Text("Error loading device info: ${snapshot.error}"),
              );
            } else {
              return const ListItem(
                title: Text("Device Information"),
                subtitle: Text("Loading..."),
              );
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      ListTile(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Consumer(builder: (_, ref, ___) {
              return _DeveloperModeDetector(
                child: Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        'assets/images/icon.png',
                        width: 64,
                        height: 64,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appName,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          globalState.packageInfo.version,
                          style: Theme.of(context).textTheme.labelLarge,
                        )
                      ],
                    )
                  ],
                ),
                onEnterDeveloperMode: () {
                  ref.read(appSettingProvider.notifier).updateState(
                        (state) => state.copyWith(developerMode: true),
                      );
                  context.showNotifier(appLocalizations.developerModeEnableTip);
                },
              );
            }),
            const SizedBox(
              height: 24,
            ),
            Text(
              appLocalizations.desc,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      const SizedBox(
        height: 12,
      ),
      ..._buildDeviceInfoSection(),
      ..._buildContributorsSection(),
      ..._buildMoreSection(context),
    ];
    return Padding(
      padding: kMaterialListPadding.copyWith(
        top: 16,
        bottom: 16,
      ),
      child: generateListView(items),
    );
  }
}

class Avatar extends StatelessWidget {
  final Contributor contributor;

  const Avatar({
    super.key,
    required this.contributor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Column(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircleAvatar(
              foregroundImage: AssetImage(
                contributor.avatar,
              ),
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            contributor.name,
            style: context.textTheme.bodySmall,
          )
        ],
      ),
      onTap: () {
        globalState.openUrl(contributor.link);
      },
    );
  }
}

class _DeveloperModeDetector extends StatefulWidget {
  final Widget child;
  final VoidCallback onEnterDeveloperMode;

  const _DeveloperModeDetector({
    required this.child,
    required this.onEnterDeveloperMode,
  });

  @override
  State<_DeveloperModeDetector> createState() => _DeveloperModeDetectorState();
}

class _DeveloperModeDetectorState extends State<_DeveloperModeDetector> {
  int _counter = 0;
  Timer? _timer;

  void _handleTap() {
    _counter++;
    if (_counter >= 5) {
      widget.onEnterDeveloperMode();
      _resetCounter();
    } else {
      _timer?.cancel();
      _timer = Timer(Duration(seconds: 1), _resetCounter);
    }
  }

  void _resetCounter() {
    _counter = 0;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: widget.child,
    );
  }
}
