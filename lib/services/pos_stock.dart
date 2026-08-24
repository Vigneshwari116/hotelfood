/// POS only sells items that have stock recorded above zero.
bool posIsStocked(double stock) => stock > 0.000001;

bool posAllowsAdd({required double stock, required double cartQty}) {
  if (!posIsStocked(stock)) return false;
  return cartQty + 1 <= stock + 0.000001;
}

double posMaxQty(double stock) {
  if (!posIsStocked(stock)) return 0;
  return stock;
}
