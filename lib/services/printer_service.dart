import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodstock/model/models.dart';

/// Paper sizes used by kitchen/front-desk printers and PDF export.
class ReceiptPaper {
  static const prefsKey = 'receipt_paper_size';
  static const defaultSize = '80mm';

  static const labels = <String, String>{
    '58mm': '58mm Thermal',
    '80mm': '80mm Thermal',
    'A5': 'A5 Sheet',
    'A4': 'A4 Sheet',
  };

  static bool isValid(String? size) =>
      size != null && labels.containsKey(size);

  static PdfPageFormat format(
    String size, {
    int itemCount = 1,
  }) {
    final mm = PdfPageFormat.mm;
    final lines = itemCount < 1 ? 1 : itemCount;

    switch (size) {
      case '58mm':
        return PdfPageFormat(
          58 * mm,
          (120 + lines * 16) * mm,
          marginAll: 3 * mm,
        );
      case 'A5':
        return PdfPageFormat.a5.copyWith(
          marginTop: 12 * mm,
          marginBottom: 12 * mm,
          marginLeft: 14 * mm,
          marginRight: 14 * mm,
        );
      case 'A4':
        return PdfPageFormat.a4.copyWith(
          marginTop: 16 * mm,
          marginBottom: 16 * mm,
          marginLeft: 18 * mm,
          marginRight: 18 * mm,
        );
      case '80mm':
      default:
        return PdfPageFormat(
          80 * mm,
          (130 + lines * 16) * mm,
          marginAll: 4 * mm,
        );
    }
  }
}

class ReceiptScreen extends StatefulWidget {
  final int saleId;
  final List<CartLine> lines;

  final String paymentType;

  final double subtotal;
  final double tax;
  final double discount;
  final double grandTotal;

  const ReceiptScreen({
    super.key,
    required this.saleId,
    required this.lines,
    required this.paymentType,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.grandTotal,
  });

  @override
  State<ReceiptScreen> createState() =>
      _ReceiptScreenState();
}

class _ReceiptScreenState
    extends State<ReceiptScreen> {
  static const String _printerKey =
      'selected_printer';

  Printer? _selectedPrinter;

  String _paperSize = ReceiptPaper.defaultSize;

  bool _loadingPrinter = true;
  bool _printing = false;
  bool _savingPdf = false;

  @override
  void initState() {
    super.initState();
    _loadPrinter();
  }

  // ------------------------------------------------------------
  // LOAD SELECTED PRINTER
  // ------------------------------------------------------------

  Future<void> _loadPrinter() async {
    try {
      final prefs =
      await SharedPreferences.getInstance();

      final saved =
      prefs.getString(_printerKey);

      final savedSize =
      prefs.getString(ReceiptPaper.prefsKey);

      final paperSize =
      ReceiptPaper.isValid(savedSize)
          ? savedSize!
          : ReceiptPaper.defaultSize;

      if (saved != null && saved.isNotEmpty) {
        final map =
        jsonDecode(saved) as Map<String, dynamic>;

        final savedPrinter =
        Printer.fromMap(map);

        // Get current printer list so that we use
        // a live printer object.
        final printers =
        await Printing.listPrinters();

        Printer? current;

        for (final printer in printers) {
          if (printer.url ==
              savedPrinter.url ||
              printer.name ==
                  savedPrinter.name) {
            current = printer;
            break;
          }
        }

        if (!mounted) return;

        setState(() {
          _selectedPrinter =
              current ?? savedPrinter;
          _paperSize = paperSize;
          _loadingPrinter = false;
        });

        return;
      }

      if (!mounted) return;

      setState(() {
        _paperSize = paperSize;
        _loadingPrinter = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadingPrinter = false;
      });
    }
  }

  // ------------------------------------------------------------
  // PAGE FORMAT
  // ------------------------------------------------------------

  PdfPageFormat get _receiptFormat {
    return ReceiptPaper.format(
      _paperSize,
      itemCount: widget.lines.length,
    );
  }

  Future<void> _changePaperSize(String value) async {
    setState(() {
      _paperSize = value;
    });

    try {
      final prefs =
          await SharedPreferences.getInstance();
      await prefs.setString(
        ReceiptPaper.prefsKey,
        value,
      );
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // PDF RECEIPT
  // ------------------------------------------------------------

  Future<Uint8List> _buildReceipt(
      PdfPageFormat format,
      ) async {
    final regularFont = pw.Font.ttf(
      await rootBundle.load(
        'assets/fonts/NotoSans-Regular.ttf',
      ),
    );

    final boldFont = pw.Font.ttf(
      await rootBundle.load(
        'assets/fonts/NotoSans-Bold.ttf',
      ),
    );

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) {
          return pw.Column(
            crossAxisAlignment:
            pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  'FIVE STAR',
                  style: pw.TextStyle(
                    fontSize: _paperSize == '58mm' ? 14 : 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 2),

              pw.Center(
                child: pw.Text(
                  'HOTEL BILL',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),

              pw.SizedBox(height: 8),

              pw.Divider(),

              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Bill No.',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    '#${widget.saleId}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 3),

              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Date',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    _formatDate(DateTime.now()),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),

              pw.SizedBox(height: 3),

              pw.Row(
                mainAxisAlignment:
                    pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Payment',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Text(
                    widget.paymentType,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 8),

              pw.Divider(),

              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text(
                      'ITEM',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'QTY',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'RATE',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'AMOUNT',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 5),

              pw.Divider(),

              ...widget.lines.map(
                (line) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 4,
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 5,
                          child: pw.Text(
                            line.name,
                            maxLines: 2,
                            style: const pw.TextStyle(
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            line.qty % 1 == 0
                                ? line.qty.toInt().toString()
                                : line.qty.toStringAsFixed(2),
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            '₹${line.price.toStringAsFixed(2)}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            '₹${line.amount.toStringAsFixed(2)}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(
                              fontSize: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              pw.Divider(),

              pw.SizedBox(height: 5),

              _pdfAmountRow(
                'Subtotal',
                widget.subtotal,
              ),

              pw.SizedBox(height: 4),

              _pdfAmountRow(
                'Tax',
                widget.tax,
              ),

              pw.SizedBox(height: 4),

              _pdfAmountRow(
                'Discount',
                widget.discount,
              ),

              pw.SizedBox(height: 7),

              pw.Divider(),

              pw.SizedBox(height: 5),

              _pdfAmountRow(
                'TOTAL',
                widget.grandTotal,
                bold: true,
                fontSize: 14,
              ),

              pw.SizedBox(height: 14),

              pw.Center(
                child: pw.Text(
                  'Thank you for dining with us',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 4),

              pw.Center(
                child: pw.Text(
                  'Please visit again',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // ------------------------------------------------------------
  // PDF AMOUNT ROW
  // ------------------------------------------------------------

  pw.Widget _pdfAmountRow(
      String title,
      double value, {
        bool bold = false,
        double fontSize = 9,
      }) {
    return pw.Row(
      mainAxisAlignment:
      pw.MainAxisAlignment
          .spaceBetween,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          '₹${value.toStringAsFixed(2)}',
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: bold
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // DATE
  // ------------------------------------------------------------

  String _formatDate(DateTime date) {
    String two(int value) =>
        value.toString().padLeft(2, '0');

    return '${date.day}/${date.month}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  // ------------------------------------------------------------
  // DIRECT PRINT
  // ------------------------------------------------------------

  Future<void> _printToSelectedPrinter() async {
    if (_selectedPrinter == null) {
      _showError(
        'No printer selected.\nPlease configure a printer first.',
      );
      return;
    }

    setState(() {
      _printing = true;
    });

    try {
      final result =
      await Printing.directPrintPdf(
        printer: _selectedPrinter!,
        name: 'Five Star Bill #${widget.saleId}',
        format: _receiptFormat,
        onLayout: (format) {
          return _buildReceipt(
            _receiptFormat,
          );
        },
      );

      if (!mounted) return;

      if (result) {
        _showSuccess(
          'Receipt sent to ${_selectedPrinter!.name}',
        );
      } else {
        _showError(
          'Printer did not accept the receipt.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to print receipt.\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _printing = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // SYSTEM PRINT DIALOG
  // ------------------------------------------------------------

  Future<void> _systemPrint() async {
    try {
      await Printing.layoutPdf(
        name:
        'Five Star Bill #${widget.saleId}',
        format: _receiptFormat,
        onLayout: (format) {
          return _buildReceipt(
            _receiptFormat,
          );
        },
      );
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to open print dialog.\n$e',
      );
    }
  }

  // ------------------------------------------------------------
  // SHARE
  // ------------------------------------------------------------

  Future<void> _savePdf() async {
    if (_savingPdf) return;

    setState(() {
      _savingPdf = true;
    });

    try {
      final bytes = await _buildReceipt(_receiptFormat);
      final fileName =
          'FiveStar_Bill_${widget.saleId}.pdf';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save bill as PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );

      if (!mounted) return;

      if (path == null || path.isEmpty) {
        return;
      }

      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }

      _showSuccess('Bill saved as PDF');
    } catch (e) {
      if (!mounted) return;

      try {
        await _shareReceipt();
      } catch (_) {
        _showError('Unable to save PDF.\n$e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingPdf = false;
        });
      }
    }
  }

  Future<void> _shareReceipt() async {
    try {
      final bytes =
      await _buildReceipt(_receiptFormat);

      await Printing.sharePdf(
        bytes: bytes,
        filename:
        'FiveStar_Bill_${widget.saleId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to share receipt.\n$e',
      );
    }
  }

  // ------------------------------------------------------------
  // ERROR
  // ------------------------------------------------------------

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ------------------------------------------------------------
  // SUCCESS
  // ------------------------------------------------------------

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hotel Bill',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: _shareReceipt,
            icon: const Icon(Icons.share),
          ),
        ],
      ),

      body: Column(
        children: [
          // SELECTED PRINTER
          Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.print),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    _loadingPrinter
                        ? 'Loading printer...'
                        : _selectedPrinter == null
                        ? 'No printer selected'
                        : 'Printer: ${_selectedPrinter!.name}',
                    style: const TextStyle(
                      fontWeight:
                      FontWeight.w600,
                    ),
                    overflow:
                    TextOverflow.ellipsis,
                  ),
                ),

                DropdownButton<String>(
                  value: _paperSize,
                  underline: const SizedBox(),
                  items: [
                    for (final entry in ReceiptPaper.labels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _changePaperSize(value);
                  },
                ),
              ],
            ),
          ),

          // RECEIPT PREVIEW
          Expanded(
            child: PdfPreview(
              key: ValueKey(_paperSize),
              build: (format) {
                return _buildReceipt(
                  _receiptFormat,
                );
              },
              initialPageFormat: _receiptFormat,
              pageFormats: {
                ReceiptPaper.labels[_paperSize] ??
                    'Bill': _receiptFormat,
              },
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: false,
              allowSharing: false,
              pdfFileName:
              'FiveStar_Bill_${widget.saleId}.pdf',
              maxPageWidth: 500,
            ),
          ),

          // ACTIONS
          SafeArea(
            child: Padding(
              padding:
              const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _systemPrint,
                      icon: const Icon(
                        Icons.print,
                      ),
                      label: const Text(
                        'Print',
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _savingPdf ? null : _savePdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(
                        _savingPdf ? 'Saving...' : 'Save PDF',
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed:
                      _printing ||
                          _selectedPrinter ==
                              null
                          ? null
                          : _printToSelectedPrinter,
                      icon: _printing
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                        CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                          Colors.white,
                        ),
                      )
                          : const Icon(
                        Icons.print,
                      ),
                      label: Text(
                        _printing
                            ? 'Printing...'
                            : 'Print Receipt',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
