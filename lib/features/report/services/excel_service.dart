import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart'; // Pastikan pakai open_filex (bukan open_file)
import '../../../models/transaction_model.dart';


class ExcelService {

  static Future<void> generateExcelReport({
    required List<TransactionModel> transactions,
    required String branchName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // 1. Buat Buku Excel Baru
    var excel = Excel.createExcel();

    // Ganti nama sheet default 'Sheet1' jadi 'Laporan'
    Sheet sheet = excel['Sheet1'];
    excel.rename('Sheet1', 'Laporan Keuangan');

    // 2. Buat Gaya Header (Opsional: Bold)
    CellStyle headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString("#D3D3D3"), // Abu-abu muda
    );

    // 3. Tulis Header Kolom (Baris 1)
    // --- PERBAIKAN HEADER (Baris 1) ---
    // Header juga harus dibungkus TextCellValue
    List<CellValue> headers = [
      TextCellValue('Tanggal'),
      TextCellValue('Kategori'),
      TextCellValue('Deskripsi'),
      TextCellValue('Pemasukan'),
      TextCellValue('Pengeluaran'),
      TextCellValue('Cabang'),
      TextCellValue('User'),
    ];
    sheet.appendRow(headers);

    // --- PERBAIKAN DATA (Baris 2 dst) ---
    final dateFormat = DateFormat('yyyy-MM-dd');

    for (var tx in transactions) {
      bool isIncome = tx.type == 'income';

      sheet.appendRow([
        // 1. Tanggal (Teks) -> Bungkus pakai TextCellValue
        TextCellValue(dateFormat.format(tx.date)),

        // 2. Kategori (Teks)
        TextCellValue(tx.category ?? '-'),

        // 3. Deskripsi (Teks)
        TextCellValue(tx.description ?? '-'),

        // 4. Pemasukan (Angka) -> Bungkus pakai DoubleCellValue
        DoubleCellValue(isIncome ? tx.amount : 0),

        // 5. Pengeluaran (Angka)
        DoubleCellValue(!isIncome ? tx.amount : 0),

        // 6. Cabang (Teks)
        TextCellValue(tx.relatedBranchId ?? branchName),

        // 7. User (Teks)
        TextCellValue(tx.userId ?? '-'),
      ]);
    }

    // 5. Simpan File ke HP
    // Kita simpan di folder temporary/dokumen aplikasi agar tidak butuh izin ribet
    final directory = await getApplicationDocumentsDirectory();
    final fileName = "Laporan_${branchName}_${DateFormat('yyyyMMdd').format(startDate)}.xlsx";
    final String path = '${directory.path}/$fileName';

    // Encode dan Tulis File
    final List<int>? fileBytes = excel.save();
    if (fileBytes != null) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);

      // 6. Buka File Otomatis
      await OpenFilex.open(path);
    }
  }
}