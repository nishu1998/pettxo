// Firestore set({merge:true}) recursively merges maps, but never interprets
// dotted object keys as field paths. Arrays, Dates and Timestamps are atomic.
function plain(value) { return value != null && Object.getPrototypeOf(value) === Object.prototype; }
module.exports = function mergeFirestoreSet(before, patch) {
  const out = plain(before) ? {...before} : {};
  for (const [key, value] of Object.entries(patch)) {
    out[key] = plain(value) && Object.keys(value).length ? module.exports(out[key], value) : value;
  }
  return out;
};
