using System.Text.Json;
using System.Text.Json.Serialization;

namespace LegacySystem;

// ── Scenario config model ──────────────────────────────────────────────────────

/// <summary>Root of scenario.json — the chaos timeline for the hackathon scenario.</summary>
public class ScenarioConfig
{
    /// <summary>IncidentId stamped on telemetry anomalies and the tickets they cause.</summary>
    public string IncidentId { get; set; } = "INC-BADDEPLOYMENT-01";

    public List<ChaosEvent> Events { get; set; } = [];
}

public class ChaosEvent
{
    /// <summary>Minutes after app start when this event begins.</summary>
    public int OffsetMinutes { get; set; }

    public int DurationMinutes { get; set; } = 10;

    /// <summary>LatencySpike or BlindSpot.</summary>
    public string Type { get; set; } = "LatencySpike";

    /// <summary>Service affected by this event (used for telemetry anomaly).</summary>
    public string Service { get; set; } = "OrderService";

    public string Operation { get; set; } = "ProcessOrder";

    /// <summary>Multiplier applied to normal latency during this event. 1.0 = no change.</summary>
    public double LatencyMultiplier { get; set; } = 1.0;

    /// <summary>Multiplier applied to normal error count during this event.</summary>
    public double ErrorRateMultiplier { get; set; } = 1.0;

    /// <summary>Whether this event also generates support tickets.</summary>
    public bool GenerateTickets { get; set; }

    /// <summary>
    /// Minutes after the event starts before tickets begin (simulates users
    /// noticing the problem — matches the "early-warning blind spot" pattern).
    /// </summary>
    public int TicketDelayMinutes { get; set; } = 3;

    /// <summary>Human-readable description of what this event simulates.</summary>
    public string Description { get; set; } = "";
}

// ── Active incident ────────────────────────────────────────────────────────────

/// <summary>The currently active chaos event, if any.</summary>
public record ActiveIncident(string IncidentId, ChaosEvent Event, bool TicketsStarted);

// ── Chaos engine ───────────────────────────────────────────────────────────────

/// <summary>
/// Reads scenario.json and returns the currently active incident based on
/// elapsed time since the app started.  Stateless — safe to call from any thread.
/// </summary>
public sealed class ChaosEngine
{
    private readonly ScenarioConfig _scenario;
    private readonly DateTime _startedAt = DateTime.UtcNow;

    public ChaosEngine(ScenarioConfig scenario) => _scenario = scenario;

    public ActiveIncident? GetActiveIncident()
    {
        var elapsedMinutes = (DateTime.UtcNow - _startedAt).TotalMinutes;

        foreach (var ev in _scenario.Events)
        {
            if (elapsedMinutes >= ev.OffsetMinutes &&
                elapsedMinutes <  ev.OffsetMinutes + ev.DurationMinutes)
            {
                var minutesIntoEvent = elapsedMinutes - ev.OffsetMinutes;
                return new ActiveIncident(
                    _scenario.IncidentId,
                    ev,
                    minutesIntoEvent >= ev.TicketDelayMinutes
                );
            }
        }

        return null;
    }

    public static ScenarioConfig LoadFromFile(string path)
    {
        if (!File.Exists(path))
            return new ScenarioConfig();

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<ScenarioConfig>(json,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                ?? new ScenarioConfig();
        }
        catch
        {
            return new ScenarioConfig();
        }
    }
}
