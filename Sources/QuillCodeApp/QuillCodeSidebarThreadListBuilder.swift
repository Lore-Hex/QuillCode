import Foundation

struct SidebarThreadListBuilder {
    var items: [SidebarItemSurface]

    func filteredItems(matching query: String) -> [SidebarItemSurface] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return items
        }
        return items.filter { item in
            let pinLabel = item.isPinned ? "pinned" : ""
            let archivedLabel = item.isArchived ? "archived" : ""
            return item.title.localizedCaseInsensitiveContains(normalizedQuery)
                || item.subtitle.localizedCaseInsensitiveContains(normalizedQuery)
                || item.searchText.localizedCaseInsensitiveContains(normalizedQuery)
                || pinLabel.localizedCaseInsensitiveContains(normalizedQuery)
                || archivedLabel.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    var pinnedItems: [SidebarItemSurface] {
        items.filter { $0.isPinned && !$0.isArchived }
    }

    var recentItems: [SidebarItemSurface] {
        items.filter { !$0.isPinned && !$0.isArchived }
    }

    func recentSections(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SidebarThreadSectionSurface] {
        let recent = recentItems
        guard !recent.isEmpty else { return [] }

        let grouped = Dictionary(grouping: recent) { item in
            SidebarThreadDateBucket.bucket(
                for: item.updatedAt,
                now: now,
                calendar: calendar
            )
        }

        return SidebarThreadDateBucket.allCases.compactMap { bucket in
            guard let items = grouped[bucket], !items.isEmpty else { return nil }
            return SidebarThreadSectionSurface(
                title: bucket.title,
                items: items.sorted { $0.updatedAt > $1.updatedAt }
            )
        }
    }

    var archivedItems: [SidebarItemSurface] {
        items.filter(\.isArchived)
    }
}

private enum SidebarThreadDateBucket: Int, CaseIterable {
    case today
    case yesterday
    case previousSevenDays
    case older

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .previousSevenDays:
            return "Previous 7 days"
        case .older:
            return "Older"
        }
    }

    static func bucket(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> SidebarThreadDateBucket {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfPreviousSevenDays = calendar.date(byAdding: .day, value: -8, to: startOfToday) ?? startOfYesterday

        if date >= startOfToday {
            return .today
        }
        if date >= startOfYesterday {
            return .yesterday
        }
        if date >= startOfPreviousSevenDays {
            return .previousSevenDays
        }
        return .older
    }
}
