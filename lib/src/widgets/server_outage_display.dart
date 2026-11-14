import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/network/server_status.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:material_ui/material_ui.dart';

/// Message shown in place of the content that needs the TwoStones server, when
/// that server is unavailable.
///
/// Like the website, which serves a different page in each case, this
/// distinguishes planned maintenance from an outage.
///
/// This is laid out as a plain column so it can either be embedded among other
/// widgets, as on the home tab where offline content is kept around it, or fill
/// a whole screen.
class const ServerOutageDisplay({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMaintenance = ref.watch(serverStatusProvider) == ServerStatus.maintenance;
    final textStyle = Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: Styles.bodyPadding,
      child: Column(
        mainAxisAlignment: .center,
        children: [
          const TwoStonesLogo(size: 150),
          const SizedBox(height: 16),
          Text(
            isMaintenance
                ? 'TwoStones is undergoing scheduled maintenance. We expect to be back very soon.'
                : 'TwoStones is down. We expect to be back very soon. Thanks for your patience.',
            textAlign: TextAlign.center,
            style: textStyle,
          ),
        ],
      ),
    );
  }
}
