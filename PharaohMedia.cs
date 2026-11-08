using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

public static class PharaohMedia
{
    private const int RawSector = 2352, Sector = 2048;
    private const int SectorCount = 255442;

    public static void Install(string image, string destination)
    {
        string extension = Path.GetExtension(image).ToLowerInvariant();
        if (extension == ".ccd") image = Path.ChangeExtension(image, ".img");
        bool raw = extension != ".iso";
        string iso = Path.Combine(destination, "Pharaoh.iso");
        if (raw)
        {
            using (var input = File.OpenRead(image))
            using (var output = File.Open(iso, FileMode.CreateNew, FileAccess.Write))
            {
                if (input.Length != (long)SectorCount * RawSector)
                    throw new InvalidDataException("Unexpected CD image size.");
                byte[] source = new byte[RawSector * 256], data = new byte[Sector * 256];
                for (int index = 0; index < SectorCount; index += 256)
                {
                    int count = Math.Min(256, SectorCount - index);
                    Read(input, source, count * RawSector);
                    for (int i = 0; i < count; i++)
                    {
                        int offset = i * RawSector;
                        if (source[offset + 15] != 1)
                            throw new InvalidDataException("Expected a Mode 1 CD image.");
                        Buffer.BlockCopy(source, offset + 16, data, i * Sector, Sector);
                    }
                    output.Write(data, 0, count * Sector);
                }
            }
        }
        else File.Copy(image, iso);
        using (var disc = File.OpenRead(iso))
        {
            if (disc.Length != (long)SectorCount * Sector)
                throw new InvalidDataException("Unexpected ISO size.");
            byte[] pvd = DiscRead(disc, 16, Sector);
            if (Encoding.ASCII.GetString(pvd, 0, 7) != "\u0001CD001\u0001" ||
                Encoding.ASCII.GetString(pvd, 40, 32).Trim() != "PHARAOH")
                throw new InvalidDataException("Expected the PHARAOH disc.");
            // Fixed extents are specific to the inspected Japanese 1.0 pressing.
            byte[] hdr = DiscRead(disc, 32328, 25939);
            byte[] cab = DiscRead(disc, 193, 65811884);
            using (var sha = SHA256.Create())
            {
                if (Hex(sha.ComputeHash(hdr)) != "E0A5D7236E31CB9FDEB28C0A9E4EBA2CBBDC37A4940FB9CD230D206C67FEBE52" ||
                    Hex(sha.ComputeHash(cab)) != "0CF7C387FF9FDA0AD3E035F47E13BE7B16AB6A0D0D34FB302E288AB5EF17CB5B")
                    throw new InvalidDataException("This disc does not match the supported Japanese 1.0 release.");
            }
            Expand(hdr, cab, destination);
        }
        Directory.CreateDirectory(Path.Combine(destination, "Save"));
    }

    private static byte[] DiscRead(Stream disc, int sector, int size)
    {
        var bytes = new byte[size];
        disc.Position = sector * (long)Sector;
        Read(disc, bytes, size);
        return bytes;
    }

    private static void Read(Stream stream, byte[] bytes, int size)
    {
        int offset = 0;
        while (offset < size)
        {
            int got = stream.Read(bytes, offset, size - offset);
            if (got == 0) throw new EndOfStreamException();
            offset += got;
        }
    }

    private static int U32(byte[] bytes, int offset) { return BitConverter.ToInt32(bytes, offset); }
    private static int U16(byte[] bytes, int offset) { return BitConverter.ToUInt16(bytes, offset); }
    private static string Hex(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-", ""); }
    private static string Name(byte[] bytes, int offset)
    {
        return Encoding.GetEncoding(932).GetString(bytes, offset, Array.IndexOf<byte>(bytes, 0, offset) - offset);
    }

    // InstallShield 5 file table and length-prefixed raw DEFLATE blocks.
    private static void Expand(byte[] hdr, byte[] cab, string root)
    {
        int descriptor = U32(hdr, 12);
        int table = descriptor + U32(hdr, descriptor + 12);
        int dirCount = U32(hdr, descriptor + 28);
        int fileCount = U32(hdr, descriptor + 40);
        using (var md5 = MD5.Create())
        {
            for (int i = 0; i < fileCount; i++)
            {
                int entry = table + U32(hdr, table + (dirCount + i) * 4);
                int flags = U16(hdr, entry + 8);
                if ((flags & 8) != 0) continue;
                if (flags != 4) throw new InvalidDataException("Unexpected CAB flags.");
                string name = Name(hdr, table + U32(hdr, entry));
                int directoryOffset = U32(hdr, table + U16(hdr, entry + 4) * 4);
                string directory = Name(hdr, table + directoryOffset);
                if (Path.GetFileName(name) != name || Array.IndexOf(new[] {"", "Data", "Maps", "Save"}, directory) < 0)
                    throw new InvalidDataException("Unexpected CAB path.");
                int size = U32(hdr, entry + 10);
                int start = U32(hdr, entry + 38), end = start + U32(hdr, entry + 14);
                using (var expanded = new MemoryStream(size))
                {
                    for (int offset = start; offset < end;)
                    {
                        int length = U16(cab, offset);
                        offset += 2;
                        if (length == 0 || offset + length > end)
                            throw new InvalidDataException("Invalid CAB block.");
                        using (var block = new MemoryStream(cab, offset, length, false))
                        using (var deflate = new DeflateStream(block, CompressionMode.Decompress))
                            deflate.CopyTo(expanded);
                        offset += length;
                    }
                    expanded.Position = 0;
                    if (expanded.Length != size || Hex(md5.ComputeHash(expanded)) !=
                        BitConverter.ToString(hdr, entry + 42, 16).Replace("-", ""))
                        throw new InvalidDataException("CAB verification failed for " + name);
                    string folder = Path.Combine(root, directory);
                    Directory.CreateDirectory(folder);
                    File.WriteAllBytes(Path.Combine(folder, name), expanded.ToArray());
                }
            }
        }
    }
}
