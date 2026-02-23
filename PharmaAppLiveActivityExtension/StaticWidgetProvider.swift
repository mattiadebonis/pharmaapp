import WidgetKit

struct SimpleWidgetEntry: TimelineEntry {
    let date: Date
}

struct StaticWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleWidgetEntry {
        SimpleWidgetEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleWidgetEntry) -> Void) {
        completion(SimpleWidgetEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleWidgetEntry>) -> Void) {
        completion(Timeline(entries: [SimpleWidgetEntry(date: .now)], policy: .never))
    }
}
