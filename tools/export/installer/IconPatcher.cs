// Подменяет значок и сведения о файле (версия, название, описание) внутри готового exe.
// Нужен, чтобы ShootIn.exe в проводнике и диспетчере задач выглядел как игра, а не как «Godot Engine»,
// и чтобы не требовался внешний rcedit. Работает через Win32 UpdateResource.
//
// Запуск:  IconPatcher.exe <файл.exe> <значок.ico> <версия 1.0.0> "<название>" "<описание>" "<компания>"
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

static class IconPatcher
{
    const int RT_ICON = 3, RT_GROUP_ICON = 14, RT_VERSION = 16;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr BeginUpdateResource(string file, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool UpdateResource(IntPtr h, IntPtr type, IntPtr name, ushort lang, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool EndUpdateResource(IntPtr h, bool discard);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryEx(string file, IntPtr zero, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool FreeLibrary(IntPtr module);
    delegate bool EnumLangProc(IntPtr module, IntPtr type, IntPtr name, ushort lang, IntPtr param);
    delegate bool EnumNameProc(IntPtr module, IntPtr type, IntPtr name, IntPtr param);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool EnumResourceNames(IntPtr module, IntPtr type, EnumNameProc proc, IntPtr param);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool EnumResourceLanguages(IntPtr module, IntPtr type, IntPtr name, EnumLangProc proc, IntPtr param);

    static int Main(string[] args)
    {
        if (args.Length < 6)
        {
            Console.Error.WriteLine("Использование: IconPatcher <exe> <ico> <версия> <название> <описание> <компания>");
            return 2;
        }
        string exe = args[0], ico = args[1], version = args[2], product = args[3], description = args[4], company = args[5];
        try
        {
            // 1. Что уже есть в файле: старые группы значков, значки и версия — их нужно убрать.
            var oldGroups = new List<Res>();
            var oldIcons = new List<Res>();
            var oldVersion = new List<Res>();
            IntPtr module = LoadLibraryEx(exe, IntPtr.Zero, 0x2 /* LOAD_LIBRARY_AS_DATAFILE */);
            if (module == IntPtr.Zero) throw new Exception("Не удалось открыть exe: " + Marshal.GetLastWin32Error());
            Collect(module, (IntPtr)RT_GROUP_ICON, oldGroups);
            Collect(module, (IntPtr)RT_ICON, oldIcons);
            Collect(module, (IntPtr)RT_VERSION, oldVersion);
            FreeLibrary(module);
            if (Environment.GetEnvironmentVariable("ICONPATCH_DEBUG") != null)
            {
                foreach (var r in oldGroups) Console.WriteLine("группа: " + (r.Name ?? r.Id.ToString()) + " язык " + r.Lang);
                foreach (var r in oldIcons) Console.WriteLine("значок: " + (r.Name ?? r.Id.ToString()) + " язык " + r.Lang);
                foreach (var r in oldVersion) Console.WriteLine("версия: " + (r.Name ?? r.Id.ToString()) + " язык " + r.Lang);
            }

            IntPtr h = BeginUpdateResource(exe, false);
            if (h == IntPtr.Zero) throw new Exception("BeginUpdateResource: " + Marshal.GetLastWin32Error());
            foreach (var r in oldGroups) Remove(h, RT_GROUP_ICON, r);
            foreach (var r in oldIcons) Remove(h, RT_ICON, r);
            foreach (var r in oldVersion) Remove(h, RT_VERSION, r);

            // 2. Новый значок из .ico: каждая картинка — отдельный RT_ICON, плюс одна группа.
            byte[] icoBytes = File.ReadAllBytes(ico);
            int count = BitConverter.ToUInt16(icoBytes, 4);
            var group = new MemoryStream();
            var gw = new BinaryWriter(group);
            gw.Write((ushort)0); gw.Write((ushort)1); gw.Write((ushort)count);
            for (int i = 0; i < count; i++)
            {
                int e = 6 + i * 16;
                int size = BitConverter.ToInt32(icoBytes, e + 8), offset = BitConverter.ToInt32(icoBytes, e + 12);
                byte[] image = new byte[size];
                Array.Copy(icoBytes, offset, image, 0, size);
                ushort id = (ushort)(i + 1);
                if (!UpdateResource(h, (IntPtr)RT_ICON, (IntPtr)id, 1033, image, (uint)size)) throw new Exception("RT_ICON: " + Marshal.GetLastWin32Error());
                gw.Write(icoBytes[e]); gw.Write(icoBytes[e + 1]); gw.Write(icoBytes[e + 2]); gw.Write(icoBytes[e + 3]);
                gw.Write(BitConverter.ToUInt16(icoBytes, e + 4)); gw.Write(BitConverter.ToUInt16(icoBytes, e + 6));
                gw.Write(size); gw.Write(id);
            }
            byte[] groupBytes = group.ToArray();
            if (!UpdateResource(h, (IntPtr)RT_GROUP_ICON, (IntPtr)1, 1033, groupBytes, (uint)groupBytes.Length)) throw new Exception("RT_GROUP_ICON: " + Marshal.GetLastWin32Error());

            // 3. Сведения о файле.
            byte[] ver = BuildVersion(version, product, description, company);
            if (!UpdateResource(h, (IntPtr)RT_VERSION, (IntPtr)1, 1033, ver, (uint)ver.Length)) throw new Exception("RT_VERSION: " + Marshal.GetLastWin32Error());

            if (!EndUpdateResource(h, false)) throw new Exception("EndUpdateResource: " + Marshal.GetLastWin32Error());
            Console.WriteLine("Готово: значок и сведения обновлены в " + exe);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("ОШИБКА: " + ex.Message);
            return 1;
        }
    }

    // Имя ресурса — либо число, либо строка; строку копируем сразу, пока модуль загружен.
    class Res
    {
        public ushort Id;
        public string Name;
        public ushort Lang;
    }

    static void Collect(IntPtr module, IntPtr type, List<Res> into)
    {
        var names = new List<Res>();
        EnumResourceNames(module, type, (m, t, n, p) =>
        {
            var res = new Res();
            if (((long)n >> 16) == 0) res.Id = (ushort)(long)n; else res.Name = Marshal.PtrToStringUni(n);
            names.Add(res);
            return true;
        }, IntPtr.Zero);
        foreach (Res res in names)
        {
            IntPtr name = res.Name != null ? Marshal.StringToHGlobalUni(res.Name) : (IntPtr)res.Id;
            EnumResourceLanguages(module, type, name, (m, t, n, lang, p) =>
            {
                into.Add(new Res { Id = res.Id, Name = res.Name, Lang = lang });
                return true;
            }, IntPtr.Zero);
            if (res.Name != null) Marshal.FreeHGlobal(name);
        }
    }

    static void Remove(IntPtr h, int type, Res res)
    {
        IntPtr name = res.Name != null ? Marshal.StringToHGlobalUni(res.Name) : (IntPtr)res.Id;
        UpdateResource(h, (IntPtr)type, name, res.Lang, null, 0);
        if (res.Name != null) Marshal.FreeHGlobal(name);
    }

    // --- VS_VERSIONINFO -----------------------------------------------------------------------
    static byte[] BuildVersion(string version, string product, string description, string company)
    {
        string[] parts = (version + ".0.0.0").Split('.');
        ushort a = ushort.Parse(parts[0]), b = ushort.Parse(parts[1]), c = ushort.Parse(parts[2]), d = ushort.Parse(parts[3]);
        string four = a + "." + b + "." + c + "." + d;

        var fixedInfo = new MemoryStream();
        var fw = new BinaryWriter(fixedInfo);
        fw.Write(0xFEEF04BDu); fw.Write(0x00010000u);
        fw.Write((uint)((a << 16) | b)); fw.Write((uint)((c << 16) | d));
        fw.Write((uint)((a << 16) | b)); fw.Write((uint)((c << 16) | d));
        fw.Write(0x3Fu); fw.Write(0u); fw.Write(0x00040004u); fw.Write(1u); fw.Write(0u); fw.Write(0u); fw.Write(0u);

        var strings = new MemoryStream();
        WriteString(strings, "CompanyName", company);
        WriteString(strings, "FileDescription", description);
        WriteString(strings, "FileVersion", four);
        WriteString(strings, "InternalName", product);
        WriteString(strings, "LegalCopyright", company);
        WriteString(strings, "OriginalFilename", product + ".exe");
        WriteString(strings, "ProductName", product);
        WriteString(strings, "ProductVersion", four);
        byte[] table = Node("040904B0", new byte[0], strings.ToArray(), 1, 0);
        byte[] stringFileInfo = Node("StringFileInfo", new byte[0], table, 1, 0);

        var translation = new MemoryStream();
        var tw = new BinaryWriter(translation);
        tw.Write((ushort)0x0409); tw.Write((ushort)0x04B0);
        byte[] varNode = Node("Translation", translation.ToArray(), new byte[0], 0, translation.ToArray().Length);
        byte[] varFileInfo = Node("VarFileInfo", new byte[0], varNode, 1, 0);

        var body = new MemoryStream();
        body.Write(stringFileInfo, 0, stringFileInfo.Length); Align(body);
        body.Write(varFileInfo, 0, varFileInfo.Length);
        return Node("VS_VERSION_INFO", fixedInfo.ToArray(), body.ToArray(), 0, fixedInfo.ToArray().Length);
    }

    static void WriteString(MemoryStream into, string key, string value)
    {
        byte[] valueBytes = Encoding.Unicode.GetBytes(value + "\0");
        byte[] node = Node(key, valueBytes, new byte[0], 1, valueBytes.Length / 2);
        Align(into);
        into.Write(node, 0, node.Length);
    }

    // Узел: wLength, wValueLength, wType, ключ (UTF-16), выравнивание, значение, выравнивание, дети.
    static byte[] Node(string key, byte[] value, byte[] children, ushort type, int valueLength)
    {
        var ms = new MemoryStream();
        var w = new BinaryWriter(ms);
        w.Write((ushort)0); w.Write((ushort)valueLength); w.Write(type);
        byte[] keyBytes = Encoding.Unicode.GetBytes(key + "\0");
        w.Write(keyBytes);
        Align(ms);
        w.Write(value);
        if (children.Length > 0) { Align(ms); w.Write(children); }
        byte[] result = ms.ToArray();
        result[0] = (byte)(result.Length & 0xFF);
        result[1] = (byte)(result.Length >> 8);
        return result;
    }

    static void Align(MemoryStream ms)
    {
        while (ms.Position % 4 != 0) ms.WriteByte(0);
    }
}
