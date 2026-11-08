import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../repository_screen.dart';

/// The Releases tab (SPEC-044): the versions of the main repository.
final releasesTab = RepositoryTab(
  id: 'releases',
  label: 'Releases',
  builder: (context, repo) => const ReleasesTab(),
);

class ReleasesTab extends StatelessWidget {
  const ReleasesTab({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Releases',
      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
    ),
  );
}
