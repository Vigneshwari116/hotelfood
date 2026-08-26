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
import 'package:foodstock/services/bluetooth_thermal_printer.dart';
import 'package:foodstock/services/receipt_document.dart';
import 'package:foodstock/services/receipt_layout.dart';
import 'package:foodstock/services/receipt_profile.dart';
import 'package:foodstock/widgets/brand_logo.dart';

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
    bool hasCustomer = false,
    bool hasTax = false,
    bool hasDiscount = false,
  }) {
    final mm = PdfPageFormat.mm;
    final lines = itemCount < 1 ? 1 : itemCount;

    switch (size) {
      case '58mm':
        var heightMm = 62.0 + lines * 5.0;
        if (hasCustomer) heightMm += 6;
        if (hasTax) heightMm += 3.5;
        if (hasDiscount) heightMm += 3.5;
        return PdfPageFormat(
          58 * mm,
          heightMm * mm,
          marginAll: 1 * mm,
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
          (78 + lines * 8) * mm,
          marginAll: 3 * mm,
        );
    }
  }

  static bool isThermal(String size) =>
      size == '58mm' || size == '80mm';
}

class ReceiptScreen extends StatefulWidget {
  final int saleId;
  final List<CartLine> lines;

  final String paymentType;

  final double subtotal;
  final double tax;
  final double discount;
  final double grandTotal;
  final String? customerName;
  final String? customerPhone;

  const ReceiptScreen({
    super.key,
    required this.saleId,
    required this.lines,
    required this.paymentType,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.grandTotal,
    this.customerName,
    this.customerPhone,
  });

  ReceiptDocument get _document => ReceiptDocument(
        saleId: saleId,
        lines: lines,
        paymentType: paymentType,
        subtotal: subtotal,
        tax: tax,
        discount: discount,
        grandTotal: grandTotal,
        customerName: customerName,
        customerPhone: customerPhone,
      );

  @override
  State<ReceiptScreen> createState() =>
      _ReceiptScreenState();
}

class _ReceiptScreenState
    extends State<ReceiptScreen> {
  static const String _printerKey =
      'selected_printer';

  Printer? _selectedPrinter;
  SavedThermalPrinter? _thermalPrinter;

  String _paperSize = ReceiptPaper.defaultSize;
  ReceiptProfile _profile = ReceiptProfile.defaults();

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

      final profile = await ReceiptProfile.load();
      final thermal = await BluetoothThermalPrinter.loadSaved();

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
          _thermalPrinter = thermal;
          _profile = profile;
          _paperSize = thermal != null ? '58mm' : paperSize;
          _loadingPrinter = false;
        });

        return;
      }

      if (!mounted) return;

      setState(() {
        _thermalPrinter = thermal;
        _profile = profile;
        _paperSize = thermal != null ? '58mm' : paperSize;
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
      hasCustomer: widget._document.hasCustomer,
      hasTax: widget.tax > 0,
      hasDiscount: widget.discount > 0,
    );
  }

  bool get _thermal => ReceiptPaper.isThermal(_paperSize);

  bool get _narrow => _paperSize == '58mm';

  double get _titleSize {
    if (_narrow) return 14;
    if (_thermal) return 13;
    if (_paperSize == 'A5') return 16;
    return 20;
  }

  double get _subtitleSize {
    if (_thermal) return 7;
    return 10;
  }

  double get _bodySize {
    if (_narrow) return 7;
    if (_thermal) return 8;
    return 10;
  }

  double get _totalSize {
    if (_narrow) return 10;
    if (_thermal) return 11;
    return 14;
  }

  double get _previewWidth {
    switch (_paperSize) {
      case '58mm':
        return 240;
      case '80mm':
        return 300;
      case 'A5':
        return 420;
      default:
        return 520;
    }
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

    pw.MemoryImage? chickenLogo;
    try {
      chickenLogo = pw.MemoryImage(
        (await rootBundle.load(BrandAssets.chicken)).buffer.asUint8List(),
      );
    } catch (_) {}

    final document = widget._document;
    final customerName = document.trimmedCustomerName;
    final customerPhone = document.trimmedCustomerPhone;

    pdf.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(_narrow ? 1.5 * PdfPageFormat.mm : 3 * PdfPageFormat.mm),
        build: (context) {
          return pw.Column(
            crossAxisAlignment:
            pw.CrossAxisAlignment.stretch,
            mainAxisAlignment: pw.MainAxisAlignment.start,
            children: [
              if (chickenLogo != null)
                pw.Center(
                  child: pw.Image(
                    chickenLogo,
                    height: _narrow ? 18 : 32,
                  ),
                ),

              pw.Center(
                child: pw.Text(
                  _profile.shopName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: _titleSize,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),

              if (_profile.address.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    _profile.address,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(fontSize: _subtitleSize),
                  ),
                ),

              if (_profile.phone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Mob No.-${_profile.phone}.',
                    style: pw.TextStyle(fontSize: _subtitleSize),
                  ),
                ),

              if (_profile.email.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Email:${_profile.email}',
                    style: pw.TextStyle(fontSize: _subtitleSize),
                  ),
                ),

              pw.SizedBox(height: _thermal ? 1 : 3),

              pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed),

              pw.Padding(
                padding: pw.EdgeInsets.only(top: _thermal ? 1 : 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Bill #${widget.saleId}',
                      style: pw.TextStyle(fontSize: _bodySize),
                    ),
                    pw.Text(
                      ReceiptLayout.billWhen(document.billedAt),
                      style: pw.TextStyle(fontSize: _bodySize),
                    ),
                  ],
                ),
              ),

              pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed),

              if (customerName != null) ...[
                pw.Text(
                  'Customer: $customerName',
                  style: pw.TextStyle(fontSize: _bodySize),
                ),
              ],
              if (customerPhone != null) ...[
                pw.Text(
                  'Mobile: $customerPhone',
                  style: pw.TextStyle(fontSize: _bodySize),
                ),
              ],
              if (customerName != null || customerPhone != null)
                pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed),

              _itemHeaderRow(),

              ...widget.lines.map(_itemRow),

              pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed),

              _pdfAmountRow(
                'SubTotal',
                widget.subtotal,
                fontSize: _bodySize,
              ),

              if (widget.tax > 0)
                _pdfAmountRow(
                  ReceiptLayout.taxLabel(widget.tax, widget.subtotal),
                  widget.tax,
                  fontSize: _bodySize,
                ),

              if (widget.discount > 0)
                _pdfAmountRow(
                  'Discount',
                  widget.discount,
                  fontSize: _bodySize,
                ),

              _pdfAmountRow(
                'Grand Total',
                widget.grandTotal,
                bold: true,
                fontSize: _totalSize,
              ),

              pw.SizedBox(height: _thermal ? 2 : 4),

              pw.Center(
                child: pw.Text(
                  'Thank You',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: _subtitleSize,
                    fontWeight: pw.FontWeight.bold,
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

  pw.Widget _itemHeaderRow() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3, bottom: 1),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Item x Qty',
              style: pw.TextStyle(
                fontSize: _bodySize,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(
            'Rate',
            style: pw.TextStyle(
              fontSize: _bodySize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _itemRow(CartLine line) {
    final qty = ReceiptLayout.qtyText(line.qty);

    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        vertical: _thermal ? 1.5 : 3,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${line.name} x $qty',
                  maxLines: 2,
                  style: pw.TextStyle(fontSize: _bodySize),
                ),
                if (ReceiptLayout.extraDetail(line.name, line.subItem))
                  pw.Text(
                    line.subItem!.trim(),
                    maxLines: 1,
                    style: pw.TextStyle(
                      fontSize: _bodySize - 0.5,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            ReceiptLayout.money(line.amount),
            style: pw.TextStyle(fontSize: _bodySize),
          ),
        ],
      ),
    );
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
          ReceiptLayout.money(value, forceDecimals: true),
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
  // DIRECT PRINT
  // ------------------------------------------------------------

  bool get _canDirectPrint {
    return _thermalPrinter != null || _selectedPrinter != null;
  }

  Future<void> _printToSelectedPrinter() async {
    if (!_canDirectPrint) {
      _showError(
        'No printer selected.\nOpen Printers and choose the POSiFLOW Bluetooth printer.',
      );
      return;
    }

    setState(() {
      _printing = true;
    });

    try {
      if (_thermalPrinter != null) {
        await BluetoothThermalPrinter.printSale(
          document: widget._document,
        );

        if (!mounted) return;
        _showSuccess(
          'Receipt sent to ${_thermalPrinter!.name}',
        );
        return;
      }

      final result =
      await Printing.directPrintPdf(
        printer: _selectedPrinter!,
        name: 'Shilpa Enterprise Bill #${widget.saleId}',
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
    if (_thermalPrinter != null) {
      await _printToSelectedPrinter();
      return;
    }

    try {
      await Printing.layoutPdf(
        name:
        'Shilpa Enterprise Bill #${widget.saleId}',
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
                        : _thermalPrinter != null
                        ? 'POSiFLOW: ${_thermalPrinter!.name}'
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
              maxPageWidth: _previewWidth,
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
                      _printing || !_canDirectPrint
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
