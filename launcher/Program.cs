using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class Program
{
    private const string PayloadResource = "WinSweepPayload.zip";

    [STAThread]
    private static int Main()
    {
        try
        {
            var engineRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WinSweep",
                "Engine");

            Directory.CreateDirectory(engineRoot);
            ExtractPayload(engineRoot);

            var powerShell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32",
                "WindowsPowerShell",
                "v1.0",
                "powershell.exe");
            var uiScript = Path.Combine(engineRoot, "winsweep-ui.ps1");
            if (!File.Exists(powerShell) || !File.Exists(uiScript))
            {
                throw new FileNotFoundException("WinSweep engine files were not found.", uiScript);
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = powerShell,
                Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " + QuoteArgument(uiScript),
                WorkingDirectory = engineRoot,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            startInfo.EnvironmentVariables["WINSWEEP_LAUNCHED_FROM_EXE"] = "1";

            using (var process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("PowerShell could not be started.");
                }

                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.Message,
                "WinSweep",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    private static void ExtractPayload(string engineRoot)
    {
        using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResource))
        {
            if (stream == null)
            {
                throw new InvalidOperationException("WinSweep payload is missing from the executable.");
            }

            using (var archive = new ZipArchive(stream, ZipArchiveMode.Read, false))
            {
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

                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    if (string.Equals(entry.Name, "winsweep-config.json", StringComparison.OrdinalIgnoreCase)
                        && File.Exists(destination))
                    {
                        continue;
                    }

                    entry.ExtractToFile(destination, true);
                }
            }
        }
    }

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}
