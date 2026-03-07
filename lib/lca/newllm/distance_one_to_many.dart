
// File: lib/lca/newllm/distance_one_to_many.dart
//
// Distance one-to-many tool with GRI filtering and max-distance filtering.
// Robust version: non-throwing, graceful degradation when destination tables are missing,
// and tolerant inputs. Keeps the original public signature and output structure.
//
// Update notes:
// - If args.sources is omitted or empty, candidates are auto-derived from the CEPII
//   distance table for the destination (international only, destination excluded).
// - GRI parser now accepts loose tokens like "r2", "<=2", "rank 2".
// - meta.sourceCount now reports the number of candidates actually considered.

import 'dart:math' as math;

/// Public entry point matching the controller's expected signature:
/// Map<String, dynamic> Function(Map<String, dynamic>)
Map<String, dynamic> distanceOneToMany(Map<String, dynamic> args) {
  // ---- Validate and normalise inputs (be permissive, never throw) ----
  final String destination = _asString(args['destination'])?.toUpperCase() ?? '';
  final List providedSourcesRaw = (args['sources'] as List?) ?? const [];

  // Default behaviour if maxGRI or maxDistance is omitted
  final dynamic maxGriArg = args.containsKey('maxGRI') ? args['maxGRI'] : '5+';
  final bool requireGri = args.containsKey('maxGRI');

  final Map<String, dynamic>? md = (args['maxDistance'] as Map?)?.cast<String, dynamic>();
  final double maxDistanceValueInUnits =
      (md?['value'] is num) ? (md!['value'] as num).toDouble() : double.infinity;
  final String units = _normaliseUnits(_asString(md?['units']) ?? 'km');
  final bool unitsOk = units == 'km' || units == 'mi';
  final String safeUnits = unitsOk ? units : 'km';

  if (destination.isEmpty) {
    return _errorResult(
      'UNKNOWN',
      safeUnits,
      'missing_destination',
      'destination (ISO-3) is required',
    );
  }

  // ---- Load distance table for destination, if available ----
  // Keep compatibility with the original table that only had DEU.
  final Map<String, double>? tableKm = _DIST_TABLES_BY_DEST[destination];

  // ---- Determine candidate sources ----
  // If the caller provides sources, use them. If not, auto-derive from the distance table.
  List<Map<String, dynamic>> candidateSources;

  if (providedSourcesRaw.isNotEmpty) {
    candidateSources = [];
    for (final s in providedSourcesRaw) {
      if (s is Map) {
        candidateSources.add(s.cast<String, dynamic>());
      } else {
        // Non-object items are dropped later in the main loop as invalid_source_item
        candidateSources.add({'_raw': s});
      }
    }
  } else if (tableKm != null) {
    // Auto-source mode: build a candidate per ISO3 in the table, excluding the destination.
    candidateSources = tableKm.keys
        .where((code) => code != destination)
        .map((code) => <String, dynamic>{
              'code': code,
              'name': _iso3ToName[code] ?? code,
              'score': 0.0, // neutral default - not used for filtering
            })
        .toList();
  } else {
    // No provided sources and no table to expand from - cannot proceed usefully
    return _errorResult(
      destination,
      safeUnits,
      'no_sources_available',
      'No sources provided and no distance table for destination $destination',
    );
  }

  final double maxDistanceKm = safeUnits == 'km'
      ? maxDistanceValueInUnits
      : maxDistanceValueInUnits / _MI_PER_KM;

  // ---- Process each source ----
  final List<Map<String, dynamic>> results = [];
  final List<Map<String, dynamic>> filteredOut = [];

  for (final s in candidateSources) {
    if (s is! Map) {
      filteredOut.add({
        'source': s,
        'reason': 'invalid_source_item',
        'details': 'Each item must be an object with code/name/score.',
      });
      continue;
    }
    final src = s.cast<String, dynamic>();

    final String? rawCode = _asString(src['code']);
    final String code = (rawCode ?? '').toUpperCase();
    String? name = _asString(src['name']);
    final double? score = (src['score'] is num) ? (src['score'] as num).toDouble() : null;

    if (score == null) {
      filteredOut.add({
        'code': code.isEmpty ? null : code,
        'name': name,
        'reason': 'missing_score',
      });
      continue;
    }

    // Try to infer ISO3 code from name when missing
    String inferredCode = code;
    if (inferredCode.isEmpty && name != null) {
      inferredCode = _nameToIso3[name.trim().toLowerCase()] ?? '';
    }
    if (inferredCode.isEmpty) {
      filteredOut.add({
        'code': null,
        'name': name,
        'score': score,
        'reason': 'unknown_source_code',
      });
      continue;
    }

    // Exclude the destination itself to ensure international only
    if (inferredCode == destination) {
      filteredOut.add({
        'code': inferredCode,
        'name': name ?? _iso3ToName[inferredCode] ?? inferredCode,
        'score': score,
        'reason': 'same_as_destination',
      });
      continue;
    }

    // Resolve a display name from ISO3 when name is missing
    name ??= _iso3ToName[inferredCode] ?? inferredCode;

    // Distance in km if we have a table for this destination
    final bool haveDistances = tableKm != null;
    final double? distKm = haveDistances ? tableKm[inferredCode] : null;

    if (haveDistances && distKm == null) {
      // We have a table, but not for this source code
      filteredOut.add({
        'code': inferredCode,
        'name': name,
        'score': score,
        'reason': 'no_distance_for_code',
      });
      continue;
    }

    // GRI rating and rank
    final String resolvedNameForGri = _normaliseNameForGRI(name);
    final String? gri = _griScores[name] ??
        _griScores[resolvedNameForGri] ??
        _griScores[_iso3ToName[inferredCode] ?? ''];

    // If the user explicitly set a maxGRI, we must enforce it.
    // If they did not, we do not exclude for missing GRI.
    if (requireGri && gri == null) {
      filteredOut.add({
        'code': inferredCode,
        'name': name,
        'score': score,
        'reason': 'missing_gri_rating',
      });
      continue;
    }

    final int maxGriRank = _safeGriRank(maxGriArg);
    final int griRank = gri != null ? _safeGriRank(gri) : 1; // assume best when not required

    // Apply filters
    final bool overMaxGRI = requireGri ? griRank > maxGriRank : false;
    final bool overMaxDistance = haveDistances
        ? (distKm ?? double.infinity) > maxDistanceKm
        : false; // if no distances, do not exclude on distance

    if (overMaxGRI || overMaxDistance) {
      final reasons = <String>[];
      if (overMaxGRI) reasons.add('over_max_gri');
      if (overMaxDistance) reasons.add('over_max_distance');
      filteredOut.add({
        'code': inferredCode,
        'name': name,
        'score': score,
        if (gri != null) 'gri': gri,
        if (distKm != null) 'distanceKm': _round(distKm, 3),
        'reason': reasons.join(','),
      });
      continue;
    }

    // Passed
    final double outDist =
        safeUnits == 'km' ? (distKm ?? double.nan) : ((distKm ?? double.nan) * _MI_PER_KM);

    results.add({
      'code': inferredCode,
      'name': name,
      'score': _round(score, 6),
      if (gri != null) 'gri': gri,
      if (gri != null) 'griCategory': _griCategoryText[gri] ?? 'Unknown',
      'distance': {
        // If we do not have distances for this destination, distance.value will be NaN
        'value': haveDistances ? _round(outDist, 3) : double.nan,
        'units': safeUnits,
        'method': haveDistances ? 'precomputed_great_circle_${destination}_km' : 'no_distance_table_for_destination',
      },
    });
  }

  // Sort by distance when available, else by score descending
  results.sort((a, b) {
    final double da = (a['distance']['value'] as num).toDouble();
    final double db = (b['distance']['value'] as num).toDouble();
    final bool daOk = !da.isNaN;
    final bool dbOk = !db.isNaN;

    if (daOk && dbOk && da != db) return da.compareTo(db);
    if (daOk != dbOk) return daOk ? -1 : 1;

    final double sa = (a['score'] as num).toDouble();
    final double sb = (b['score'] as num).toDouble();
    return sb.compareTo(sa);
  });

  // Build meta
  final meta = <String, dynamic>{
    'maxGRI': maxGriArg,
    'maxGRIRank': _safeGriRank(maxGriArg),
    'maxDistance': {
      'value': (safeUnits == 'km') ? maxDistanceKm : maxDistanceKm * _MI_PER_KM,
      'units': safeUnits
    },
    'sourceCount': candidateSources.length,
    'included': results.length,
    'excluded': filteredOut.length,
    if (!unitsOk) 'note': 'Invalid units provided. Falling back to "km".',
    if (tableKm == null)
      'warning':
          'No distance table for destination $destination. Distance filtering disabled for this run.',
  };

  return {
    'destination': {'code': destination, 'name': _iso3ToName[destination] ?? destination},
    'units': safeUnits,
    'results': results,
    'filtered_out': filteredOut,
    'meta': meta,
  };
}

// ---------------- Helpers and data ----------------

String _normaliseUnits(String s) => s.trim().toLowerCase();
String? _asString(dynamic v) => v is String ? v : null;

double _round(double v, int places) {
  final p = math.pow(10, places).toDouble();
  return (v * p).round().toDouble() / p;
}

// Rank: 1 < 2 < 3 < 4 < 5 < 5+ (worst). Accept numbers or strings. Clamp to 1..6.
int _safeGriRank(dynamic v) {
  try {
    return _griRank(v);
  } catch (_) {
    return 6;
  }
}

// Rank decoder used internally - now tolerant of tokens like "r2", "<=2", "rank 2"
int _griRank(dynamic v) {
  if (v is num) return v.toInt().clamp(1, 6);
  final s0 = _asString(v)?.trim();
  if (s0 == null || s0.isEmpty) throw ArgumentError('Invalid GRI value: $v');
  final s = s0.toLowerCase();
  if (s == '5+' || s == '5 plus' || s == '5plus') return 6;
  // Extract first integer found
  final match = RegExp(r'\d+').firstMatch(s);
  if (match == null) throw ArgumentError('Invalid GRI value: $v');
  final n = int.parse(match.group(0)!);
  return n.clamp(1, 6);
}

Map<String, dynamic> _errorResult(String dest, String units, String code, String msg) => {
      'destination': {'code': dest, 'name': _iso3ToName[dest] ?? dest},
      'units': units,
      'results': const [],
      'filtered_out': const [],
      'meta': {
        'error': code,
        'message': msg,
      }
    };

String _normaliseNameForGRI(String name) {
  // Common aliases to GRI keys
  final n = name.trim();
  switch (n) {
    case 'UK':
    case 'Great Britain':
    case 'Britain':
      return 'United Kingdom';
    case 'USA':
    case 'United States':
      return 'United States of America';
    case 'South Korea':
      return 'Korea (Republic of)';
    case 'North Korea':
      return 'Korea (Democratic People\'s Republic of)'; // not in provided GRI list
    case 'Czech Republic':
      return 'Czechia';
    case 'Ivory Coast':
      return 'Côte d’Ivoire';
    case 'UAE':
      return 'United Arab Emirates';
    case 'Russia':
      return 'Russian Federation';
    case 'Turkey':
      return 'Türkiye';
    default:
      return n;
  }
}

const double _MI_PER_KM = 0.621371192;

// Minimal ISO3 to common name map for display;
// keep existing entries and behaviour.
const Map<String, String> _iso3ToName = {
  'DEU': 'Germany',
  'GBR': 'United Kingdom',
  'IRL': 'Ireland',
  'FRA': 'France',
  'ESP': 'Spain',
  'PRT': 'Portugal',
  'ITA': 'Italy',
  'NLD': 'Netherlands',
  'BEL': 'Belgium',
  'CHE': 'Switzerland',
  'AUT': 'Austria',
  'POL': 'Poland',
  'CZE': 'Czechia',
  'SVK': 'Slovakia',
  'SVN': 'Slovenia',
  'HRV': 'Croatia',
  'HUN': 'Hungary',
  'ROU': 'Romania',
  'ROM': 'Romania', // legacy code in your table
  'UKR': 'Ukraine',
  'RUS': 'Russian Federation',
  'TUR': 'Türkiye',
  'GRC': 'Greece',
  'CYP': 'Cyprus',
  'ISL': 'Iceland',
  'NOR': 'Norway',
  'SWE': 'Sweden',
  'FIN': 'Finland',
  'DNK': 'Denmark',
  'EST': 'Estonia',
  'LVA': 'Latvia',
  'LTU': 'Lithuania',
  'BLR': 'Belarus',
  'GEO': 'Georgia',
  'ARM': 'Armenia',
  'AZE': 'Azerbaijan',
  'KAZ': 'Kazakhstan',
  'UZB': 'Uzbekistan',
  'TJK': 'Tajikistan',
  'TKM': 'Turkmenistan',
  'KGZ': 'Kyrgyzstan',
  'MNG': 'Mongolia',
  'AFG': 'Afghanistan',
  'PAK': 'Pakistan',
  'NPL': 'Nepal',
  'LKA': 'Sri Lanka',
  'BTN': 'Bhutan',
  'BGD': 'Bangladesh',
  'MMR': 'Myanmar',
  'THA': 'Thailand',
  'LAO': 'Laos',
  'VNM': 'Vietnam',
  'KHM': 'Cambodia',
  'MYS': 'Malaysia',
  'SGP': 'Singapore',
  'IDN': 'Indonesia',
  'PHL': 'Philippines',
  'TWN': 'Taiwan',
  'HKG': 'Hong Kong',
  'CHN': 'China',
  'KOR': 'Korea (Republic of)',
  'JPN': 'Japan',
  'SAU': 'Saudi Arabia',
  'ARE': 'United Arab Emirates',
  'QAT': 'Qatar',
  'KWT': 'Kuwait',
  'BHR': 'Bahrain',
  'OMN': 'Oman',
  'IRN': 'Iran',
  'IRQ': 'Iraq',
  'JOR': 'Jordan',
  'LBN': 'Lebanon',
  'ISR': 'Israel',
  'PAL': 'Palestine', // appears as PAL in your table
  'EGY': 'Egypt',
  'LBY': 'Libya',
  'MAR': 'Morocco',
  'DZA': 'Algeria',
  'TUN': 'Tunisia',
  'MLT': 'Malta',
  'NER': 'Niger',
  'NGA': 'Nigeria',
  'GHA': 'Ghana',
  'CIV': 'Côte d’Ivoire',
  'SEN': 'Senegal',
  'GIN': 'Guinea',
  'GMB': 'Gambia',
  'SLE': 'Sierra Leone',
  'MLI': 'Mali',
  'CMR': 'Cameroon',
  'TCD': 'Chad',
  'CAF': 'Central African Republic',
  'COG': 'Congo (Republic of)',
  'COD': 'Congo (Democratic Republic of)',
  'GAB': 'Gabon',
  'GNQ': 'Equatorial Guinea',
  'UGA': 'Uganda',
  'RWA': 'Rwanda',
  'BDI': 'Burundi',
  'ETH': 'Ethiopia',
  'SDN': 'Sudan',
  'SSD': 'South Sudan',
  'TZA': 'Tanzania',
  'KEN': 'Kenya',
  'SOM': 'Somalia',
  'ZAF': 'South Africa',
  'ZMB': 'Zambia',
  'ZWE': 'Zimbabwe',
  'MWI': 'Malawi',
  'MOZ': 'Mozambique',
  'AGO': 'Angola',
  'NAM': 'Namibia',
  'BWA': 'Botswana',
  'SWZ': 'Eswatini',
  'LSO': 'Lesotho',
  'AUS': 'Australia',
  'NZL': 'New Zealand',
  'USA': 'United States of America',
  'CAN': 'Canada',
  'MEX': 'Mexico',
  'BRA': 'Brazil',
  'ARG': 'Argentina',
  'CHL': 'Chile',
  'PER': 'Peru',
  'COL': 'Colombia',
  'URY': 'Uruguay',
  // ... extend if needed
};

// Optional: name to ISO3 for backfilling when only a name is given
final Map<String, String> _nameToIso3 = {
  for (final e in _iso3ToName.entries) e.value.toLowerCase(): e.key,
  'uk': 'GBR',
  'united states': 'USA',
  'usa': 'USA',
  'russia': 'RUS',
  'turkey': 'TUR',
  'uae': 'ARE',
  'ivory coast': 'CIV',
  'south korea': 'KOR',
};

// Your provided GRI mapping
const Map<String, String> _griScores = {
  // Rating 5+ : NO GUARANTEE OF RIGHTS DUE TO THE BREAKdown OF THE LAW
  "Afghanistan": "5+",
  "Burundi": "5+",
  "Central African Republic": "5+",
  "Haiti": "5+",
  "Libya": "5+",
  "Myanmar": "5+",
  "Palestine": "5+",
  "Somalia": "5+",
  "South Sudan": "5+",
  "Sudan": "5+",
  "Syria": "5+",
  "Yemen": "5+",

  // Rating 5 : NO GUARANTEE OF RIGHTS
  "Algeria": "5",
  "Bahrain": "5",
  "Bangladesh": "5",
  "Belarus": "5",
  "Cambodia": "5",
  "China": "5",
  "Colombia": "5",
  "Ecuador": "5",
  "Egypt": "5",
  "Eritrea": "5",
  "Eswatini": "5",
  "Guatemala": "5",
  "Honduras": "5",
  "Hong Kong": "5",
  "India": "5",
  "Indonesia": "5",
  "Iran": "5",
  "Iraq": "5",
  "Jordan": "5",
  "Kazakhstan": "5",
  "Korea (Republic of)": "5",
  "Kuwait": "5",
  "Kyrgyzstan": "5",
  "Laos": "5",
  "Malaysia": "5",
  "Mauritania": "5",
  "Nigeria": "5",
  "Pakistan": "5",
  "Philippines": "5",
  "Qatar": "5",
  "Russian Federation": "5",
  "Saudi Arabia": "5",
  "Thailand": "5",
  "Tunisia": "5",
  "Türkiye": "5",
  "Ukraine": "5",
  "United Arab Emirates": "5",
  "Venezuela": "5",
  "Zimbabwe": "5",

  // Rating 4 : SYSTEMATIC VIOLATIONS OF RIGHTS
  "Angola": "4",
  "Argentina": "4",
  "Benin": "4",
  "Botswana": "4",
  "Brazil": "4",
  "Burkina Faso": "4",
  "Cameroon": "4",
  "Chad": "4",
  "Congo (Democratic Republic of)": "4",
  "Costa Rica": "4",
  "Djibouti": "4",
  "El Salvador": "4",
  "Ethiopia": "4",
  "Fiji": "4",
  "Georgia": "4",
  "Greece": "4",
  "Guinea": "4",
  "Guinea-Bissau": "4",
  "Hungary": "4",
  "Israel": "4",
  "Kenya": "4",
  "Lebanon": "4",
  "Lesotho": "4",
  "Liberia": "4",
  "Madagascar": "4",
  "Mali": "4",
  "Niger": "4",
  "North Macedonia": "4",
  "Panama": "4",
  "Peru": "4",
  "Senegal": "4",
  "Serbia": "4",
  "Sierra Leone": "4",
  "Sri Lanka": "4",
  "Tanzania": "4",
  "Trinidad and Tobago": "4",
  "Uganda": "4",
  "United Kingdom": "4",
  "United States of America": "4",
  "Vietnam": "4",
  "Zambia": "4",

  // Rating 3 : REGULAR VIOLATIONS OF RIGHTS
  "Albania": "3",
  "Armenia": "3",
  "Bahamas": "3",
  "Belgium": "3",
  "Belize": "3",
  "Bolivia": "3",
  "Bosnia and Herzegovina": "3",
  "Bulgaria": "3",
  "Canada": "3",
  "Chile": "3",
  "Congo (Republic of)": "3",
  "Côte d’Ivoire": "3",
  "Gabon": "3",
  "Jamaica": "3",
  "Mauritius": "3",
  "Mexico": "3",
  "Montenegro": "3",
  "Morocco": "3",
  "Mozambique": "3",
  "Namibia": "3",
  "Nepal": "3",
  "Oman": "3",
  "Paraguay": "3",
  "Poland": "3",
  "Romania": "3",
  "Rwanda": "3",
  "South Africa": "3",
  "Switzerland": "3",
  "Togo": "3",

  // Rating 2 : REPEATED VIOLATIONS OF RIGHTS
  "Australia": "2",
  "Barbados": "2",
  "Croatia": "2",
  "Czechia": "2",
  "Dominican Republic": "2",
  "Estonia": "2",
  "Finland": "2",
  "France": "2",
  "Ghana": "2",
  "Italy": "2",
  "Japan": "2",
  "Latvia": "2",
  "Lithuania": "2",
  "Malawi": "2",
  "Moldova": "2",
  "Netherlands": "2",
  "New Zealand": "2",
  "Portugal": "2",
  "Singapore": "2",
  "Slovakia": "2",
  "Spain": "2",
  "Taiwan": "2",
  "Uruguay": "2",

  // Rating 1 : SPORADIC VIOLATIONS OF RIGHTS
  "Austria": "1",
  "Denmark": "1",
  "Germany": "1",
  "Iceland": "1",
  "Ireland": "1",
  "Norway": "1",
  "Sweden": "1",
};

// Category text for descriptions
const Map<String, String> _griCategoryText = {
  '5+': 'No guarantee of rights due to the breakdown of the law',
  '5': 'No guarantee of rights',
  '4': 'Systematic violations of rights',
  '3': 'Regular violations of rights',
  '2': 'Repeated violations of rights',
  '1': 'Sporadic violations of rights',
};

// Distances from destination to ISO-3 codes, in kilometres.
// Original table was only for DEU. Keep as-is and plug into a map by destination.
const Map<String, Map<String, double>> _DEU_DIST_KM = {
  'DEU': {
    "ABW": 8231.708,
    "AFG": 4945.52,
    "AGO": 6825.559,
    "AIA": 7267.052,
    "ALB": 1383.712,
    "AND": 1182.827,
    "ANT": 8066.369,
    "ARE": 4823.589,
    "ARG": 11646.03,
    "ARM": 2934.269,
    "ATG": 7277.712,
    "AUS": 15935.09,
    "AUT": 592.3267,
    "AZE": 3218.327,
    "BDI": 6373.8,
    "BEL": 423.3463,
    "BEN": 4911.565,
    "BFA": 4503.403,
    "BGD": 7347.78,
    "BGR": 1503.343,
    "BHR": 4422.71,
    "BHS": 7665.657,
    "BIH": 1020.18,
    "BLR": 1262.182,
    "BLZ": 9065.331,
    "BMU": 6240.838,
    "BOL": 10575.86,
    "BRA": 9395.881,
    "BRB": 7459.262,
    "BRN": 10614.45,
    "BTN": 7014.233,
    "BWA": 8473.321,
    "CAF": 5231.482,
    "CAN": 6541.714,
    "CHE": 543.4735,
    "CHL": 12267.26,
    "CHN": 8031.667,
    "CIV": 5222.712,
    "CMR": 5072.483,
    "COG": 6192.056,
    "COK": 16502.69,
    "COL": 9137.329,
    "COM": 7764.539,
    "CPV": 4979.282,
    "CRI": 9425.447,
    "CUB": 8097.509,
    "CYM": 8435.141,
    "CYP": 2620.761,
    "CZE": 483.3867,
    "DEU": 301.0826,
    "DJI": 5357.301,
    "DMA": 7387.663,
    "DNK": 537.62,
    "DOM": 7709.526,
    "DZA": 1812.23,
    "ECU": 10096.2,
    "EGY": 2956.822,
    "ERI": 4826.117,
    "ESH": 3396.892,
    "ESP": 1627.346,
    "EST": 1321.21,
    "ETH": 5378.895,
    "FIN": 1435.278,
    "FJI": 16157.92,
    "FLK": 13109.14,
    "FRA": 789.5815,
    "FRO": 1563.716,
    "FSM": 12591.16,
    "GAB": 5731.293,
    "GBR": 808.641,
    "GEO": 2771.096,
    "GHA": 5105.261,
    "GIB": 2088.955,
    "GIN": 5072.055,
    "GLP": 7327.432,
    "GMB": 4838.93,
    "GNB": 4959.793,
    "GNQ": 5422.414,
    "GRC": 1810.254,
    "GRD": 7686.532,
    "GRL": 3702.079,
    "GTM": 9458.776,
    "GUF": 7715.788,
    "GUY": 7928.409,
    "HKG": 9026.214,
    "HND": 9220.706,
    "HRV": 853.229,
    "HTI": 7872.879,
    "HUN": 841.2282,
    "IDN": 11030.03,
    "IND": 6565.789,
    "IRL": 1169.722,
    "IRN": 3811.351,
    "IRQ": 3448.862,
    "ISL": 2316.602,
    "ISR": 2972.164,
    "ITA": 1013.826,
    "JAM": 8243.737,
    "JOR": 3036.515,
    "JPN": 9086.037,
    "KAZ": 4333.309,
    "KEN": 6409.654,
    "KGZ": 4848.92,
    "KHM": 9310.814,
    "KIR": 13979.2,
    "KNA": 7273.679,
    "KOR": 8503.73,
    "KWT": 3999.126,
    "LAO": 8725.066,
    "LBN": 2848.546,
    "LBR": 5355.48,
    "LBY": 2231.11,
    "LCA": 7479.724,
    "LKA": 8003.832,
    "LSO": 9158.263,
    "LTU": 1037.258,
    "LUX": 377.74,
    "LVA": 1125.732,
    "MAR": 2404.765,
    "MDA": 1463.109,
    "MDG": 8665.77,
    "MDV": 7886.07,
    "MEX": 9475.768,
    "MHL": 13190.83,
    "MKD": 1403.964,
    "MLI": 4525.833,
    "MLT": 1772.423,
    "MMR": 8202.389,
    "MNG": 6409.082,
    "MNP": 11485.13,
    "MOZ": 8425.986,
    "MRT": 4293.281,
    "MTQ": 7426.871,
    "MUS": 9224.183,
    "MWI": 7701.453,
    "MYS": 9986.959,
    "NAM": 8196.301,
    "NCL": 16160.98,
    "NER": 4181.92,
    "NFK": 16951.88,
    "NGA": 4846.996,
    "NIC": 9363.904,
    "NIU": 16429.35,
    "NLD": 379.1754,
    "NOR": 1038.91,
    "NPL": 6636.189,
    "NRU": 13977.27,
    "NZL": 18219.9,
    "OMN": 5138.525,
    "PAK": 5550.772,
    "PAL": 2999.04,
    "PAN": 9246.935,
    "PER": 10747.49,
    "PHL": 10308.54,
    "PLW": 11639.45,
    "PNG": 13779.21,
    "POL": 697.9935,
    "PRI": 7477.402,
    "PRK": 8198.39,
    "PRT": 2021.61,
    "PRY": 10733.88,
    "PYF": 15845.72,
    "QAT": 4553.797,
    "REU": 9209.298,
    "ROM": 1341.096,
    "RUS": 2654.584,
    "RWA": 6238.126,
    "SAU": 4211.321,
    "SDN": 4551.761,
    "SEN": 4745.513,
    "SGP": 10180.76,
    "SHN": 7772.667,
    "SLB": 14596.16,
    "SLE": 5204.68,
    "SLV": 9439.856,
    "SMR": 870.0517,
    "SOM": 6232.701,
    "SPM": 4677.535,
    "STP": 5688.891,
    "SUR": 7793.067,
    "SVK": 751.6134,
    "SVN": 711.9847,
    "SWE": 929.3204,
    "SWZ": 8916.29,
    "SYC": 7589.414,
    "SYR": 2842.564,
    "TCA": 7558.455,
    "TCD": 4511.328,
    "TGO": 4983.175,
    "THA": 8877.51,
    "TJK": 4724.228,
    "TKL": 15334.66,
    "TKM": 4041.977,
    "TMP": 12547.27,
    "TON": 16597.13,
    "TTO": 7813.286,
    "TUN": 1728.645,
    "TUR": 2167.774,
    "TUV": 15075.38,
    "TWN": 9275.322,
    "TZA": 6900.44,
    "UGA": 6029.86,
    "UKR": 1695.696,
    "URY": 11495.73,
    "USA": 7595.452,
    "UZB": 4539.407,
    "VCT": 7565.869,
    "VEN": 8289.505,
    "VGB": 7352.69,
    "VNM": 9259.051,
    "VUT": 15744.82,
    "WLF": 15753.65,
    "WSM": 15845.2,
    "YEM": 5135.836,
    "YUG": 1159.349,
    "ZAF": 9110.947,
    "ZAR": 6392.761,
    "ZMB": 7516.817,
    "ZWE": 8044.164
  },
};

// Destination keyed map of distance tables.
// At present we only have DEU. Add more destinations here when available.
final Map<String, Map<String, double>> _DIST_TABLES_BY_DEST = {
  'DEU': _DEU_DIST_KM['DEU']!,
};
