import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String content;
  final VoidCallback onConfirm; // Aksi yang dijalankan saat klik YA
  final String confirmText;
  final Color confirmColor;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    required this.onConfirm,
    this.confirmText = "Ya, Hapus",
    this.confirmColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(content),
      actions: [
        // Tombol Batal
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Tutup dialog
          child: const Text("Batal", style: TextStyle(color: Colors.grey)),
        ),

        // Tombol Eksekusi
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () {
            Navigator.of(context).pop(); // 1. Auto Close (Tutup dulu)
            onConfirm(); // 2. Jalankan logika (Hapus/Simpan dll)
          },
          child: Text(confirmText, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}