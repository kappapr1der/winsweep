using System;
using System.IO.Compression;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows;

namespace WinSweepLauncher;

internal static class Program
{
    private const string PayloadResource = "WinSweepPayload.zip";

    [STAThread]
    private static int Main()
    {
        try
        {
            var engineRoot = GetEngineRoot();
            Directory.CreateDirectory(engineRoot);
            ExtractPayload(engineRoot);

            var commandLine = Environment.GetCommandLineArgs();
            if (commandLine.Any(argument =>
                    string.Equals(argument, "--test", StringComparison.OrdinalIgnoreCase)))
            {
                return MainWindow.RunSmokeTest(engineRoot) ? 0 : 1;
            }
            if (commandLine.Any(argument =>
                    string.Equals(argument, "--render-test", StringComparison.OrdinalIgnoreCase)))
            {
                return MainWindow.RunRenderSmokeTest(engineRoot) ? 0 : 1;
            }

            var app = new Application
            {
                ShutdownMode = ShutdownMode.OnMainWindowClose
            };
            app.DispatcherUnhandledException += (_, eventArgs) =>
            {
                MessageBox.Show(
                    eventArgs.Exception.Message,
                    "WinSweep",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                eventArgs.Handled = true;
            };

            app.Run(new MainWindow(engineRoot));
            return 0;
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "WinSweep",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            return 1;
        }
    }

    private static string GetEngineRoot()
    {
#if PORTABLE
        return Path.Combine(AppContext.BaseDirectory, "WinSweepData");
#else
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WinSweep",
            "Engine");
#endif
    }

    private static void ExtractPayload(string engineRoot)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResource)
            ?? throw new InvalidOperationException("WinSweep payload is missing from the executable.");
        using var archive = new ZipArchive(stream, ZipArchiveMode.Read, false);

        var root = Path.GetFullPath(engineRoot) + Path.DirectorySeparatorChar;
        foreach (var entry in archive.Entries)
        {
            var relativePath = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
            var destination = Path.GetFullPath(Path.Combine(engineRoot, relativePath));
            if (!destination.StartsWith(root, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("WinSweep payload contains an unsafe path.");
            }

            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(destination);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            if (string.Equals(entry.Name, "winsweep-config.json", StringComparison.OrdinalIgnoreCase)
                && File.Exists(destination))
            {
                continue;
            }

            entry.ExtractToFile(destination, true);
        }
    }
}
