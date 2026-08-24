/// POS tap rules: untracked stock (0 or less) can still be sold;
/// recorded stock is a maximum.
bool posAllowsAdd({required double stock, required double cartQty}) {
  if (stock <= 0.000001) return true;
  return cartQty + 1 <= stock + 0.000001;
}

double? posMaxQty(double stock) {
  if (stock <= 0.000001) return null;
  return stock;
}
