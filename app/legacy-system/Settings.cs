namespace LegacySystem;

/// <summary>
/// Runtime settings injected by the VM Custom Script Extension via appsettings.json.
/// Defaults allow the app to start cleanly in dev mode without crashing.
/// </summary>
public class AppSettings
{
    /// <summary>Participant slot, e.g. "user01". Stamped on every emitted event.</summary>
    public string SlotId { get; set; } = "userXX";

    /// <summary>Base URL of the shared Ingestion API, e.g. https://workshop-ingest-XXXX.azurewebsites.net</summary>
    public string IngestionEndpoint { get; set; } = "";

    /// <summary>Per-slot secret key sent as x-team-key header. Written by install.ps1 from protectedSettings.</summary>
    public string IngestionKey { get; set; } = "";

    /// <summary>Azure region label stamped on telemetry events.</summary>
    public string Region { get; set; } = "eastus2";
}
