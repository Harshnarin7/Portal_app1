import 'package:flutter/material.dart';
import 'birth_log_screen.dart';
import 'gestation_log_screen.dart';

const _kPrimary = Color(0xFF3B6FE0);
const _kSurface = Color(0xFFFFFFFF);
const _kBorder = Color(0xFFD4DCF0);
const _kText1 = Color(0xFF1A2340);
const _kText2 = Color(0xFF4A5578);
const _kText3 = Color(0xFF8A95B0);
const _kBg = Color(0xFFEFF3FB);

class LogHubScreen extends StatelessWidget {
  const LogHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3A8A), Color(0xFF3B6FE0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logs',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Same records as the web logs. Choose one to open.',
                    style: TextStyle(fontSize: 13, color: Color(0xFFD6E2FF), height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _LogOptionCard(
              icon: Icons.search_rounded,
              title: 'Gestation (inclusion criteria) log',
              subtitle:
                  'Log every woman checked for gestational age at triage — Continue to Form A when eligible.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GestationLogScreen()),
              ),
            ),
            const SizedBox(height: 14),
            _LogOptionCard(
              icon: Icons.assignment_outlined,
              title: 'Log of all births',
              subtitle:
                  'Record every birth at this hospital and catch GA-eligible deliveries with no Form A.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BirthLogScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LogOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kSurface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _kPrimary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _kText1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: _kText2, height: 1.35),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _kText3),
            ],
          ),
        ),
      ),
    );
  }
}
