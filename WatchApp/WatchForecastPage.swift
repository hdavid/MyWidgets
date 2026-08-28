import SwiftUI

/// One windguru spot as a scrolling table of the upcoming daylight hours:
/// hour, direction, wind, gust, temperature — the columns of the forecast
/// widget turned into rows, which is the shape a watch screen has.
struct WatchForecastPage: View {
    var spot: WindguruSpot

    @State private var forecast: WindguruForecast?
    @State private var stale = false
    @State private var loading = false

    var body: some View {
        Group {
            if let forecast {
                let points = forecast.upcoming(hours: 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(spot.heading)
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if stale {
                                Text("offline")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Pal.red)
                            }
                        }
                        if points.isEmpty {
                            Text("No upcoming daylight hours")
                                .font(.system(size: 12))
                                .foregroundStyle(Pal.gray)
                        }
                        ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                            ForecastRow(p: p)
                        }
                        Text(forecast.model)
                            .font(.system(size: 9))
                            .foregroundStyle(Pal.gray)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                NoDataView(message: loading ? "Loading…" : "No forecast yet")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await load() } }
        .task(id: spot) { await load() }
        .refreshWhenStale(ttl: Freshness.forecast, since: forecast?.fetchedAt) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if forecast == nil, let cached = ForecastStore.load(for: spot.id) {
            forecast = cached
            stale = true
        }
        if let fresh = await Windguru.fetch(spot) {
            ForecastStore.save(fresh, for: spot.id)
            forecast = fresh
            stale = false
        } else if forecast != nil {
            stale = true
        }
    }
}

private struct ForecastRow: View {
    var p: ForecastPoint

    var body: some View {
        HStack(spacing: 6) {
            Text(forecastHourLabel(p.time))
                .font(.system(size: 12))
                .foregroundStyle(Pal.gray)
                .frame(width: 46, alignment: .leading)
            // Same convention as the wind rose: the arrow points INTO the
            // wind — toward where it comes from.
            Image(systemName: "location.north.fill")
                .font(.system(size: 9))
                .foregroundStyle(Pal.art)
                .rotationEffect(.degrees(p.dir))
            Text(fmt0(p.wind))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(windColor(p.wind))
            Text(fmt0(p.gust))
                .font(.system(size: 12))
                .foregroundStyle(windColor(p.gust))
            Spacer(minLength: 2)
            if let t = p.temp {
                Text(fmt0(t) + "°")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(temperatureColor(t))
            }
        }
        .lineLimit(1)
    }
}
