// Установщик и деинсталлятор ShootIn для Windows. Один исходник собирается дважды:
//   Setup.exe     — графический установщик с игрой внутри (ресурс payload.zip);
//   Uninstall.exe — маленький деинсталлятор (/define:UNINSTALLER), его Setup.exe кладёт в папку игры.
//
// Только C# 5 (встроенный в Windows csc.exe), без внешних зависимостей. Права администратора не нужны:
// игра ставится в профиль пользователя (%LOCALAPPDATA%\Programs\ShootIn).
//
// Ключи Setup.exe:   /S тихая установка   /D=папка   /NODESKTOP   /NOSTARTMENU   /NOLAUNCH   /LOG=файл
// Ключи Uninstall.exe: /S без вопросов   /REMOVEDATA удалить и сохранения с модами игрока   /LOG=файл
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

static class Info
{
    public const string Name = "ShootIn";
    public const string Publisher = "ShootIn";
    public const string ExeName = "ShootIn.exe";
    public const string UninstallName = "Uninstall.exe";
    public const string RegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ShootIn";
    public const string Tagline = "2D экшен-платформер: 34 уровня, 8 боссов и моды";

    public static string DefaultDir
    {
        get
        {
            // Повторная установка — туда же, куда ставили раньше.
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RegistryKey))
            {
                if (key != null)
                {
                    string old = key.GetValue("InstallLocation") as string;
                    if (!string.IsNullOrEmpty(old)) return old;
                }
            }
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\ShootIn");
        }
    }

    // Здесь игра хранит сохранения и установленные из игры моды (user:// в Godot).
    public static string UserDataDir
    {
        get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), @"Godot\app_userdata\ShootIn"); }
    }

    public static string StartMenuDir
    {
        get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "ShootIn"); }
    }

    public static string DesktopLink
    {
        get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "ShootIn.lnk"); }
    }
}

static class Log
{
    public static string Path;

    public static void Write(string text)
    {
        if (string.IsNullOrEmpty(Path)) return;
        try { File.AppendAllText(Path, DateTime.Now.ToString("HH:mm:ss") + "  " + text + Environment.NewLine, Encoding.UTF8); }
        catch (Exception) { }
    }
}

static class Args
{
    public static bool Has(string[] args, string flag)
    {
        foreach (string a in args)
            if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    public static string Value(string[] args, string prefix)
    {
        foreach (string a in args)
        {
            if (a.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                return a.Substring(prefix.Length).Trim('"');
        }
        return null;
    }
}

static class Shell
{
    public static void CreateShortcut(string lnkPath, string target, string arguments, string workDir, string description, string icon)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lnkPath));
        Type shellType = Type.GetTypeFromProgID("WScript.Shell");
        if (shellType == null) throw new InvalidOperationException("WScript.Shell недоступен");
        object shell = Activator.CreateInstance(shellType);
        object link = null;
        try
        {
            link = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnkPath });
            Type linkType = link.GetType();
            Set(linkType, link, "TargetPath", target);
            Set(linkType, link, "Arguments", arguments);
            Set(linkType, link, "WorkingDirectory", workDir);
            Set(linkType, link, "Description", description);
            Set(linkType, link, "IconLocation", icon + ",0");
            linkType.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
        }
        finally
        {
            if (link != null) Marshal.FinalReleaseComObject(link);
            Marshal.FinalReleaseComObject(shell);
        }
    }

    static void Set(Type type, object obj, string property, string value)
    {
        type.InvokeMember(property, BindingFlags.SetProperty, null, obj, new object[] { value });
    }

    public static void DeleteQuiet(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) { Log.Write("не удалось удалить " + path + ": " + ex.Message); }
    }

    public static void DeleteDirIfEmpty(string dir)
    {
        try
        {
            if (Directory.Exists(dir) && Directory.GetFileSystemEntries(dir).Length == 0) Directory.Delete(dir);
        }
        catch (Exception ex) { Log.Write("не удалось удалить папку " + dir + ": " + ex.Message); }
    }

    // Игра, запущенная из этой папки: перед заменой или удалением файла её нужно закрыть.
    public static List<Process> RunningGame(string installDir)
    {
        var found = new List<Process>();
        string expected = Path.GetFullPath(Path.Combine(installDir, Info.ExeName));
        foreach (Process p in Process.GetProcessesByName("ShootIn"))
        {
            try
            {
                if (string.Equals(Path.GetFullPath(p.MainModule.FileName), expected, StringComparison.OrdinalIgnoreCase)) found.Add(p);
            }
            catch (Exception) { }
        }
        return found;
    }

    public static void CloseGame(List<Process> processes)
    {
        foreach (Process p in processes)
        {
            try
            {
                p.CloseMainWindow();
                if (!p.WaitForExit(2500)) p.Kill();
                p.WaitForExit(3000);
            }
            catch (Exception ex) { Log.Write("не удалось закрыть игру: " + ex.Message); }
        }
    }
}

#if UNINSTALLER

static class Uninstaller
{
    [STAThread]
    static int Main(string[] args)
    {
        Log.Path = Args.Value(args, "/LOG=");
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        bool silent = Args.Has(args, "/S");
        bool removeData = Args.Has(args, "/REMOVEDATA");
        string runFrom = Args.Value(args, "/_run=");
        try
        {
            if (runFrom == null)
            {
                // Первый запуск: из папки игры файл удалить нельзя (он занят) — перезапускаемся из временной копии.
                string installDir = Path.GetDirectoryName(Application.ExecutablePath);
                if (!silent)
                {
                    if (MessageBox.Show("Удалить ShootIn с этого компьютера?", "Удаление ShootIn", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return 0;
                    removeData = MessageBox.Show(
                        "Удалить также сохранения игры и установленные из игры моды?\n\n" + Info.UserDataDir + "\n\nЕсли нажать «Нет», сохранения останутся, и после новой установки вы продолжите с того же места.",
                        "Удаление ShootIn", MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.Yes;
                }
                string temp = Path.Combine(Path.GetTempPath(), "ShootIn-uninstall-" + Guid.NewGuid().ToString("N") + ".exe");
                File.Copy(Application.ExecutablePath, temp, true);
                var start = new ProcessStartInfo(temp);
                start.Arguments = "/_run=\"" + installDir + "\"" + (silent ? " /S" : "") + (removeData ? " /REMOVEDATA" : "") + (Log.Path != null ? " /LOG=\"" + Log.Path + "\"" : "");
                start.UseShellExecute = false;
                Process.Start(start);
                return 0;
            }
            return Remove(runFrom, silent, removeData);
        }
        catch (Exception ex)
        {
            Log.Write("ошибка: " + ex);
            if (!silent) MessageBox.Show("Не удалось удалить ShootIn:\n" + ex.Message, "Удаление ShootIn", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static int Remove(string dir, bool silent, bool removeData)
    {
        dir = Path.GetFullPath(dir);
        Log.Write("удаление из " + dir + (removeData ? " вместе с данными игрока" : ""));
        List<Process> running = Shell.RunningGame(dir);
        if (running.Count > 0)
        {
            if (!silent && MessageBox.Show("ShootIn сейчас запущена. Закрыть игру и продолжить удаление?", "Удаление ShootIn", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return 1;
            Shell.CloseGame(running);
        }

        Shell.DeleteQuiet(Info.DesktopLink);
        string menu = Info.StartMenuDir;
        if (Directory.Exists(menu))
        {
            foreach (string file in Directory.GetFiles(menu, "*.lnk")) Shell.DeleteQuiet(file);
            Shell.DeleteDirIfEmpty(menu);
        }
        try { Registry.CurrentUser.DeleteSubKeyTree(Info.RegistryKey, false); }
        catch (Exception ex) { Log.Write("реестр: " + ex.Message); }

        string mods = Path.Combine(dir, "mods");
        Shell.DeleteQuiet(Path.Combine(mods, "Как установить моды.txt"));
        Shell.DeleteQuiet(Path.Combine(dir, Info.ExeName));
        // Первый экземпляр деинсталлятора ещё может быть закрыт не до конца — пробуем несколько раз.
        string first = Path.Combine(dir, Info.UninstallName);
        for (int i = 0; i < 40 && File.Exists(first); i++)
        {
            try { File.Delete(first); }
            catch (Exception) { Thread.Sleep(250); }
        }
        string kept = null;
        if (removeData)
        {
            TryDeleteTree(mods);
            TryDeleteTree(Info.UserDataDir);
        }
        else
        {
            if (Directory.Exists(mods) && Directory.GetFileSystemEntries(mods).Length > 0) kept = mods;
            Shell.DeleteDirIfEmpty(mods);
        }
        Shell.DeleteDirIfEmpty(dir);

        // Временную копию деинсталлятора удаляет отдельный процесс после нашего выхода.
        var cleanup = new ProcessStartInfo("cmd.exe", "/c ping 127.0.0.1 -n 3 >nul & del /f /q \"" + Application.ExecutablePath + "\"");
        cleanup.CreateNoWindow = true;
        cleanup.UseShellExecute = false;
        Process.Start(cleanup);

        Log.Write("удаление завершено");
        if (!silent)
        {
            string text = "ShootIn удалена.";
            if (kept != null) text += "\n\nВаши моды сохранены в папке:\n" + kept;
            if (!removeData && Directory.Exists(Info.UserDataDir)) text += "\n\nСохранения игры остались в папке:\n" + Info.UserDataDir;
            MessageBox.Show(text, "Удаление ShootIn", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        return 0;
    }

    static void TryDeleteTree(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, true); }
        catch (Exception ex) { Log.Write("не удалось удалить " + path + ": " + ex.Message); }
    }
}

#else

class InstallOptions
{
    public string Dir;
    public bool Desktop = true;
    public bool StartMenu = true;
}

class InstallResult
{
    public string Dir;
    public string ModsDir;
    public string UserModsDir;
    public List<string> Shortcuts = new List<string>();
}

static class Installer
{
    public static Stream OpenPayload()
    {
        Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip");
        if (stream == null) throw new InvalidOperationException("В установщике нет данных игры (payload.zip).");
        return stream;
    }

    public static long PayloadSize()
    {
        long total = 0;
        using (var zip = new ZipArchive(OpenPayload(), ZipArchiveMode.Read))
            foreach (ZipArchiveEntry entry in zip.Entries) total += entry.Length;
        return total;
    }

    public static string CheckDir(string dir)
    {
        if (string.IsNullOrWhiteSpace(dir)) return "Укажите папку для установки.";
        try
        {
            string full = Path.GetFullPath(dir);
            if (!Path.IsPathRooted(full) || full.Length < 4) return "Укажите папку на диске, например " + Info.DefaultDir;
            if (full.IndexOfAny(Path.GetInvalidPathChars()) >= 0) return "В пути есть недопустимые символы.";
        }
        catch (Exception) { return "Путь указан неверно."; }
        return null;
    }

    public static InstallResult Install(InstallOptions options, Action<int, string> progress)
    {
        string dir = Path.GetFullPath(options.Dir);
        var result = new InstallResult();
        result.Dir = dir;
        Log.Write("установка в " + dir);

        progress(2, "Создаю папки…");
        Directory.CreateDirectory(dir);
        result.ModsDir = Path.Combine(dir, "mods");
        Directory.CreateDirectory(result.ModsDir);
        Directory.CreateDirectory(Info.UserDataDir);
        result.UserModsDir = Path.Combine(Info.UserDataDir, "mods");
        Directory.CreateDirectory(result.UserModsDir);

        using (var zip = new ZipArchive(OpenPayload(), ZipArchiveMode.Read))
        {
            long total = 0, done = 0;
            foreach (ZipArchiveEntry entry in zip.Entries) total += entry.Length;
            byte[] buffer = new byte[1 << 20];
            foreach (ZipArchiveEntry entry in zip.Entries)
            {
                if (entry.FullName.EndsWith("/")) continue;
                string target = Path.GetFullPath(Path.Combine(dir, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                if (!target.StartsWith(dir, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Недопустимый путь в данных установщика: " + entry.FullName);
                Directory.CreateDirectory(Path.GetDirectoryName(target));
                progress(2 + (int)(86 * done / Math.Max(total, 1)), "Копирую " + entry.Name + "…");
                using (Stream input = entry.Open())
                using (var output = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    int read;
                    while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        output.Write(buffer, 0, read);
                        done += read;
                        progress(2 + (int)(86 * done / Math.Max(total, 1)), "Копирую " + entry.Name + "…");
                    }
                }
                Log.Write("записан " + target);
            }
        }

        progress(90, "Записываю деинсталлятор…");
        string uninstall = Path.Combine(dir, Info.UninstallName);
        using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("uninstall.exe"))
        {
            if (resource == null) throw new InvalidOperationException("В установщике нет деинсталлятора.");
            using (var output = new FileStream(uninstall, FileMode.Create, FileAccess.Write, FileShare.None)) resource.CopyTo(output);
        }
        File.WriteAllText(Path.Combine(result.ModsDir, "Как установить моды.txt"),
            "Сюда можно класть моды для ShootIn: .zip-архивы или папки с файлом mod.json.\r\n" +
            "Игра находит их при открытии экрана «Моды» (главное меню → Моды) и включает галочкой.\r\n" +
            "Моды, установленные кнопкой «Установить из файла…» прямо в игре, лежат в другой папке:\r\n" +
            result.UserModsDir + "\r\n", new UTF8Encoding(true));

        string exe = Path.Combine(dir, Info.ExeName);
        string description = Info.Name + " — " + Info.Tagline;
        if (options.StartMenu)
        {
            progress(93, "Создаю ярлыки в меню «Пуск»…");
            string menu = Info.StartMenuDir;
            string link = Path.Combine(menu, "ShootIn.lnk");
            Shell.CreateShortcut(link, exe, "", dir, description, exe);
            result.Shortcuts.Add(link);
            string modsLink = Path.Combine(menu, "Папка модов ShootIn.lnk");
            Shell.CreateShortcut(modsLink, result.ModsDir, "", result.ModsDir, "Папка с модами ShootIn", exe);
            result.Shortcuts.Add(modsLink);
            string removeLink = Path.Combine(menu, "Удалить ShootIn.lnk");
            Shell.CreateShortcut(removeLink, uninstall, "", dir, "Удалить ShootIn", uninstall);
            result.Shortcuts.Add(removeLink);
        }
        if (options.Desktop)
        {
            progress(95, "Создаю ярлык на рабочем столе…");
            Shell.CreateShortcut(Info.DesktopLink, exe, "", dir, description, exe);
            result.Shortcuts.Add(Info.DesktopLink);
        }

        progress(97, "Регистрирую программу в Windows…");
        using (RegistryKey key = Registry.CurrentUser.CreateSubKey(Info.RegistryKey))
        {
            key.SetValue("DisplayName", Info.Name);
            key.SetValue("DisplayVersion", BuildInfo.Version);
            key.SetValue("Publisher", Info.Publisher);
            key.SetValue("InstallLocation", dir);
            key.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
            key.SetValue("DisplayIcon", exe);
            key.SetValue("UninstallString", "\"" + uninstall + "\"");
            key.SetValue("QuietUninstallString", "\"" + uninstall + "\" /S");
            key.SetValue("EstimatedSize", (int)(new FileInfo(exe).Length / 1024), RegistryValueKind.DWord);
            key.SetValue("NoModify", 1, RegistryValueKind.DWord);
            key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }
        progress(100, "Готово.");
        Log.Write("установка завершена");
        return result;
    }

    public static void Launch(string dir)
    {
        var start = new ProcessStartInfo(Path.Combine(dir, Info.ExeName));
        start.WorkingDirectory = dir;
        Process.Start(start);
    }
}

class SetupForm : Form
{
    readonly InstallOptions options;
    readonly bool launchAfter;
    Panel pageOptions, pageProgress, pageDone;
    TextBox pathBox;
    Label spaceLabel, statusLabel, doneTitle, doneText;
    CheckBox desktopBox, menuBox, launchBox;
    ProgressBar bar;
    Button installButton, cancelButton, closeButton;
    InstallResult result;
    bool installing;

    public SetupForm(InstallOptions options, bool launchAfter)
    {
        this.options = options;
        this.launchAfter = launchAfter;
        Text = "Установка ShootIn";
        Font = new Font("Segoe UI", 9f);
        AutoScaleMode = AutoScaleMode.Font;
        ClientSize = new Size(600, 410);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
        Build();
    }

    void Build()
    {
        var header = new Panel { Dock = DockStyle.Top, Height = 84, BackColor = Color.FromArgb(26, 28, 38) };
        var logo = new PictureBox { Left = 18, Top = 14, Width = 56, Height = 56, SizeMode = PictureBoxSizeMode.Zoom };
        try { logo.Image = Icon.ToBitmap(); } catch (Exception) { }
        var title = new Label { Left = 88, Top = 14, Width = 480, Height = 34, Text = "ShootIn " + BuildInfo.Version, ForeColor = Color.FromArgb(255, 220, 90), Font = new Font("Segoe UI", 17f, FontStyle.Bold) };
        var subtitle = new Label { Left = 90, Top = 50, Width = 480, Height = 22, Text = Info.Tagline, ForeColor = Color.FromArgb(200, 200, 220) };
        header.Controls.Add(logo);
        header.Controls.Add(title);
        header.Controls.Add(subtitle);

        var footer = new Panel { Dock = DockStyle.Bottom, Height = 56, BackColor = Color.FromArgb(240, 240, 244) };
        installButton = new Button { Text = "Установить", Width = 130, Height = 32, Left = 330, Top = 12 };
        cancelButton = new Button { Text = "Отмена", Width = 110, Height = 32, Left = 472, Top = 12 };
        closeButton = new Button { Text = "Готово", Width = 130, Height = 32, Left = 452, Top = 12, Visible = false };
        installButton.Click += delegate { StartInstall(); };
        cancelButton.Click += delegate { Close(); };
        closeButton.Click += delegate { Finish(); };
        footer.Controls.Add(installButton);
        footer.Controls.Add(cancelButton);
        footer.Controls.Add(closeButton);

        var body = new Panel { Dock = DockStyle.Fill };

        pageOptions = new Panel { Dock = DockStyle.Fill };
        pageOptions.Controls.Add(new Label { Left = 24, Top = 16, Width = 552, Height = 40, Text = "Мастер установит ShootIn на ваш компьютер. Права администратора не нужны: игра ставится в профиль пользователя." });
        pageOptions.Controls.Add(new Label { Left = 24, Top = 66, Width = 400, Height = 20, Text = "Папка установки:" });
        pathBox = new TextBox { Left = 24, Top = 90, Width = 440, Text = options.Dir };
        pathBox.TextChanged += delegate { UpdateSpace(); };
        var browse = new Button { Left = 474, Top = 88, Width = 100, Height = 27, Text = "Обзор…" };
        browse.Click += delegate
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "Выберите папку для ShootIn";
                if (dialog.ShowDialog(this) == DialogResult.OK)
                    pathBox.Text = Path.Combine(dialog.SelectedPath, dialog.SelectedPath.EndsWith("ShootIn", StringComparison.OrdinalIgnoreCase) ? "" : "ShootIn").TrimEnd('\\');
            }
        };
        spaceLabel = new Label { Left = 24, Top = 122, Width = 552, Height = 20, ForeColor = Color.FromArgb(90, 90, 100) };
        desktopBox = new CheckBox { Left = 24, Top = 156, Width = 400, Height = 24, Text = "Ярлык на рабочем столе", Checked = options.Desktop };
        menuBox = new CheckBox { Left = 24, Top = 182, Width = 400, Height = 24, Text = "Ярлыки в меню «Пуск»", Checked = options.StartMenu };
        pageOptions.Controls.Add(new Label { Left = 24, Top = 224, Width = 552, Height = 64, ForeColor = Color.FromArgb(90, 90, 100),
            Text = "Будут созданы: папка игры, папка mods рядом с игрой (сюда кладут моды), папка сохранений и модов игрока, запись в «Установке и удалении программ» и деинсталлятор." });
        pageOptions.Controls.Add(pathBox);
        pageOptions.Controls.Add(browse);
        pageOptions.Controls.Add(spaceLabel);
        pageOptions.Controls.Add(desktopBox);
        pageOptions.Controls.Add(menuBox);

        pageProgress = new Panel { Dock = DockStyle.Fill, Visible = false };
        pageProgress.Controls.Add(new Label { Left = 24, Top = 70, Width = 552, Height = 24, Text = "Устанавливаю ShootIn…", Font = new Font("Segoe UI", 11f, FontStyle.Bold) });
        bar = new ProgressBar { Left = 24, Top = 110, Width = 552, Height = 24, Minimum = 0, Maximum = 100 };
        statusLabel = new Label { Left = 24, Top = 144, Width = 552, Height = 24 };
        pageProgress.Controls.Add(bar);
        pageProgress.Controls.Add(statusLabel);

        pageDone = new Panel { Dock = DockStyle.Fill, Visible = false };
        doneTitle = new Label { Left = 24, Top = 20, Width = 552, Height = 30, Font = new Font("Segoe UI", 13f, FontStyle.Bold) };
        doneText = new Label { Left = 24, Top = 60, Width = 552, Height = 150 };
        launchBox = new CheckBox { Left = 24, Top = 226, Width = 400, Height = 24, Text = "Запустить ShootIn", Checked = launchAfter };
        pageDone.Controls.Add(doneTitle);
        pageDone.Controls.Add(doneText);
        pageDone.Controls.Add(launchBox);

        body.Controls.Add(pageOptions);
        body.Controls.Add(pageProgress);
        body.Controls.Add(pageDone);
        Controls.Add(body);
        Controls.Add(header);
        Controls.Add(footer);
        UpdateSpace();
    }

    void UpdateSpace()
    {
        string text;
        try
        {
            long need = Installer.PayloadSize() + 2 * 1024 * 1024;
            string root = Path.GetPathRoot(Path.GetFullPath(pathBox.Text));
            var drive = new DriveInfo(root);
            text = "Нужно около " + (need / 1048576) + " МБ, свободно на диске " + root + " — " + (drive.AvailableFreeSpace / 1048576) + " МБ.";
            installButton.Enabled = drive.AvailableFreeSpace > need;
            if (!installButton.Enabled) text = "Не хватает места на диске " + root + " (нужно около " + (need / 1048576) + " МБ).";
        }
        catch (Exception)
        {
            text = "Укажите существующий диск и папку.";
            installButton.Enabled = false;
        }
        spaceLabel.Text = text;
    }

    void StartInstall()
    {
        string error = Installer.CheckDir(pathBox.Text);
        if (error != null) { MessageBox.Show(this, error, "Установка ShootIn", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        options.Dir = Path.GetFullPath(pathBox.Text);
        options.Desktop = desktopBox.Checked;
        options.StartMenu = menuBox.Checked;
        List<Process> running = Shell.RunningGame(options.Dir);
        if (running.Count > 0)
        {
            if (MessageBox.Show(this, "ShootIn сейчас запущена. Закрыть игру и продолжить установку?", "Установка ShootIn", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) != DialogResult.Yes) return;
            Shell.CloseGame(running);
        }
        pageOptions.Visible = false;
        pageProgress.Visible = true;
        installButton.Visible = false;
        cancelButton.Enabled = false;
        installing = true;
        var worker = new Thread(delegate()
        {
            try
            {
                InstallResult r = Installer.Install(options, delegate(int percent, string text)
                {
                    BeginInvoke(new MethodInvoker(delegate { bar.Value = Math.Min(100, Math.Max(0, percent)); statusLabel.Text = text; }));
                });
                BeginInvoke(new MethodInvoker(delegate { ShowDone(r, null); }));
            }
            catch (Exception ex)
            {
                Log.Write("ошибка: " + ex);
                BeginInvoke(new MethodInvoker(delegate { ShowDone(null, ex); }));
            }
        });
        worker.IsBackground = true;
        worker.Start();
    }

    void ShowDone(InstallResult r, Exception error)
    {
        installing = false;
        result = r;
        pageProgress.Visible = false;
        pageDone.Visible = true;
        cancelButton.Visible = false;
        closeButton.Visible = true;
        if (error != null)
        {
            doneTitle.Text = "Не удалось установить ShootIn";
            string reason = error.Message;
            if (error is UnauthorizedAccessException) reason = "Нет прав на запись в выбранную папку. Выберите другую — по умолчанию игра ставится в папку вашего профиля.";
            else if (error is IOException) reason = reason + "\n\nЕсли игра запущена, закройте её и повторите установку.";
            doneText.Text = reason;
            launchBox.Visible = false;
            closeButton.Text = "Закрыть";
            return;
        }
        doneTitle.Text = "ShootIn установлена";
        doneText.Text = "Игра:  " + r.Dir + "\nМоды (кладите сюда):  " + r.ModsDir + "\nСохранения и моды из игры:  " + Info.UserDataDir +
            (r.Shortcuts.Count > 0 ? "\n\nЯрлыки созданы: " + r.Shortcuts.Count : "") +
            "\n\nУдалить игру можно через «Параметры → Приложения» или ярлык «Удалить ShootIn».";
    }

    void Finish()
    {
        if (result != null && launchBox.Checked)
        {
            try { Installer.Launch(result.Dir); }
            catch (Exception ex) { MessageBox.Show(this, "Не удалось запустить игру: " + ex.Message); }
        }
        Close();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (installing) e.Cancel = true;
        base.OnFormClosing(e);
    }
}

static class Setup
{
    [STAThread]
    static int Main(string[] args)
    {
        Log.Path = Args.Value(args, "/LOG=");
        var options = new InstallOptions();
        options.Dir = Args.Value(args, "/D=") ?? Info.DefaultDir;
        options.Desktop = !Args.Has(args, "/NODESKTOP");
        options.StartMenu = !Args.Has(args, "/NOSTARTMENU");
        if (Args.Has(args, "/S"))
        {
            string error = Installer.CheckDir(options.Dir);
            if (error != null) { Log.Write(error); return 2; }
            try
            {
                List<Process> running = Shell.RunningGame(Path.GetFullPath(options.Dir));
                Shell.CloseGame(running);
                InstallResult r = Installer.Install(options, delegate(int percent, string text) { });
                if (Args.Has(args, "/LAUNCH")) Installer.Launch(r.Dir);
                return 0;
            }
            catch (Exception ex)
            {
                Log.Write("ошибка: " + ex);
                return 1;
            }
        }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SetupForm(options, !Args.Has(args, "/NOLAUNCH")));
        return 0;
    }
}

#endif
