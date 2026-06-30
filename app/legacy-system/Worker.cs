using System.Net.Http.Json;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace LegacySystem;

/// <summary>
/// Background service that continuously emits telemetry and support tickets
/// to the shared Ingestion API.  Applies chaos events from scenario.json on a
/// shared timeline so all 30 participant VMs see the same incident at the same
/// wall-clock offset after startup.
/// </summary>
public sealed class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly IHttpClientFactory _http;
    private readonly AppSettings _settings;
    private readonly ChaosEngine _chaos;
    private readonly Random _rng = new();

    // ── Services and operations the "legacy system" exposes ──────────────────
    private static readonly (string Service, string Operation)[] Endpoints =
    [
        ("OrderService",    "ProcessOrder"),
        ("PaymentService",  "ValidateCard"),
        ("InventoryService","CheckStock"),
        ("UserService",     "GetProfile"),
    ];

    // ── Simulated customer tenants ────────────────────────────────────────────
    private static readonly string[] Tenants =
        ["Contoso Ltd", "Fabrikam Inc", "Northwind Traders", "Adventure Works", "Tailspin Toys"];

    // ── Incident-driven ticket messages ───────────────────────────────────────
    private static readonly string[] SlowMessages =
    [
        "The system is really slow today, orders are taking forever",
        "Getting timeout errors when trying to process orders",
        "Unable to complete purchase — page keeps timing out",
        "Orders are not going through, nothing is working",
        "Very slow response times — something is clearly wrong",
        "Can't complete my order, it just keeps spinning",
        "System has been slow for the past few minutes, urgent",
        "Customers are complaining about slow checkouts",
        "Seeing lots of errors when customers try to check out",
        "Portal unresponsive — please investigate immediately",
    ];

    // ── Background noise tickets (no telemetry anomaly — creates blind spots) ──
    private static readonly string[] NoiseMessages =
    [
        "Minor display issue on the portal, nothing urgent",
        "Small UI glitch noticed, not blocking anything",
        "One user reported a login delay earlier, seems fine now",
    ];

    public Worker(
        ILogger<Worker> logger,
        IHttpClientFactory http,
        AppSettings settings,
        ChaosEngine chaos)
    {
        _logger   = logger;
        _http     = http;
        _settings = settings;
        _chaos    = chaos;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        _logger.LogInformation(
            "Legacy system started. slot={Slot} endpoint={Endpoint}",
            _settings.SlotId, string.IsNullOrEmpty(_settings.IngestionEndpoint) ? "(not configured)" : _settings.IngestionEndpoint);

        if (string.IsNullOrEmpty(_settings.IngestionEndpoint))
            _logger.LogWarning("IngestionEndpoint is empty — signals will not be sent. Set in appsettings.json.");

        const int TelemetryIntervalSec = 10;
        const int MinTicketIntervalSec = 25;
        DateTime lastTicketAt = DateTime.MinValue;

        while (!ct.IsCancellationRequested)
        {
            var incident = _chaos.GetActiveIncident();

            // Emit one telemetry sample per service endpoint
            foreach (var (service, operation) in Endpoints)
                await EmitTelemetryAsync(service, operation, incident, ct);

            // Emit a support ticket during an active incident (after its ticket-delay)
            if (incident is { TicketsStarted: true })
            {
                var secondsSinceLast = (DateTime.UtcNow - lastTicketAt).TotalSeconds;
                // Randomise interval between tickets to avoid a perfectly regular burst
                if (secondsSinceLast >= MinTicketIntervalSec && _rng.NextDouble() < 0.7)
                {
                    await EmitTicketAsync(incident, ct);
                    lastTicketAt = DateTime.UtcNow;
                }
            }

            // Occasionally emit a "noise" ticket with no telemetry anomaly — creates a
            // blind-spot pattern that the Part 3 agent must distinguish from real incidents.
            if (incident is null && _rng.NextDouble() < 0.008) // ~1 per ~20 min
                await EmitNoiseTicketAsync(ct);

            await Task.Delay(TimeSpan.FromSeconds(TelemetryIntervalSec), ct);
        }
    }

    // ── Telemetry emitter ──────────────────────────────────────────────────────

    private async Task EmitTelemetryAsync(
        string service, string operation, ActiveIncident? incident, CancellationToken ct)
    {
        // Normal baseline: 80–150 ms latency, 0–2 errors, 100–200 rpm throughput
        var latencyMs  = 80  + _rng.Next(70);
        var errorCount = _rng.Next(3);
        var throughput = 100 + _rng.Next(100);
        var isAnomaly  = false;
        var incidentId = "";

        // Apply chaos multipliers to the affected service
        if (incident is not null && service == incident.Event.Service &&
            incident.Event.Type == "LatencySpike")
        {
            latencyMs  = (int)(latencyMs  * incident.Event.LatencyMultiplier);
            errorCount = (int)(errorCount * incident.Event.ErrorRateMultiplier) + _rng.Next(4);
            throughput = (int)(throughput * 0.65);
            isAnomaly  = true;
            incidentId = incident.IncidentId;
        }

        await PostAsync("/api/ingest/telemetry", new
        {
            service,
            operation,
            region        = _settings.Region,
            latencyMs,
            errorCount,
            throughput,
            isAnomaly,
            incidentId,
            correlationId = Guid.NewGuid().ToString("N")[..12],
        }, ct);
    }

    // ── Ticket emitters ────────────────────────────────────────────────────────

    private async Task EmitTicketAsync(ActiveIncident incident, CancellationToken ct)
    {
        await PostAsync("/api/ingest/support", new
        {
            ticketId       = "TKT-" + Guid.NewGuid().ToString("N")[..10],
            customerTenant = Tenants[_rng.Next(Tenants.Length)],
            description    = SlowMessages[_rng.Next(SlowMessages.Length)],
            category       = "Performance",
            incidentId     = incident.IncidentId,
            isNoise        = false,
        }, ct);
    }

    private async Task EmitNoiseTicketAsync(CancellationToken ct)
    {
        await PostAsync("/api/ingest/support", new
        {
            ticketId       = "TKT-" + Guid.NewGuid().ToString("N")[..10],
            customerTenant = Tenants[_rng.Next(Tenants.Length)],
            description    = NoiseMessages[_rng.Next(NoiseMessages.Length)],
            category       = "UX",
            incidentId     = "",
            isNoise        = true,
        }, ct);
    }

    // ── HTTP helper ────────────────────────────────────────────────────────────

    private async Task PostAsync(string path, object payload, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(_settings.IngestionEndpoint)) return;

        try
        {
            var client = _http.CreateClient("ingestion");
            var url    = _settings.IngestionEndpoint.TrimEnd('/') + path;
            var resp   = await client.PostAsJsonAsync(url, payload, ct);

            if (!resp.IsSuccessStatusCode)
                _logger.LogWarning("Ingest {Path} returned {Status}", path, (int)resp.StatusCode);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning("POST {Path} failed: {Message}", path, ex.Message);
        }
    }
}
