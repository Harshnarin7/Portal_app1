// lib/screens/crf_detail_screen.dart
import 'package:flutter/material.dart';
import '../models/crf.dart';

class CRFDetailScreen extends StatelessWidget {
  final CRF crf;
  const CRFDetailScreen({super.key, required this.crf});

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: const TextStyle(color: Colors.white70)),
          Flexible(child: Text(b, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      appBar: AppBar(title: const Text('CRF Details'), backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          color: const Color(0xFF111216),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${crf.motherFirstName} ${crf.motherLastName ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _row('Screening ID', crf.screeningIdManual),
              _row('Site', '${crf.site} (${crf.siteId})'),
              _row('Screening Date', crf.screeningDateTime.toLocal().toString()),
              const Divider(color: Colors.white12),
              _row('Gestation', '${crf.gestationWeeks}w ${crf.gestationDays}d'),
              _row('GA Method', crf.gaMethod),
              _row('ED Date', crf.expectedDeliveryDate.toLocal().toString().split(' ')[0]),
              const Divider(color: Colors.white12),
              _row('Mother Phone', crf.motherPhone),
              _row('Husband Phone', crf.husbandPhone),
              const Divider(color: Colors.white12),
              _row('Eligibility', crf.eligibility),
              _row('Consent', crf.consent),
            ]),
          ),
        ),
      ),
    );
  }
}
