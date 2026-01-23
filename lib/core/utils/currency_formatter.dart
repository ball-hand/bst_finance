import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {

    // Jika kosong, biarkan kosong
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Hanya ambil angka
    String newText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Cegah error jika string kosong setelah direplace
    if (newText.isEmpty) return newValue;

    // Ubah ke format Rupiah
    double value = double.parse(newText);
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: '', decimalDigits: 0);
    String newString = formatter.format(value).trim();

    return newValue.copyWith(
      text: newString,
      selection: TextSelection.collapsed(offset: newString.length),
    );
  }

  // Helper untuk mengubah string terformat "3.000.000" kembali ke double 3000000.0
  static double toDouble(String formattedValue) {
    if (formattedValue.isEmpty) return 0;
    return double.parse(formattedValue.replaceAll('.', ''));
  }
}