import QtQuick

// One weather widget's data: its own place and unit (Edit "Weather"…), else the shared
// WeatherData. `src` has WeatherData's fields (city, loaded, temp, hourly, daily…);
// show temperatures through t(), which converts to the widget's unit.
QtObject {
    id: root

    property string location: ""
    property string unit: "auto" // auto (Config.tempUnit) | C | F

    readonly property bool custom: location.trim() !== ""
    property var own: ({ loaded: false, failed: false })
    readonly property var src: custom ? own : WeatherData
    readonly property string srcUnit: custom ? "C" : Config.tempUnit // own fetches are in °C
    readonly property string shownUnit: unit === "auto" ? Config.tempUnit : unit

    function convert(v: real): real {
        return srcUnit === shownUnit ? v : shownUnit === "F" ? v * 9 / 5 + 32 : (v - 32) * 5 / 9;
    }

    function t(v: real): string {
        return Math.round(convert(v)) + "°";
    }

    function refresh(): void {
        const loc = location.trim(), parts = loc.split(","), asked = loc;
        const got = o => { if (root.location.trim() === asked) root.own = o; }; // ignore answers for an older location
        // a failed refresh keeps the last forecast (as WeatherData does); retry in a minute
        const fail = () => { if (!root.own.loaded) got({ loaded: false, failed: true }); retry.restart(); };
        const forecast = (lat, lon, place) => WeatherData.get(`https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&timezone=auto&forecast_days=6`
            + "&current=temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"
            + "&hourly=temperature_2m,weather_code,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max", d => {
            if (!d?.current || !d.hourly?.time || !d.daily?.time)
                return fail();
            const nowKey = d.current.time.slice(0, 13);
            const start = Math.max(0, d.hourly.time.findIndex(x => x.slice(0, 13) === nowKey));
            const hourly = [], daily = [];
            for (let i = start; i < Math.min(start + 6, d.hourly.time.length); i++)
                hourly.push({ hour: i === start ? "Now" : d.hourly.time[i].slice(11, 13), temp: d.hourly.temperature_2m[i],
                              code: d.hourly.weather_code[i], isDay: d.hourly.is_day[i] === 1 });
            for (let i = 0; i < d.daily.time.length; i++)
                daily.push({ day: i === 0 ? "Today" : Qt.locale().dayName(new Date(d.daily.time[i] + "T12:00:00").getDay(), Locale.ShortFormat),
                             high: d.daily.temperature_2m_max[i], low: d.daily.temperature_2m_min[i], code: d.daily.weather_code[i] });
            const code = d.current.weather_code, isDay = d.current.is_day === 1;
            got({ loaded: true, failed: false, city: place, temp: d.current.temperature_2m, feelsLike: d.current.apparent_temperature,
                  code, isDay, condition: WeatherData.describe(code), icon: WeatherData.iconFor(code, isDay),
                  high: d.daily.temperature_2m_max[0], low: d.daily.temperature_2m_min[0],
                  humidity: d.current.relative_humidity_2m ?? 0, wind: d.current.wind_speed_10m ?? 0, uv: d.daily.uv_index_max?.[0] ?? 0,
                  sunrise: (d.daily.sunrise?.[0] ?? "").slice(11, 16), sunset: (d.daily.sunset?.[0] ?? "").slice(11, 16),
                  hourly, daily });
        });
        if (parts.length === 2 && !isNaN(parseFloat(parts[0])) && !isNaN(parseFloat(parts[1])))
            forecast(parseFloat(parts[0]), parseFloat(parts[1]), loc);
        else
            WeatherData.get(`https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(loc)}`, d => {
                const r = d?.results?.[0];
                r ? forecast(r.latitude, r.longitude, r.name) : fail();
            });
    }

    onLocationChanged: {
        own = { loaded: false, failed: false };
        if (location.trim() !== "") // not `custom`: that binding may not have updated yet
            debounce.restart();
    }
    Component.onCompleted: if (custom) refresh()

    property list<QtObject> timers: [
        Timer {
            id: debounce

            interval: 300
            onTriggered: if (root.custom) root.refresh()
        },
        Timer {
            running: root.custom
            interval: 20 * 60 * 1000
            repeat: true
            onTriggered: root.refresh()
        },
        Timer {
            id: retry

            interval: 60 * 1000
            onTriggered: if (root.custom) root.refresh()
        }
    ]
}
