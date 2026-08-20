import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:foodstock/services/printer_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState
    extends State<PrinterSettingsScreen> {
  // ============================================================
  // STORAGE KEY
  // ============================================================

  static const String _printerKey = 'selected_printer';
  static const String _paperSizeKey = 'receipt_paper_size';

  // ============================================================
  // DATA
  // ============================================================

  List<Printer> _printers = [];

  Printer? _selectedPrinter;

  bool _loading = true;
  bool _saving = false;
  bool _printing = false;

  String _paperSize = '80mm';

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  // ============================================================
  // LOAD PRINTERS
  // ============================================================

  Future<void> _loadPrinters() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      // --------------------------------------------------------
      // GET SYSTEM PRINTERS
      // --------------------------------------------------------

      final printers = await Printing.listPrinters();

      // --------------------------------------------------------
      // GET SAVED SETTINGS
      // --------------------------------------------------------

      final prefs =
      await SharedPreferences.getInstance();

      final savedPrinter =
      prefs.getString(_printerKey);

      final savedPaperSize =
      prefs.getString(_paperSizeKey);

      Printer? selectedPrinter;

      // --------------------------------------------------------
      // RESTORE PAPER SIZE
      // --------------------------------------------------------

      if (ReceiptPaper.isValid(savedPaperSize)) {
        _paperSize = savedPaperSize!;
      }

      // --------------------------------------------------------
      // RESTORE SAVED PRINTER
      // --------------------------------------------------------

      if (savedPrinter != null &&
          savedPrinter.isNotEmpty) {
        try {
          final Map<String, dynamic> map =
          jsonDecode(savedPrinter)
          as Map<String, dynamic>;

          final saved =
          Printer.fromMap(map);

          // Find the matching printer from
          // the currently available system printers.
          for (final printer in printers) {
            if (printer.url == saved.url ||
                printer.name == saved.name) {
              selectedPrinter = printer;
              break;
            }
          }
        } catch (_) {
          selectedPrinter = null;
        }
      }

      // --------------------------------------------------------
      // IF NO SAVED PRINTER
      // USE DEFAULT PRINTER
      // --------------------------------------------------------

      if (selectedPrinter == null &&
          printers.isNotEmpty) {
        try {
          selectedPrinter = printers.firstWhere(
                (printer) => printer.isDefault,
          );
        } catch (_) {
          selectedPrinter = printers.first;
        }
      }

      if (!mounted) return;

      setState(() {
        _printers = printers;
        _selectedPrinter = selectedPrinter;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showError(
        'Unable to load printers.\n$e',
      );
    }
  }

  // ============================================================
  // SELECT PRINTER
  // ============================================================

  Future<void> _selectPrinter(
      Printer printer,
      ) async {
    if (_saving) return;

    setState(() {
      _selectedPrinter = printer;
      _saving = true;
    });

    try {
      final prefs =
      await SharedPreferences.getInstance();

      await prefs.setString(
        _printerKey,
        jsonEncode(
          printer.toMap(),
        ),
      );

      await prefs.setString(
        _paperSizeKey,
        _paperSize,
      );

      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showSuccess(
        '${printer.name} selected successfully.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        'Unable to save printer.\n$e',
      );
    }
  }

  // ============================================================
  // CHANGE PAPER SIZE
  // ============================================================

  Future<void> _changePaperSize(
      String value,
      ) async {
    setState(() {
      _paperSize = value;
    });

    try {
      final prefs =
      await SharedPreferences.getInstance();

      await prefs.setString(
        _paperSizeKey,
        value,
      );
    } catch (_) {
      // No need to show an error for this.
    }
  }

  // ============================================================
  // SYSTEM PRINTER PICKER
  // ============================================================

  Future<void> _pickPrinterFromSystem() async {
    try {
      final printer =
      await Printing.pickPrinter(
        context: context,
      );

      if (printer == null) {
        return;
      }

      await _selectPrinter(printer);

      await _loadPrinters();
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to open printer picker.\n$e',
      );
    }
  }

  // ============================================================
  // TEST PRINT
  // ============================================================

  Future<void> _testPrint() async {
    final printer = _selectedPrinter;

    if (printer == null) {
      _showError(
        'Please select a printer first.',
      );
      return;
    }

    if (_printing) {
      return;
    }

    setState(() {
      _printing = true;
    });

    try {
      // --------------------------------------------------------
      // RECEIPT PAPER SIZE
      // --------------------------------------------------------

      final PdfPageFormat format = ReceiptPaper.format(
        _paperSize,
        itemCount: 3,
      );

      // --------------------------------------------------------
      // DIRECT PRINT
      // --------------------------------------------------------

      final bool result =
      await Printing.directPrintPdf(
        printer: printer,
        name: 'Shilpa Enterprise Test Bill',
        format: format,
        onLayout: (format) async {
          return _buildTestReceipt(format);
        },
      );

      if (!mounted) return;

      setState(() {
        _printing = false;
      });

      if (result) {
        _showSuccess(
          'Test receipt sent to ${printer.name}.',
        );
      } else {
        _showError(
          'Printer did not accept the print job.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _printing = false;
      });

      _showError(
        'Test print failed.\n$e',
      );
    }
  }

  // ============================================================
  // BUILD TEST RECEIPT
  // ============================================================

  Future<Uint8List> _buildTestReceipt(
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
            pw.CrossAxisAlignment.center,
            children: [
              // ------------------------------------------------
              // RESTAURANT NAME
              // ------------------------------------------------

              pw.Text(
                'SHILPA ENTERPRISE',
                textAlign:
                pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight:
                  pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 4),

              pw.Text(
                'HOTEL BILL — TEST',
                style:
                const pw.TextStyle(
                  fontSize: 9,
                ),
              ),

              pw.SizedBox(height: 10),

              pw.Divider(),

              // ------------------------------------------------
              // TEST PRINT
              // ------------------------------------------------

              pw.Text(
                'PRINTER TEST RECEIPT',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight:
                  pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 10),

              // ------------------------------------------------
              // PRINTER
              // ------------------------------------------------

              pw.Align(
                alignment:
                pw.Alignment.centerLeft,
                child: pw.Text(
                  'Printer',
                  style:
                  pw.TextStyle(
                    fontWeight:
                    pw.FontWeight.bold,
                  ),
                ),
              ),

              pw.SizedBox(height: 3),

              pw.Align(
                alignment:
                pw.Alignment.centerLeft,
                child: pw.Text(
                  _selectedPrinter?.name ??
                      '',
                ),
              ),

              pw.SizedBox(height: 8),

              // ------------------------------------------------
              // PAPER SIZE
              // ------------------------------------------------

              pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Text(
                    'Paper Size',
                  ),
                  pw.Text(
                    _paperSize,
                  ),
                ],
              ),

              pw.SizedBox(height: 10),

              pw.Divider(),

              pw.SizedBox(height: 10),

              // ------------------------------------------------
              // TEST ITEMS
              // ------------------------------------------------

              _receiptRow(
                'Test Item',
                '₹100.00',
              ),

              pw.SizedBox(height: 5),

              _receiptRow(
                'Quantity',
                '1',
              ),

              pw.SizedBox(height: 10),

              pw.Divider(),

              // ------------------------------------------------
              // TOTAL
              // ------------------------------------------------

              pw.Row(
                mainAxisAlignment:
                pw.MainAxisAlignment
                    .spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL',
                    style:
                    pw.TextStyle(
                      fontWeight:
                      pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '₹100.00',
                    style:
                    pw.TextStyle(
                      fontWeight:
                      pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 15),

              // ------------------------------------------------
              // SUCCESS
              // ------------------------------------------------

              pw.Text(
                'Printer is working correctly.',
                textAlign:
                pw.TextAlign.center,
                style:
                pw.TextStyle(
                  fontWeight:
                  pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(height: 10),

              pw.Text(
                'Thank You',
                style:
                pw.TextStyle(
                  fontWeight:
                  pw.FontWeight.bold,
                ),
              ),
            ],
          );
        },
      ),
    );

    return Uint8List.fromList(
      await pdf.save(),
    );
  }

  // ============================================================
  // RECEIPT ROW
  // ============================================================

  pw.Widget _receiptRow(
      String title,
      String value,
      ) {
    return pw.Row(
      mainAxisAlignment:
      pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(title),
        pw.Text(value),
      ],
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(
      String message,
      ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
          Colors.red.shade700,
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // SUCCESS
  // ============================================================

  void _showSuccess(
      String message,
      ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
          Colors.green.shade700,
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  // ============================================================
  // PRINTER CARD
  // ============================================================

  Widget _printerCard(
      Printer printer,
      ) {
    final selected =
        _selectedPrinter != null &&
            _selectedPrinter!.url ==
                printer.url;

    return Card(
      margin:
      const EdgeInsets.only(
        bottom: 10,
      ),
      elevation:
      selected ? 3 : 1,
      clipBehavior:
      Clip.antiAlias,
      child: InkWell(
        onTap: _saving
            ? null
            : () => _selectPrinter(
          printer,
        ),
        child: Padding(
          padding:
          const EdgeInsets.all(16),
          child: Row(
            children: [
              // ------------------------------------------------
              // PRINTER ICON
              // ------------------------------------------------

              CircleAvatar(
                radius: 25,
                backgroundColor:
                selected
                    ? Colors.green
                    : Colors.grey
                    .shade200,
                child: Icon(
                  Icons.print,
                  color: selected
                      ? Colors.white
                      : Colors.grey
                      .shade700,
                ),
              ),

              const SizedBox(
                width: 14,
              ),

              // ------------------------------------------------
              // PRINTER DETAILS
              // ------------------------------------------------

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      printer.name,
                      maxLines: 2,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        fontSize: 16,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    if (printer.model !=
                        null &&
                        printer.model!
                            .isNotEmpty)
                      Text(
                        printer.model!,
                        style:
                        TextStyle(
                          color: Colors
                              .grey
                              .shade700,
                        ),
                      ),

                    if (printer.location !=
                        null &&
                        printer.location!
                            .isNotEmpty)
                      Padding(
                        padding:
                        const EdgeInsets
                            .only(
                          top: 2,
                        ),
                        child: Text(
                          printer.location!,
                          style:
                          TextStyle(
                            fontSize: 12,
                            color: Colors
                                .grey
                                .shade600,
                          ),
                        ),
                      ),

                    const SizedBox(
                      height: 6,
                    ),

                    // ------------------------------------------
                    // STATUS
                    // ------------------------------------------

                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        Row(
                          mainAxisSize:
                          MainAxisSize
                              .min,
                          children: [
                            Icon(
                              printer
                                  .isAvailable
                                  ? Icons
                                  .check_circle
                                  : Icons
                                  .cancel,
                              size: 16,
                              color: printer
                                  .isAvailable
                                  ? Colors.green
                                  : Colors.red,
                            ),

                            const SizedBox(
                              width: 5,
                            ),

                            Text(
                              printer
                                  .isAvailable
                                  ? 'Available'
                                  : 'Unavailable',
                              style:
                              TextStyle(
                                fontSize:
                                12,
                                color: printer
                                    .isAvailable
                                    ? Colors
                                    .green
                                    : Colors
                                    .red,
                              ),
                            ),
                          ],
                        ),

                        if (printer.isDefault)
                          const Chip(
                            label:
                            Text(
                              'Default',
                              style:
                              TextStyle(
                                fontSize:
                                11,
                              ),
                            ),
                            visualDensity:
                            VisualDensity
                                .compact,
                            padding:
                            EdgeInsets
                                .zero,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              // ------------------------------------------------
              // SELECTED ICON
              // ------------------------------------------------

              if (selected)
                const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 28,
                )
              else
                const Icon(
                  Icons
                      .radio_button_unchecked,
                  color: Colors.grey,
                  size: 26,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SELECTED PRINTER CARD
  // ============================================================

  Widget _selectedPrinterCard() {
    final printer = _selectedPrinter;

    return Card(
      elevation: 1,
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Text(
              'Selected Printer',
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            if (printer == null)
              Row(
                children: [
                  Icon(
                    Icons
                        .print_disabled,
                    color: Colors
                        .grey
                        .shade500,
                    size: 30,
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  const Expanded(
                    child: Text(
                      'No printer selected',
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor:
                    Colors.green
                        .shade100,
                    child: const Icon(
                      Icons.print,
                      color:
                      Colors.green,
                    ),
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        Text(
                          printer.name,
                          maxLines: 2,
                          overflow:
                          TextOverflow
                              .ellipsis,
                          style:
                          const TextStyle(
                            fontWeight:
                            FontWeight
                                .bold,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(
                          height: 4,
                        ),

                        Text(
                          printer.isAvailable
                              ? 'Ready to print'
                              : 'Printer unavailable',
                          style:
                          TextStyle(
                            color: printer
                                .isAvailable
                                ? Colors
                                .green
                                : Colors
                                .red,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Icon(
                    Icons
                        .check_circle,
                    color:
                    Colors.green,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PAPER SIZE CARD
  // ============================================================

  Widget _paperSizeCard() {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            const Text(
              'Receipt Paper',
              style: TextStyle(
                fontSize: 17,
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 5,
            ),

            Text(
              'Choose thermal roll or sheet size so the bill matches your printer.',
              style: TextStyle(
                color:
                Colors.grey.shade600,
                fontSize: 13,
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            DropdownButtonFormField<
                String>(
              value: _paperSize,
              decoration:
              const InputDecoration(
                labelText:
                'Paper Size',
                prefixIcon:
                Icon(Icons
                    .receipt_long),
                border:
                OutlineInputBorder(),
              ),
              items: [
                for (final entry in ReceiptPaper.labels.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged:
                  (value) {
                if (value == null) {
                  return;
                }

                _changePaperSize(
                  value,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      body: _loading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : RefreshIndicator(
        onRefresh:
        _loadPrinters,
        child: ListView(
          physics:
          const AlwaysScrollableScrollPhysics(),
          padding:
          const EdgeInsets.all(
            16,
          ),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Refresh printers',
                onPressed: _loading ? null : _loadPrinters,
                icon: const Icon(Icons.refresh),
              ),
            ),

            // ==================================================
            // SELECTED PRINTER
            // ==================================================

            _selectedPrinterCard(),

            const SizedBox(
              height: 16,
            ),

            // ==================================================
            // PAPER SIZE
            // ==================================================

            _paperSizeCard(),

            const SizedBox(
              height: 16,
            ),

            // ==================================================
            // SYSTEM PRINTER PICKER
            // ==================================================

            SizedBox(
              width:
              double.infinity,
              child:
              OutlinedButton.icon(
                onPressed:
                _pickPrinterFromSystem,
                icon:
                const Icon(
                  Icons.settings,
                ),
                label:
                const Text(
                  'Choose From System Printers',
                ),
                style:
                OutlinedButton.styleFrom(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    vertical: 15,
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ==================================================
            // AVAILABLE PRINTERS HEADER
            // ==================================================

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Available Printers',
                    style:
                    TextStyle(
                      fontSize: 18,
                      fontWeight:
                      FontWeight
                          .bold,
                    ),
                  ),
                ),

                Container(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration:
                  BoxDecoration(
                    color: Colors
                        .grey
                        .shade100,
                    borderRadius:
                    BorderRadius
                        .circular(
                      20,
                    ),
                  ),
                  child: Text(
                    '${_printers.length}',
                    style:
                    TextStyle(
                      color: Colors
                          .grey
                          .shade700,
                      fontWeight:
                      FontWeight
                          .bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(
              height: 12,
            ),

            // ==================================================
            // PRINTER LIST
            // ==================================================

            if (_printers.isEmpty)
              Card(
                child: Padding(
                  padding:
                  const EdgeInsets
                      .all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons
                            .print_disabled,
                        size: 55,
                        color: Colors
                            .grey
                            .shade500,
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      const Text(
                        'No printers found',
                        style:
                        TextStyle(
                          fontWeight:
                          FontWeight
                              .bold,
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(
                        height: 6,
                      ),

                      Text(
                        'Connect or install a printer and tap refresh.',
                        textAlign:
                        TextAlign
                            .center,
                        style:
                        TextStyle(
                          color: Colors
                              .grey
                              .shade600,
                        ),
                      ),

                      const SizedBox(
                        height: 15,
                      ),

                      OutlinedButton.icon(
                        onPressed:
                        _loadPrinters,
                        icon:
                        const Icon(
                          Icons.refresh,
                        ),
                        label:
                        const Text(
                          'Refresh',
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._printers.map(
                _printerCard,
              ),

            const SizedBox(
              height: 20,
            ),

            // ==================================================
            // TEST PRINT
            // ==================================================

            SizedBox(
              width:
              double.infinity,
              child:
              FilledButton.icon(
                onPressed:
                _printing ||
                    _saving ||
                    _selectedPrinter ==
                        null
                    ? null
                    : _testPrint,
                icon: _printing
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child:
                  CircularProgressIndicator(
                    strokeWidth:
                    2,
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
                      : 'Print Test Receipt',
                ),
                style:
                FilledButton.styleFrom(
                  padding:
                  const EdgeInsets
                      .symmetric(
                    vertical: 16,
                  ),
                ),
              ),
            ),

            const SizedBox(
              height: 12,
            ),

            // ==================================================
            // INFORMATION
            // ==================================================

            Card(
              color:
              Colors.blue.shade50,
              child: Padding(
                padding:
                const EdgeInsets
                    .all(14),
                child: Row(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Icon(
                      Icons
                          .info_outline,
                      color: Colors
                          .blue
                          .shade700,
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child: Text(
                        'Select a printer and a paper size (58mm, 80mm, A5 or A4). '
                            'Use "Print Test Receipt" to verify before sales.',
                        style:
                        TextStyle(
                          color: Colors
                              .blue
                              .shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(
              height: 20,
            ),
          ],
        ),
      ),
    );
  }
}
