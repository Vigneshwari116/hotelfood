/// POS sells all menu items regardless of recorded stock.
/// Stock may go negative when oversold.
bool posIsStocked(double stock) => true;

bool posAllowsAdd({required double stock, required double cartQty}) => true;

/// Returns null when quantity is not capped at the POS.
double? posMaxQty(double stock) => null;
