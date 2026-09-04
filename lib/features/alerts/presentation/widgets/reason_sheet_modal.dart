import 'package:flutter/material.dart';

class ReasonSheetModal extends StatefulWidget {
  final Function(String selectedReason) onDismiss;

  const ReasonSheetModal({
    super.key,
    required this.onDismiss,
  });

  @override
  State<ReasonSheetModal> createState() => _ReasonSheetModalState();
}

class _ReasonSheetModalState extends State<ReasonSheetModal> {
  String? _selectedReason;
  final TextEditingController _customController = TextEditingController();

  final List<String> _options = [
    'I am on it',
    'Wrong alert',
    'Something else…',
  ];

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 24.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Dismiss Alert',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          const Text(
            'Select a reason for dismissing this vehicle alert:',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14.0),
          ),
          const SizedBox(height: 16.0),
          ..._options.map((opt) {
            final isSelected = _selectedReason == opt;
            return Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF38BDF8).withOpacity(0.15) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                title: Text(
                  opt,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                leading: Radio<String>(
                  value: opt,
                  groupValue: _selectedReason,
                  activeColor: const Color(0xFF38BDF8),
                  onChanged: (val) {
                    setState(() {
                      _selectedReason = val;
                    });
                  },
                ),
                onTap: () {
                  setState(() {
                    _selectedReason = opt;
                  });
                },
              ),
            );
          }),
          if (_selectedReason == 'Something else…') ...[
            const SizedBox(height: 8.0),
            TextField(
              controller: _customController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter custom reason...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20.0),
          SizedBox(
            width: double.infinity,
            height: 48.0,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              onPressed: _selectedReason == null
                  ? null
                  : () {
                      final finalReason = (_selectedReason == 'Something else…' && _customController.text.trim().isNotEmpty)
                          ? _customController.text.trim()
                          : _selectedReason!;
                      Navigator.pop(context);
                      widget.onDismiss(finalReason);
                    },
              child: const Text(
                'Confirm Dismissal',
                style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
