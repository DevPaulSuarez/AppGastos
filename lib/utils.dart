int daysInMonth(int month, int year) {
  var lastDayDateTime = (month < 12)
      ? DateTime(year, month + 1, 0)
      : DateTime(year + 1, 1, 0);

  return lastDayDateTime.day;
}

const monthNames = [
  "ENERO",
  "FEBRERO",
  "MARZO",
  "ABRIL",
  "MAYO",
  "JUNIO",
  "JULIO",
  "AGOSTO",
  "SEPTIEMBRE",
  "OCTUBRE",
  "NOVIEMBRE",
  "DICIEMBRE",
];

/// Años hacia atrás que se pueden recorrer mes a mes en la app; los
/// anteriores se ven con el informe anual.
const yearsToBrowse = 4;

/// Convierte un monto escrito por el usuario ("12,50" o "12.50").
double? parseAmount(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// Nombre de la persona, o "Sin asignar" si el índice no es válido.
String personName(List<String> people, int? index) =>
    index != null && index >= 0 && index < people.length
    ? people[index]
    : 'Sin asignar';

/// Próxima vez que toca [weekday] (1 = lunes) a las [hour] en punto, desde
/// [now] (incluido hoy si todavía no pasó esa hora).
DateTime nextWeekdayAt(DateTime now, int weekday, int hour) {
  var date = DateTime(now.year, now.month, now.day, hour);
  while (date.weekday != weekday || !date.isAfter(now)) {
    date = DateTime(date.year, date.month, date.day + 1, hour);
  }
  return date;
}
