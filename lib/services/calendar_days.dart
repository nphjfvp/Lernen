/// Ganze Kalendertage von [from] bis [to] (negativ, wenn [to] davor liegt).
/// Über UTC-Daten gerechnet: `difference().inDays` zwischen zwei Mitternachten
/// ergäbe über die Umstellung auf Sommerzeit (23-Stunden-Tag) einen Tag zu
/// wenig.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
