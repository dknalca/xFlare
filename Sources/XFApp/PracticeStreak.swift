// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// La racha diaria (`docs/CURRICULUM.md` §7): días **consecutivos** con práctica,
/// contando hacia atrás desde hoy. Puro: se le pasan las fechas de práctica.
///
/// "Día" en el calendario del usuario (`Calendar.current`). Si hoy aún no se ha
/// practicado pero ayer sí, la racha sigue viva (todavía puede practicar hoy);
/// si el último día con práctica es anteayer o antes, la racha es 0.
public enum PracticeStreak {

    public static func currentStreak(practiceDates: [Date],
                                     today: Date = Date(),
                                     calendar: Calendar = .current) -> Int {
        let practiced = Set(practiceDates.map { calendar.startOfDay(for: $0) })
        guard !practiced.isEmpty else { return 0 }

        let startToday = calendar.startOfDay(for: today)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: startToday) else { return 0 }

        // La racha ancla en hoy si hoy tiene práctica; si no, en ayer.
        var cursor: Date
        if practiced.contains(startToday) {
            cursor = startToday
        } else if practiced.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var count = 0
        while practiced.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }
}
