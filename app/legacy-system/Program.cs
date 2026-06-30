using LegacySystem;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

// ── Locate config files next to the executable (not the temp extraction dir) ──
// For single-file self-contained publishes, AppContext.BaseDirectory is a temp
// extraction folder.  Environment.ProcessPath gives the real C:\legacy-system\ path.
var exeDir = Path.GetDirectoryName(Environment.ProcessPath)
    ?? AppContext.BaseDirectory;

// ── Build and run the host ─────────────────────────────────────────────────────
IHost host = Host.CreateDefaultBuilder(args)
    .UseWindowsService(options => options.ServiceName = "LegacySystem")
    .ConfigureHostConfiguration(config =>
    {
        // Load appsettings.json from the exe directory (written by install.ps1)
        config.SetBasePath(exeDir);
    })
    .ConfigureAppConfiguration((ctx, config) =>
    {
        config.SetBasePath(exeDir);
    })
    .ConfigureServices((ctx, services) =>
    {
        // Bind appsettings.json to AppSettings
        var settings = new AppSettings();
        ctx.Configuration.Bind(settings);
        services.AddSingleton(settings);

        // Load scenario.json from exe directory (external so facilitators can tune it)
        var scenarioPath = Path.Combine(exeDir, "scenario.json");
        var scenario     = ChaosEngine.LoadFromFile(scenarioPath);
        services.AddSingleton(new ChaosEngine(scenario));

        // Named HttpClient with the x-team-key header pre-configured
        services.AddHttpClient("ingestion", (sp, client) =>
        {
            var s = sp.GetRequiredService<AppSettings>();
            if (!string.IsNullOrEmpty(s.IngestionKey))
                client.DefaultRequestHeaders.TryAddWithoutValidation("x-team-key", s.IngestionKey);
        });

        services.AddHostedService<Worker>();
    })
    .Build();

await host.RunAsync();
