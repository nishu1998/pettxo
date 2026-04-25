class Geohash {
  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

  const Geohash._();

  static String encode(double latitude, double longitude, {int precision = 9}) {
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return '';
    }

    var isEven = true;
    var bit = 0;
    var ch = 0;
    var geohash = '';
    var latRange = [-90.0, 90.0];
    var lonRange = [-180.0, 180.0];

    while (geohash.length < precision) {
      if (isEven) {
        final mid = (lonRange[0] + lonRange[1]) / 2;
        if (longitude >= mid) {
          ch |= 1 << (4 - bit);
          lonRange[0] = mid;
        } else {
          lonRange[1] = mid;
        }
      } else {
        final mid = (latRange[0] + latRange[1]) / 2;
        if (latitude >= mid) {
          ch |= 1 << (4 - bit);
          latRange[0] = mid;
        } else {
          latRange[1] = mid;
        }
      }

      isEven = !isEven;
      if (bit < 4) {
        bit++;
      } else {
        geohash += _base32[ch];
        bit = 0;
        ch = 0;
      }
    }

    return geohash;
  }
}
