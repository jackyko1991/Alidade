import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _githubRepoUrl = 'https://github.com/jackyko1991/Alidade';
const sponsorUrl = 'https://buymeacoffee.com/jackyko1991';
const _tetra3rsUrl = 'https://github.com/ssmichael1/tetra3rs';
const _tetra3EsaUrl = 'https://github.com/esa/tetra3';
const _iauStarNamesUrl = 'https://github.com/cyschneck/iau-star-names';
const _d3CelestialUrl = 'https://github.com/ofrohn/d3-celestial';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About Alidade')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Alidade',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'An offline plate solver for astrophotographers without a '
            'finder scope. Point your camera, take a shot, and Alidade '
            'tells you exactly where in the sky you\'re pointed, no '
            'internet connection required.',
          ),
          const SizedBox(height: 24),

          _SectionCard(
            title: 'Support this project',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Alidade is free and works entirely offline. If it\'s '
                  'useful to you, consider buying me a coffee. It helps '
                  'cover developer account fees and keeps the project going.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _open(sponsorUrl),
                  icon: const Icon(Icons.coffee_outlined),
                  label: const Text('Buy me a coffee'),
                ),
              ],
            ),
          ),

          _SectionCard(
            title: 'How it works',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Alidade\'s solving core is tetra3rs, a Rust '
                  'implementation of the Tetra3 lost-in-space star '
                  'identification algorithm. Given a set of star positions '
                  'extracted from your photo, it matches their geometric '
                  'pattern against a bundled star catalog. No prior '
                  'pointing estimate is required, and nothing ever leaves '
                  'your phone.',
                ),
                const SizedBox(height: 8),
                _LinkRow(
                  label: 'tetra3rs (Rust, MIT license)',
                  onTap: () => _open(_tetra3rsUrl),
                ),
                _LinkRow(
                  label: 'tetra3 (original Python, ESA, Apache-2.0)',
                  onTap: () => _open(_tetra3EsaUrl),
                ),
              ],
            ),
          ),

          _SectionCard(
            title: 'Credits & data',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Star identification: tetra3rs, credited above.'),
                const Text('Star catalog: Gaia DR3 + Hipparcos (ESA).'),
                const SizedBox(height: 4),
                _LinkRow(
                  label: 'Named-star lookup: IAU Catalog of Star Names (MIT)',
                  onTap: () => _open(_iauStarNamesUrl),
                ),
                const SizedBox(height: 4),
                _LinkRow(
                  label: 'Constellation lines: d3-celestial by Olaf Frohn (BSD-3-Clause)',
                  onTap: () => _open(_d3CelestialUrl),
                ),
              ],
            ),
          ),

          _SectionCard(
            title: 'Source & feedback',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Alidade\'s own source code and issue tracker:'),
                const SizedBox(height: 4),
                _LinkRow(
                  label: 'GitHub repository',
                  onTap: () => _open(_githubRepoUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _open(String url) => openExternalUrl(url);
}

Future<void> openExternalUrl(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.open_in_new, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }
}
