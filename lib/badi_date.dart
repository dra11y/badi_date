import 'package:badi_date/bahai_holyday.dart';
import 'package:badi_date/names.dart';
import 'package:badi_date/years.dart';
import 'package:dart_suncalc/suncalc.dart';

/// A Badi Date
class BadiDate {
  static const LAST_YEAR_SUPPORTED = 221;
  static const YEAR_ONE_IN_GREGORIAN = 1844;
  static const LAST_GREGORIAN_YEAR_SUPPORTED =
      LAST_YEAR_SUPPORTED + YEAR_ONE_IN_GREGORIAN;

  static const YEAR_ZERO_IN_GREGORIAN = YEAR_ONE_IN_GREGORIAN - 1;

  static List<String>? monthNames([String language = 'en']) =>
      MONTH_NAME_TRANSLATIONS[language]?.values.toList();

  static List<String> get monthNameTransliterations =>
      MONTH_NAMES.values.toList();

  static List<String>? monthTransliterationsWithNames(
      [String language = 'en']) {
    final languageNames = monthNames(language);
    if (languageNames == null) return null;
    return [
      for (int i = 0; i < 19; i++)
        '${monthNameTransliterations[i]} (${languageNames[i]})'
    ];
  }

  final int day;

  /// The month number with Baha = 1, ... Ayyam'i'Ha = 19, and Ala = 20
  int _monthIntern = -1;

  /// The month number with Ayyam'i'Ha = 0 and Baha = 1, ... Ala = 19
  final int month;

  /// The full year of the Badi Calendar with 2020 AC = 177 BE
  final int year;

  /// longitude value of degree coordinates for sunset calculation in the range [-180,180]
  final double? longitude;

  /// latitude value of degree coordinates for sunset calculation in the range [-90,90]
  final double? latitude;

  /// altitude in meters
  final double? altitude;

  /// Badi date
  /// for now only for the years up to LAST_YEAR_SUPPORTED
  /// Dates before the year 172 are calculated according to the Baha'i Calendar
  /// used in western countries.
  /// parameters:
  /// day int in range [1-19]
  /// month int in range [0-19]
  /// year int
  /// longitude and latitude double for sunset calculation
  /// ayyamIHa bool
  /// For Ayyam'i'Ha set month to 0 or leave it empty and set ayyamIHa to true
  BadiDate(
      {required this.day,
      this.month = 0,
      required this.year,
      bool ayyamIHa = false,
      this.latitude,
      this.longitude,
      this.altitude}) {
    if (day < 1 || day > 19) {
      throw ArgumentError.value(day, 'day', 'Day must be in the range [1-19]');
    }
    if (month < 0 || month > 19) {
      throw ArgumentError.value(
          month, 'month', 'Month must be in the range [1-19]');
    }
    if (month != 0 && ayyamIHa) {
      throw ArgumentError.value(
          month, 'month', 'Please set month to 0 or leave it out for AyyamIHa');
    }
    if (year > LAST_YEAR_SUPPORTED) {
      throw UnsupportedError(
          'Years greater than $LAST_YEAR_SUPPORTED are not supported yet');
    }
    _monthIntern = month == 0
        ? 19
        : month == 19
            ? 20
            : month;
  }

  /// The year in the Vahid. A value in the range from [1-19]
  int get yearInVahid {
    return year % 19 == 0 ? 19 : year % 19;
  }

  String? get yearName {
    return YEAR_NAMES[year];
  }

  /// Vahid = 19 years
  int get vahid {
    return (year / 19).floor() + 1;
  }

  String? get vahidName {
    return YEAR_NAMES[vahid];
  }

  /// Kull'i'shay = 19 Vahids = 361 years
  int get kullIShay {
    return (year / 361).floor() + 1;
  }

  String? get monthName {
    return isAyyamIHa ? AYYAMIHA_NAME : MONTH_NAMES[month];
  }

  String? get monthNameEnTr {
    return '${monthNameIn('en')} ($monthName)';
  }

  String? get monthNameTrEn {
    return '$monthName (${monthNameIn('en')})';
  }

  String? monthNameIn(String languageCode) {
    return isAyyamIHa
        ? AYYAMIHA_NAME
        : MONTH_NAME_TRANSLATIONS[languageCode]?[month] ?? MONTH_NAMES[month];
  }

  /// Number of Ayyam'i'ha days the year has
  /// For years < 172: use only for January 1st to before Naw-Ruz
  static int _getNumberAyyamIHaDays(int year) {
    final yearSpecific = yearSpecifics[year];
    if (yearSpecific == null) {
      final gregYear = year + YEAR_ONE_IN_GREGORIAN;
      final isleapyear =
          gregYear % 4 == 0 && gregYear % 100 != 0 || gregYear % 400 == 0;
      return isleapyear ? 5 : 4;
    }
    return yearSpecific.leapday ? 5 : 4;
  }

  static int getDayOfNawRuz(int year) {
    final yearSpecific = yearSpecifics[year];
    if (yearSpecific == null) {
      return 21;
    }
    return yearSpecific.nawRuzOnMarch21 ? 21 : 20;
  }

  /// the day of the year with Naw Ruz = 1
  int get dayOfYear {
    if (_monthIntern == 20) {
      return 342 + _getNumberAyyamIHaDays(year) + day;
    }
    return (_monthIntern - 1) * 19 + day;
  }

  /// Is the date in the period of fast
  bool get isPeriodOfFast {
    return month == 19;
  }

  /// is the date an Ayyam'i'Ha day
  bool get isAyyamIHa {
    return month == 0;
  }

  /// is the date a feast date
  bool get isFeastDay {
    return day == 1 && !isAyyamIHa;
  }

  bool isBefore(BadiDate other) {
    return year < other.year ||
        year == other.year && dayOfYear < other.dayOfYear;
  }

  bool isOnOrBefore(BadiDate other) {
    return year < other.year ||
        year == other.year && dayOfYear <= other.dayOfYear;
  }

  static DateTime _calculateSunSet(DateTime date,
      {double? longitude, double? latitude, double? altitude}) {
    final fallback = DateTime(date.year, date.month, date.day, 18);
    // return 6pm if no location or if in the poles
    if (latitude == null ||
        longitude == null ||
        latitude > 66.0 ||
        latitude < -66.0 ||
        longitude.abs() > 180.0) {
      return fallback;
    }
    final sunCalcTimes = SunCalc.getTimes(date,
        lat: latitude, lng: longitude, height: altitude ?? 0.0);
    // The sunset of places far west might have the sunset calculated
    // for the day before. In that case we add a day and calculate again.
    if (sunCalcTimes.sunset?.day == date.day - 1) {
      final sunCalcWithAdjustment = SunCalc.getTimes(
          date.add(Duration(days: 1)),
          lat: latitude,
          lng: longitude,
          height: altitude ?? 0.0);
      return sunCalcWithAdjustment.sunset ?? fallback;
    }
    return sunCalcTimes.sunset ?? fallback;
  }

  static DateTime _utcToLocale(DateTime date) {
    if (!date.isUtc) {
      return date;
    }
    final localeDate = DateTime(date.year, date.month, date.day);
    return localeDate
        .add(Duration(hours: date.hour, minutes: date.minute))
        .add(localeDate.timeZoneOffset);
  }

  DateTime get nawRuzDate =>
      DateTime.utc(year + YEAR_ZERO_IN_GREGORIAN, 3, getDayOfNawRuz(year));

  /// Start DateTime
  DateTime get startDateTime {
    final date = nawRuzDate.add(Duration(days: dayOfYear - 1));
    return _utcToLocale(_calculateSunSet(date,
        longitude: longitude, latitude: latitude, altitude: altitude));
  }

  /// End DateTime
  DateTime get endDateTime {
    final date = nawRuzDate.add(Duration(days: dayOfYear));
    return _utcToLocale(_calculateSunSet(date,
        longitude: longitude, latitude: latitude, altitude: altitude));
  }

  static BadiDate _fromYearAndDayOfYear(
      {required int year,
      required int doy,
      double? longitude,
      double? latitude,
      double? altitude}) {
    if (doy < 1 || doy > 366) {
      throw ArgumentError.value(
          doy, 'doy', 'Day of year must be in the range [1-366]');
    }
    final month = (doy / 19).ceil();
    final day = doy - (month - 1) * 19;
    if (month < 19) {
      return BadiDate(
          day: day,
          month: month,
          year: year,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    } else if (month == 19 && day <= _getNumberAyyamIHaDays(year)) {
      return BadiDate(
          day: day,
          month: 0,
          year: year,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    }
    final alaDay = doy - 342 - _getNumberAyyamIHaDays(year);
    return BadiDate(
        day: alaDay,
        month: 19,
        year: year,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  /// BadiDate from a DateTime object
  /// Optional parameter double longitude, latitude, altitude for the sunset time
  static BadiDate fromDate(DateTime gregorianDate,
      {double? longitude, double? latitude, double? altitude}) {
    // we convert to utc to avoid daylight saving issues
    final dateTime = DateTime.utc(
        gregorianDate.year, gregorianDate.month, gregorianDate.day);
    if (dateTime.isAfter(DateTime.utc(LAST_GREGORIAN_YEAR_SUPPORTED, 3, 19))) {
      throw UnsupportedError(
          'Dates after $LAST_GREGORIAN_YEAR_SUPPORTED-03-19 are not supported yet.');
    }
    final isAfterSunset = gregorianDate.isAfter(_calculateSunSet(gregorianDate,
        longitude: longitude, latitude: latitude, altitude: altitude));
    final date = isAfterSunset ? dateTime.add(Duration(days: 1)) : dateTime;
    final badiYear = date.year - YEAR_ZERO_IN_GREGORIAN;
    final isBeforeNawRuz =
        date.isBefore(DateTime.utc(date.year, 3, getDayOfNawRuz(badiYear)));
    if (!isBeforeNawRuz) {
      final doy =
          date.difference(DateTime.utc(date.year, 3, getDayOfNawRuz(badiYear)));
      // +1 because naw ruz has a doy of 1 but a difference of 0
      return _fromYearAndDayOfYear(
          year: badiYear,
          doy: doy.inDays + 1,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    }
    final doy = date.difference(
        DateTime.utc(date.year - 1, 3, getDayOfNawRuz(badiYear - 1)));
    return _fromYearAndDayOfYear(
        year: badiYear - 1,
        doy: doy.inDays + 1,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  @override
  String toString() {
    return 'BadiDate($year/$month/$day @ $longitude,$latitude^$altitude)';
  }

  /// If the BadiDate is a Baha'i Holy day the Holy date else null
  BahaiHolyDayEnum? get holyDay {
    final birthOfBab = yearSpecifics[year]?.birthOfBab;
    return bahaiHolyDays
        .firstWhere(
            (holyDay) =>
                holyDay?.getDayOfTheYear(dayOfYearBirthOfBab: birthOfBab) ==
                dayOfYear,
            orElse: () => null)
        ?.type;
  }

  String? get holyDayNameEn {
    return holyDayNameIn('en');
  }

  BadiDate get nextDay {
    if (month == 19 && day == 19) {
      return BadiDate(
        day: 1,
        month: 1,
        year: year + 1,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude,
      );
    }
    return _fromYearAndDayOfYear(
      year: year,
      doy: dayOfYear + 1,
      longitude: longitude,
      latitude: latitude,
      altitude: altitude,
    );
  }

  String? holyDayNameIn(String languageCode) {
    if (holyDay == null) return null;
    return HOLY_DAYS[languageCode]?[holyDay];
  }

  /// The BadiDate of the next feast
  BadiDate getNextFeast() {
    if (month == 19) {
      return BadiDate(
          day: 1,
          month: 1,
          year: year + 1,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    }
    return BadiDate(
        day: 1,
        month: month + 1,
        year: year,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  /// The BadiDate of the next Holy day
  BadiDate get nextHolyDate {
    final birthOfBab = yearSpecifics[year]?.birthOfBab;
    final doy = bahaiHolyDays
        .firstWhere(
            (holyDay) =>
                (holyDay?.getDayOfTheYear(dayOfYearBirthOfBab: birthOfBab) ??
                    0) >
                dayOfYear,
            orElse: () => null)
        ?.getDayOfTheYear(dayOfYearBirthOfBab: birthOfBab);
    if (doy == null) {
      return _fromYearAndDayOfYear(
          year: year + 1,
          doy: 1,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    }
    return _fromYearAndDayOfYear(
        year: year,
        doy: doy,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  // return the last Ayyam'i'Ha day of that Badi year
  BadiDate get lastAyyamIHaDayOfYear {
    final firstAla = BadiDate(
        day: 1,
        year: year,
        month: 19,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
    return BadiDate._fromYearAndDayOfYear(
        year: year,
        doy: firstAla.dayOfYear - 1,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  // equality
  @override
  bool operator ==(other) =>
      other is BadiDate && other.year == year && other.dayOfYear == dayOfYear;

  // hash code
  @override
  int get hashCode => year * 1000 + dayOfYear;
}
