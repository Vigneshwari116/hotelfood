import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodstock/model/models.dart';

class ReceiptScreen extends StatefulWidget {
  final int saleId;
  final List<CartLine> lines;

  final String customerName;
  final String paymentType;

  final double subtotal;
  final double tax;
  final double discount;
  final double grandTotal;

  const ReceiptScreen({
    super.key,
    required this.saleId,
    required this.lines,
    required this.customerName,
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

  String _paperSize = '80mm';

  bool _loadingPrinter = true;
  bool _printing = false;

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
          _loadingPrinter = false;
        });

        return;
      }

      if (!mounted) return;

      setState(() {
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
    final width = _paperSize == '58mm'
        ? 58 * PdfPageFormat.mm
        : 80 * PdfPageFormat.mm;

    final estimatedHeight =
        95 * PdfPageFormat.mm +
            widget.lines.length *
                12 *
                PdfPageFormat.mm;

    return PdfPageFormat(
      width,
      estimatedHeight,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 4 * PdfPageFormat.mm,
      marginLeft: 4 * PdfPageFormat.mm,
      marginRight: 4 * PdfPageFormat.mm,
    );
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
              // STORE NAME
              pw.Center(
                child: pw.Text(
                  'FOODSTOCK',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight:
                    pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 3),

              pw.Center(
                child: pw.Text(
                  'RESTAURANT & POS',
                  style:
                  const pw.TextStyle(
                    fontSize: 9,
                  ),
                ),
              ),

              pw.SizedBox(height: 8),

              pw.Divider(),

              // SALE INFORMATION
              pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Text(
                    'Receipt No.',
                    style:
                    const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),
                  pw.Text(
                    '#${widget.saleId}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight:
                      pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 3),

              pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Text(
                    'Date',
                    style:
                    const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),
                  pw.Text(
                    _formatDate(DateTime.now()),
                    style:
                    const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 3),

              pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Text(
                    'Customer',
                    style:
                    const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      widget.customerName,
                      textAlign:
                      pw.TextAlign.right,
                      style:
                      const pw.TextStyle(
                        fontSize: 9,
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 8),

              pw.Divider(),

              // TABLE HEADER
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text(
                      'ITEM',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight:
                        pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'QTY',
                      textAlign:
                      pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight:
                        pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text(
                      'AMOUNT',
                      textAlign:
                      pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight:
                        pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 5),

              pw.Divider(),

              // ITEMS
              ...widget.lines.map(
                    (line) {
                  return pw.Padding(
                    padding:
                    const pw.EdgeInsets
                        .symmetric(
                      vertical: 4,
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 5,
                          child: pw.Text(
                            line.name,
                            maxLines: 2,
                            style:
                            const pw.TextStyle(
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            '${line.qty}',
                            textAlign:
                            pw.TextAlign
                                .center,
                            style:
                            const pw.TextStyle(
                              fontSize: 8,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            '₹${line.amount.toStringAsFixed(2)}',
                            textAlign:
                            pw.TextAlign
                                .right,
                            style:
                            const pw.TextStyle(
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

              pw.SizedBox(height: 7),

              pw.Divider(),

              pw.SizedBox(height: 5),

              pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Text(
                    'Payment',
                    style:
                    const pw.TextStyle(
                      fontSize: 9,
                    ),
                  ),
                  pw.Text(
                    widget.paymentType,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight:
                      pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 15),

              pw.Center(
                child: pw.Text(
                  'Thank you! Visit Again',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight:
                    pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 4),

              pw.Center(
                child: pw.Text(
                  'Powered by FoodStock POS',
                  style:
                  const pw.TextStyle(
                    fontSize: 7,
                  ),
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
        name: 'FoodStock Receipt #${widget.saleId}',
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
        'FoodStock Receipt #${widget.saleId}',
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

  Future<void> _shareReceipt() async {
    try {
      final bytes =
      await _buildReceipt(_receiptFormat);

      await Printing.sharePdf(
        bytes: bytes,
        filename:
        'FoodStock_Receipt_${widget.saleId}.pdf',
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
          'Receipt',
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
                  underline:
                  const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: '58mm',
                      child: Text('58mm'),
                    ),
                    DropdownMenuItem(
                      value: '80mm',
                      child: Text('80mm'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;

                    setState(() {
                      _paperSize = value;
                    });
                  },
                ),
              ],
            ),
          ),

          // RECEIPT PREVIEW
          Expanded(
            child: PdfPreview(
              build: (format) {
                return _buildReceipt(
                  _receiptFormat,
                );
              },
              initialPageFormat:
              _receiptFormat,
              pageFormats: {
                'Receipt': _receiptFormat,
              },
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: false,
              allowSharing: false,
              pdfFileName:
              'FoodStock_Receipt_${widget.saleId}.pdf',
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
                      onPressed: _shareReceipt,
                      icon: const Icon(
                        Icons.share,
                      ),
                      label: const Text(
                        'Share',
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
