// FontKit: leitura/escrita de fontes TrueType (glyf) sem dependências.
// Veio da pasta Fonte (Set-SystemFont.ps1 e Build-FontFamily.ps1). No Tamanduá: compilado pelo núcleo (Initialize-TmdFontKit),
// só quando a página Fonte precisa (C# 5, Add-Type do PowerShell 5.1).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public class Sfnt {
    public uint Version;
    public SortedDictionary<string, byte[]> Tables = new SortedDictionary<string, byte[]>(StringComparer.Ordinal);

    public static ushort U16(byte[] b, int o) { return (ushort)(b[o] << 8 | b[o + 1]); }
    public static short S16(byte[] b, int o) { return (short)U16(b, o); }
    public static uint U32(byte[] b, int o) { return (uint)(b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3]); }
    public static void W16(byte[] b, int o, int v) { b[o] = (byte)(v >> 8); b[o + 1] = (byte)v; }
    public static void W32(byte[] b, int o, uint v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }

    public static Sfnt Load(string path) {
        byte[] b = File.ReadAllBytes(path);
        uint ver = U32(b, 0);
        if (ver == 0x74746366) throw new Exception(path + ": coleções .ttc não são suportadas");
        if (ver == 0x774F4646 || ver == 0x774F4632) throw new Exception(path + ": converta o .woff/.woff2 para .ttf antes");
        if (ver != 0x00010000 && ver != 0x4F54544F && ver != 0x74727565) throw new Exception(path + ": não parece ser TTF/OTF");
        var f = new Sfnt { Version = ver };
        int n = U16(b, 4);
        for (int i = 0; i < n; i++) {
            int r = 12 + i * 16;
            string tag = Encoding.ASCII.GetString(b, r, 4);
            int off = (int)U32(b, r + 8), len = (int)U32(b, r + 12);
            var data = new byte[len];
            Buffer.BlockCopy(b, off, data, 0, len);
            f.Tables[tag] = data;
        }
        return f;
    }

    public bool Has(string tag) { return Tables.ContainsKey(tag); }
    public byte[] Get(string tag) { return Tables[tag]; }

    static uint Checksum(byte[] b, int off, int len) {
        uint sum = 0;
        for (int i = 0; i < len; i += 4) {
            uint v = 0;
            for (int k = 0; k < 4; k++) v = v << 8 | (uint)(i + k < len ? b[off + i + k] : 0);
            sum += v;
        }
        return sum;
    }

    public void Save(string path) {
        int n = Tables.Count;
        int pow = 1, sel = 0;
        while (pow * 2 <= n) { pow *= 2; sel++; }
        int dirLen = 12 + 16 * n;
        int total = dirLen;
        foreach (var t in Tables.Values) total += (t.Length + 3) & ~3;
        var o = new byte[total];
        W32(o, 0, Version); W16(o, 4, n); W16(o, 6, pow * 16); W16(o, 8, sel); W16(o, 10, n * 16 - pow * 16);
        if (Tables.ContainsKey("head")) W32(Tables["head"], 8, 0);
        int pos = dirLen, i = 0, headOff = -1;
        foreach (var kv in Tables) {
            int r = 12 + i * 16;
            Encoding.ASCII.GetBytes(kv.Key, 0, 4, o, r);
            W32(o, r + 4, Checksum(kv.Value, 0, kv.Value.Length));
            W32(o, r + 8, (uint)pos);
            W32(o, r + 12, (uint)kv.Value.Length);
            Buffer.BlockCopy(kv.Value, 0, o, pos, kv.Value.Length);
            if (kv.Key == "head") headOff = pos;
            pos += (kv.Value.Length + 3) & ~3;
            i++;
        }
        if (headOff >= 0) W32(o, headOff + 8, 0xB1B0AFBA - Checksum(o, 0, o.Length));
        File.WriteAllBytes(path, o);
    }

    // Registros da tabela 'name': plataforma, encoding, idioma, nameID, texto
    public List<Tuple<int, int, int, int, string>> Names() {
        var res = new List<Tuple<int, int, int, int, string>>();
        if (!Has("name")) return res;
        byte[] b = Tables["name"];
        int count = U16(b, 2), strOff = U16(b, 4);
        for (int i = 0; i < count; i++) {
            int r = 6 + i * 12;
            int pid = U16(b, r), eid = U16(b, r + 2), lid = U16(b, r + 4), nid = U16(b, r + 6);
            int len = U16(b, r + 8), off = U16(b, r + 10);
            if (strOff + off + len > b.Length) continue;
            string s = (pid == 0 || pid == 3)
                ? Encoding.BigEndianUnicode.GetString(b, strOff + off, len)
                : Encoding.GetEncoding("iso-8859-1").GetString(b, strOff + off, len);
            res.Add(Tuple.Create(pid, eid, lid, nid, s));
        }
        return res;
    }

    public string Name(int nid) {
        var all = Names();
        var w = all.FirstOrDefault(t => t.Item1 == 3 && t.Item3 == 0x409 && t.Item4 == nid)
             ?? all.FirstOrDefault(t => t.Item1 == 3 && t.Item4 == nid)
             ?? all.FirstOrDefault(t => t.Item4 == nid);
        return w == null ? null : w.Item5;
    }

    // Reescreve a tabela 'name' só com registros Windows/en-US. Mantém copyright, fabricante,
    // designer e licença da fonte; os valores passados substituem (null remove).
    public void SetNames(IDictionary<int, string> names) {
        var keep = new HashSet<int> { 0, 7, 8, 9, 11, 12, 13, 14 };
        var recs = new SortedDictionary<int, string>();
        foreach (var t in Names())
            if (t.Item1 == 3 && t.Item3 == 0x409 && keep.Contains(t.Item4)) recs[t.Item4] = t.Item5;
        // null ou vazio remove o registro (o PowerShell converte $null em "" ao passar para
        // Dictionary<int,string>; um ID 16 vazio deixa a família sem nome no DirectWrite)
        foreach (var kv in names) {
            if (string.IsNullOrEmpty(kv.Value)) recs.Remove(kv.Key); else recs[kv.Key] = kv.Value;
        }
        // O GDI recusa a fonte (AddFontResource) sem o identificador único (ID 3)
        if (!recs.ContainsKey(3) && recs.ContainsKey(1))
            recs[3] = recs.ContainsKey(6) ? recs[6] : recs[1] + (recs.ContainsKey(2) ? "-" + recs[2] : "");
        int count = recs.Count, strOff = 6 + 12 * count;
        var strings = new List<byte>();
        var o = new byte[strOff];
        W16(o, 0, 0); W16(o, 2, count); W16(o, 4, strOff);
        int i = 0;
        foreach (var kv in recs) {
            byte[] s = Encoding.BigEndianUnicode.GetBytes(kv.Value);
            int r = 6 + i * 12;
            W16(o, r, 3); W16(o, r + 2, 1); W16(o, r + 4, 0x409); W16(o, r + 6, kv.Key);
            W16(o, r + 8, s.Length); W16(o, r + 10, strings.Count);
            strings.AddRange(s);
            i++;
        }
        Tables["name"] = o.Concat(strings).ToArray();
    }
}

public class TtComponent {
    public int Flags, Gid, Arg1, Arg2;
    public double A = 1, B = 0, C = 0, D = 1;
    public byte[] Transform = new byte[0];
    public bool ArgsAreXY { get { return (Flags & 0x0002) != 0; } }
    public TtComponent Clone() { var c = (TtComponent)MemberwiseClone(); c.Transform = (byte[])Transform.Clone(); return c; }
}

public class TtGlyph {
    public List<int> EndPts = new List<int>();
    public List<int> X = new List<int>(), Y = new List<int>();
    public List<bool> On = new List<bool>();
    public List<TtComponent> Components = new List<TtComponent>();
    public byte[] Instructions = new byte[0];
    public bool IsComposite { get { return Components.Count > 0; } }
    public bool IsEmpty { get { return !IsComposite && X.Count == 0; } }

    public TtGlyph Clone() {
        var g = new TtGlyph();
        g.EndPts.AddRange(EndPts); g.X.AddRange(X); g.Y.AddRange(Y); g.On.AddRange(On);
        foreach (var c in Components) g.Components.Add(c.Clone());
        g.Instructions = (byte[])Instructions.Clone();
        return g;
    }

    static double F2Dot14(byte[] b, int o) { return Sfnt.S16(b, o) / 16384.0; }

    public static TtGlyph Parse(byte[] b, int off, int len) {
        var g = new TtGlyph();
        if (len <= 0) return g;
        int nc = Sfnt.S16(b, off);
        int p = off + 10;
        if (nc >= 0) {
            for (int i = 0; i < nc; i++) { g.EndPts.Add(Sfnt.U16(b, p)); p += 2; }
            int n = nc == 0 ? 0 : g.EndPts[nc - 1] + 1;
            int il = Sfnt.U16(b, p); p += 2;
            g.Instructions = new byte[il]; Buffer.BlockCopy(b, p, g.Instructions, 0, il); p += il;
            var flags = new byte[n];
            for (int i = 0; i < n; ) {
                byte f = b[p++]; flags[i++] = f;
                if ((f & 8) != 0) { int r = b[p++]; while (r-- > 0 && i < n) flags[i++] = f; }
            }
            int v = 0;
            for (int i = 0; i < n; i++) {
                byte f = flags[i];
                if ((f & 2) != 0) { int d = b[p++]; v += (f & 0x10) != 0 ? d : -d; }
                else if ((f & 0x10) == 0) { v += Sfnt.S16(b, p); p += 2; }
                g.X.Add(v); g.On.Add((f & 1) != 0);
            }
            v = 0;
            for (int i = 0; i < n; i++) {
                byte f = flags[i];
                if ((f & 4) != 0) { int d = b[p++]; v += (f & 0x20) != 0 ? d : -d; }
                else if ((f & 0x20) == 0) { v += Sfnt.S16(b, p); p += 2; }
                g.Y.Add(v);
            }
        } else {
            int flags;
            do {
                var c = new TtComponent();
                flags = Sfnt.U16(b, p); c.Flags = flags; c.Gid = Sfnt.U16(b, p + 2); p += 4;
                if ((flags & 1) != 0) {
                    if (c.ArgsAreXY) { c.Arg1 = Sfnt.S16(b, p); c.Arg2 = Sfnt.S16(b, p + 2); }
                    else { c.Arg1 = Sfnt.U16(b, p); c.Arg2 = Sfnt.U16(b, p + 2); }
                    p += 4;
                } else {
                    if (c.ArgsAreXY) { c.Arg1 = (sbyte)b[p]; c.Arg2 = (sbyte)b[p + 1]; }
                    else { c.Arg1 = b[p]; c.Arg2 = b[p + 1]; }
                    p += 2;
                }
                int tl = (flags & 8) != 0 ? 2 : (flags & 0x40) != 0 ? 4 : (flags & 0x80) != 0 ? 8 : 0;
                c.Transform = new byte[tl]; Buffer.BlockCopy(b, p, c.Transform, 0, tl);
                if (tl == 2) { c.A = c.D = F2Dot14(b, p); }
                else if (tl == 4) { c.A = F2Dot14(b, p); c.D = F2Dot14(b, p + 2); }
                else if (tl == 8) { c.A = F2Dot14(b, p); c.B = F2Dot14(b, p + 2); c.C = F2Dot14(b, p + 4); c.D = F2Dot14(b, p + 6); }
                p += tl;
                g.Components.Add(c);
            } while ((flags & 0x20) != 0);
            if ((flags & 0x100) != 0) {
                int il = Sfnt.U16(b, p); p += 2;
                g.Instructions = new byte[il]; Buffer.BlockCopy(b, p, g.Instructions, 0, il);
            }
        }
        return g;
    }

    public byte[] Encode(int[] bbox) {
        if (IsEmpty) return new byte[0];
        var o = new List<byte>();
        Action<int> w16 = v => { o.Add((byte)(v >> 8)); o.Add((byte)v); };
        w16(IsComposite ? -1 : EndPts.Count);
        w16(bbox[0]); w16(bbox[1]); w16(bbox[2]); w16(bbox[3]);
        if (!IsComposite) {
            foreach (int e in EndPts) w16(e);
            w16(Instructions.Length); o.AddRange(Instructions);
            int n = X.Count;
            var flags = new byte[n];
            var xs = new List<byte>(); var ys = new List<byte>();
            int px = 0, py = 0;
            for (int i = 0; i < n; i++) {
                int f = On[i] ? 1 : 0;
                int dx = X[i] - px, dy = Y[i] - py; px = X[i]; py = Y[i];
                if (dx == 0) f |= 0x10;
                else if (dx > -256 && dx < 256) { f |= 2; if (dx > 0) f |= 0x10; xs.Add((byte)Math.Abs(dx)); }
                else { xs.Add((byte)(dx >> 8)); xs.Add((byte)dx); }
                if (dy == 0) f |= 0x20;
                else if (dy > -256 && dy < 256) { f |= 4; if (dy > 0) f |= 0x20; ys.Add((byte)Math.Abs(dy)); }
                else { ys.Add((byte)(dy >> 8)); ys.Add((byte)dy); }
                flags[i] = (byte)f;
            }
            for (int i = 0; i < n; ) {
                byte f = flags[i]; int r = 0;
                while (i + r + 1 < n && flags[i + r + 1] == f && r < 255) r++;
                if (r > 0) { o.Add((byte)(f | 8)); o.Add((byte)r); } else o.Add(f);
                i += r + 1;
            }
            o.AddRange(xs); o.AddRange(ys);
        } else {
            for (int i = 0; i < Components.Count; i++) {
                var c = Components[i];
                int f = c.Flags & ~(0x0001 | 0x0020 | 0x0100);
                bool words = c.ArgsAreXY
                    ? (c.Arg1 < -128 || c.Arg1 > 127 || c.Arg2 < -128 || c.Arg2 > 127)
                    : (c.Arg1 > 255 || c.Arg2 > 255);
                if (words) f |= 1;
                if (i < Components.Count - 1) f |= 0x20;
                else if (Instructions.Length > 0) f |= 0x100;
                w16(f); w16(c.Gid);
                if (words) { w16(c.Arg1); w16(c.Arg2); } else { o.Add((byte)c.Arg1); o.Add((byte)c.Arg2); }
                o.AddRange(c.Transform);
            }
            if (Instructions.Length > 0) { w16(Instructions.Length); o.AddRange(Instructions); }
        }
        while (o.Count % 4 != 0) o.Add(0);
        return o.ToArray();
    }
}

// Lê contornos CFF (OpenType .otf, Type 2 charstrings) e devolve glifos TrueType:
// cúbicas viram quadráticas com erro máximo de Tolerance unidades, sentido do contorno invertido.
public class CffReader {
    public static double Tolerance = 1.0;

    class Index { public List<byte[]> Items = new List<byte[]>(); public int End; }

    static Index ReadIndex(byte[] b, int p) {
        var idx = new Index();
        int count = Sfnt.U16(b, p);
        if (count == 0) { idx.End = p + 2; return idx; }
        int offSize = b[p + 2], offStart = p + 3, dataStart = offStart + (count + 1) * offSize - 1;
        Func<int, int> off = i => { int v = 0; for (int k = 0; k < offSize; k++) v = v << 8 | b[offStart + i * offSize + k]; return v; };
        for (int i = 0; i < count; i++) {
            int a = off(i), e = off(i + 1);
            var d = new byte[e - a]; Buffer.BlockCopy(b, dataStart + a, d, 0, e - a);
            idx.Items.Add(d);
        }
        idx.End = dataStart + off(count);
        return idx;
    }

    // DICT: operador (12 x vira 1200+x) -> operandos
    static Dictionary<int, List<double>> ReadDict(byte[] b, int start, int end) {
        var d = new Dictionary<int, List<double>>();
        var ops = new List<double>();
        int p = start;
        while (p < end) {
            int b0 = b[p];
            if (b0 <= 21) {
                int op = b0; p++;
                if (b0 == 12) { op = 1200 + b[p]; p++; }
                d[op] = ops; ops = new List<double>();
            } else if (b0 == 28) { ops.Add((short)(b[p + 1] << 8 | b[p + 2])); p += 3; }
            else if (b0 == 29) { ops.Add(b[p + 1] << 24 | b[p + 2] << 16 | b[p + 3] << 8 | b[p + 4]); p += 5; }
            else if (b0 == 30) {
                p++;
                var sb = new StringBuilder();
                bool done = false;
                while (!done) {
                    int v = b[p++];
                    foreach (int nib in new[] { v >> 4, v & 15 }) {
                        if (nib <= 9) sb.Append((char)('0' + nib));
                        else if (nib == 0xa) sb.Append('.');
                        else if (nib == 0xb) sb.Append('E');
                        else if (nib == 0xc) sb.Append("E-");
                        else if (nib == 0xe) sb.Append('-');
                        else if (nib == 0xf) { done = true; break; }
                    }
                }
                double r; double.TryParse(sb.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out r);
                ops.Add(r);
            } else if (b0 >= 32 && b0 <= 246) { ops.Add(b0 - 139); p++; }
            else if (b0 >= 247 && b0 <= 250) { ops.Add((b0 - 247) * 256 + b[p + 1] + 108); p += 2; }
            else if (b0 >= 251 && b0 <= 254) { ops.Add(-(b0 - 251) * 256 - b[p + 1] - 108); p += 2; }
            else p++;
        }
        return d;
    }

    static int Bias(int n) { return n < 1240 ? 107 : n < 33900 ? 1131 : 32768; }

    static Index LocalSubrs(byte[] cff, List<double> priv) {
        if (priv == null || priv.Count < 2) return new Index();
        int size = (int)priv[0], off = (int)priv[1];
        var pd = ReadDict(cff, off, off + size);
        return pd.ContainsKey(19) ? ReadIndex(cff, off + (int)pd[19][0]) : new Index();
    }

    public static List<TtGlyph> ReadGlyphs(byte[] cff) {
        var names = ReadIndex(cff, cff[2]);
        var tops = ReadIndex(cff, names.End);
        var strings = ReadIndex(cff, tops.End);
        var gsubrs = ReadIndex(cff, strings.End);
        var top = ReadDict(tops.Items[0], 0, tops.Items[0].Length);
        var cs = ReadIndex(cff, (int)top[17][0]);
        int n = cs.Items.Count;

        var lsubrs = new List<Index>();
        var fdOf = new int[n];
        if (top.ContainsKey(1236)) {
            // Fonte CID: cada glifo escolhe um Private DICT pelo FDSelect
            var fdArray = ReadIndex(cff, (int)top[1236][0]);
            foreach (var item in fdArray.Items) {
                var fd = ReadDict(item, 0, item.Length);
                lsubrs.Add(LocalSubrs(cff, fd.ContainsKey(18) ? fd[18] : null));
            }
            int p = (int)top[1237][0], fmt = cff[p];
            if (fmt == 0) for (int g = 0; g < n; g++) fdOf[g] = cff[p + 1 + g];
            else if (fmt == 3) {
                int ranges = Sfnt.U16(cff, p + 1);
                for (int r = 0; r < ranges; r++) {
                    int first = Sfnt.U16(cff, p + 3 + r * 3), fdi = cff[p + 5 + r * 3];
                    int next = Sfnt.U16(cff, p + 3 + (r + 1) * 3);
                    for (int g = first; g < next && g < n; g++) fdOf[g] = fdi;
                }
            }
        } else lsubrs.Add(LocalSubrs(cff, top.ContainsKey(18) ? top[18] : null));

        var res = new List<TtGlyph>(n);
        for (int g = 0; g < n; g++) {
            var it = new Interp { G = gsubrs.Items, L = lsubrs[fdOf[g]].Items };
            it.GBias = Bias(it.G.Count); it.LBias = Bias(it.L.Count);
            it.Exec(cs.Items[g], 0);
            it.Close();
            res.Add(it.Glyph);
        }
        return res;
    }

    class Interp {
        public List<byte[]> G, L;
        public int GBias, LBias;
        public TtGlyph Glyph = new TtGlyph();
        List<double> st = new List<double>();
        List<double[]> pts = new List<double[]>(); // x, y, on(1/0) do contorno atual
        double x, y;
        int stems;
        bool haveWidth, done;

        void Width(bool has) { if (!haveWidth) { if (has && st.Count > 0) st.RemoveAt(0); haveWidth = true; } }
        void MoveTo() { Close(); pts.Add(new[] { x, y, 1.0 }); }
        void Line() { pts.Add(new[] { x, y, 1.0 }); }

        void Curve(double dx1, double dy1, double dx2, double dy2, double dx3, double dy3) {
            double x0 = x, y0 = y, x1 = x0 + dx1, y1 = y0 + dy1, x2 = x1 + dx2, y2 = y1 + dy2, x3 = x2 + dx3, y3 = y2 + dy3;
            double ex = x3 - 3 * x2 + 3 * x1 - x0, ey = y3 - 3 * y2 + 3 * y1 - y0;
            double err = Math.Sqrt(ex * ex + ey * ey) * Math.Sqrt(3) / 36;
            int segs = Math.Min(16, Math.Max(1, (int)Math.Ceiling(Math.Pow(err / Tolerance, 1.0 / 3))));
            for (int i = 0; i < segs; i++) {
                double t0 = (double)i / segs, t1 = (double)(i + 1) / segs, h = (t1 - t0) / 3;
                double[] q0 = Bez(x0, y0, x1, y1, x2, y2, x3, y3, t0), q3 = Bez(x0, y0, x1, y1, x2, y2, x3, y3, t1);
                double[] d0 = Der(x0, y0, x1, y1, x2, y2, x3, y3, t0), d3 = Der(x0, y0, x1, y1, x2, y2, x3, y3, t1);
                double q1x = q0[0] + d0[0] * h, q1y = q0[1] + d0[1] * h, q2x = q3[0] - d3[0] * h, q2y = q3[1] - d3[1] * h;
                pts.Add(new[] { (3 * (q1x + q2x) - q0[0] - q3[0]) / 4, (3 * (q1y + q2y) - q0[1] - q3[1]) / 4, 0.0 });
                pts.Add(new[] { q3[0], q3[1], 1.0 });
            }
            x = x3; y = y3;
        }

        static double[] Bez(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3, double t) {
            double u = 1 - t;
            return new[] { u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
                           u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3 };
        }
        static double[] Der(double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3, double t) {
            double u = 1 - t;
            return new[] { 3 * u * u * (x1 - x0) + 6 * u * t * (x2 - x1) + 3 * t * t * (x3 - x2),
                           3 * u * u * (y1 - y0) + 6 * u * t * (y2 - y1) + 3 * t * t * (y3 - y2) };
        }

        // Fecha o contorno: tira o ponto final repetido e inverte o sentido (CFF anti-horário -> TrueType horário)
        public void Close() {
            if (pts.Count > 1) {
                var a = pts[0]; var z = pts[pts.Count - 1];
                if (z[2] == 1 && Math.Round(z[0]) == Math.Round(a[0]) && Math.Round(z[1]) == Math.Round(a[1])) pts.RemoveAt(pts.Count - 1);
            }
            if (pts.Count >= 2) {
                var rev = new List<double[]> { pts[0] };
                for (int i = pts.Count - 1; i >= 1; i--) rev.Add(pts[i]);
                foreach (var q in rev) {
                    Glyph.X.Add((int)Math.Round(q[0])); Glyph.Y.Add((int)Math.Round(q[1])); Glyph.On.Add(q[2] == 1);
                }
                Glyph.EndPts.Add(Glyph.X.Count - 1);
            }
            pts.Clear();
        }

        public void Exec(byte[] c, int depth) {
            if (depth > 10) return;
            int p = 0;
            while (p < c.Length && !done) {
                int b0 = c[p];
                if (b0 >= 32 || b0 == 28) {
                    if (b0 == 28) { st.Add((short)(c[p + 1] << 8 | c[p + 2])); p += 3; }
                    else if (b0 <= 246) { st.Add(b0 - 139); p++; }
                    else if (b0 <= 250) { st.Add((b0 - 247) * 256 + c[p + 1] + 108); p += 2; }
                    else if (b0 <= 254) { st.Add(-(b0 - 251) * 256 - c[p + 1] - 108); p += 2; }
                    else { st.Add((c[p + 1] << 24 | c[p + 2] << 16 | c[p + 3] << 8 | c[p + 4]) / 65536.0); p += 5; }
                    continue;
                }
                p++;
                int k = st.Count;
                switch (b0) {
                    case 1: case 3: case 18: case 23:
                        Width(k % 2 != 0); stems += st.Count / 2; st.Clear(); break;
                    case 19: case 20:
                        Width(k % 2 != 0); stems += st.Count / 2; st.Clear(); p += (stems + 7) / 8; break;
                    case 21: Width(k > 2); x += st[st.Count - 2]; y += st[st.Count - 1]; MoveTo(); st.Clear(); break;
                    case 22: Width(k > 1); x += st[st.Count - 1]; MoveTo(); st.Clear(); break;
                    case 4: Width(k > 1); y += st[st.Count - 1]; MoveTo(); st.Clear(); break;
                    case 5:
                        for (int i = 0; i + 1 < k; i += 2) { x += st[i]; y += st[i + 1]; Line(); }
                        st.Clear(); break;
                    case 6: case 7: {
                        bool hz = b0 == 6;
                        for (int i = 0; i < k; i++) { if (hz) x += st[i]; else y += st[i]; Line(); hz = !hz; }
                        st.Clear(); break;
                    }
                    case 8:
                        for (int i = 0; i + 5 < k; i += 6) Curve(st[i], st[i + 1], st[i + 2], st[i + 3], st[i + 4], st[i + 5]);
                        st.Clear(); break;
                    case 24: {
                        int i = 0;
                        for (; i + 5 < k - 2; i += 6) Curve(st[i], st[i + 1], st[i + 2], st[i + 3], st[i + 4], st[i + 5]);
                        x += st[i]; y += st[i + 1]; Line();
                        st.Clear(); break;
                    }
                    case 25: {
                        int i = 0;
                        for (; i + 1 < k - 6; i += 2) { x += st[i]; y += st[i + 1]; Line(); }
                        Curve(st[i], st[i + 1], st[i + 2], st[i + 3], st[i + 4], st[i + 5]);
                        st.Clear(); break;
                    }
                    case 26: {
                        int i = 0; double dx1 = 0;
                        if (k % 2 == 1) { dx1 = st[0]; i = 1; }
                        for (; i + 3 < k; i += 4) { Curve(dx1, st[i], st[i + 1], st[i + 2], 0, st[i + 3]); dx1 = 0; }
                        st.Clear(); break;
                    }
                    case 27: {
                        int i = 0; double dy1 = 0;
                        if (k % 2 == 1) { dy1 = st[0]; i = 1; }
                        for (; i + 3 < k; i += 4) { Curve(st[i], dy1, st[i + 1], st[i + 2], st[i + 3], 0); dy1 = 0; }
                        st.Clear(); break;
                    }
                    case 30: case 31: {
                        bool hStart = b0 == 31;
                        for (int i = 0; i + 3 < k; i += 4) {
                            double extra = (k - i == 5) ? st[i + 4] : 0;
                            if (hStart) Curve(st[i], 0, st[i + 1], st[i + 2], extra, st[i + 3]);
                            else Curve(0, st[i], st[i + 1], st[i + 2], st[i + 3], extra);
                            hStart = !hStart;
                        }
                        st.Clear(); break;
                    }
                    case 10: case 29: {
                        var subrs = b0 == 10 ? L : G;
                        int idx = (int)st[st.Count - 1] + (b0 == 10 ? LBias : GBias);
                        st.RemoveAt(st.Count - 1);
                        if (idx >= 0 && idx < subrs.Count) Exec(subrs[idx], depth + 1);
                        break;
                    }
                    case 11: return;
                    case 14: Width(k == 1 || k == 5); Close(); done = true; return;
                    case 12: {
                        int b1 = c[p++];
                        var s = st;
                        if (b1 == 35 && k >= 12) {
                            Curve(s[0], s[1], s[2], s[3], s[4], s[5]); Curve(s[6], s[7], s[8], s[9], s[10], s[11]);
                        } else if (b1 == 34 && k >= 7) {
                            Curve(s[0], 0, s[1], s[2], s[3], 0); Curve(s[4], 0, s[5], -s[2], s[6], 0);
                        } else if (b1 == 36 && k >= 9) {
                            Curve(s[0], s[1], s[2], s[3], s[4], 0); Curve(s[5], 0, s[6], s[7], s[8], -(s[1] + s[3] + s[7]));
                        } else if (b1 == 37 && k >= 11) {
                            double sx = s[0] + s[2] + s[4] + s[6] + s[8], sy = s[1] + s[3] + s[5] + s[7] + s[9];
                            Curve(s[0], s[1], s[2], s[3], s[4], s[5]);
                            if (Math.Abs(sx) > Math.Abs(sy)) Curve(s[6], s[7], s[8], s[9], s[10], -sy);
                            else Curve(s[6], s[7], s[8], s[9], -sx, s[10]);
                        }
                        st.Clear(); break;
                    }
                    default: st.Clear(); break;
                }
            }
        }
    }
}

public class TtFont {
    public Sfnt S;
    public List<TtGlyph> Glyphs = new List<TtGlyph>();
    public List<int> Adv = new List<int>(), Lsb = new List<int>();
    public SortedDictionary<int, int> Cmap = new SortedDictionary<int, int>();
    int loadedCount;

    public int Upm { get { return Sfnt.U16(S.Get("head"), 18); } }

    // Abre .ttf; .otf (contornos CFF) é convertido para TrueType na hora
    public static TtFont Load(string path) {
        var f = new TtFont();
        f.S = Sfnt.Load(path);
        byte[] maxp = f.S.Get("maxp");
        byte[] hhea = f.S.Get("hhea"), hmtx = f.S.Get("hmtx");
        int n = Sfnt.U16(maxp, 4);
        if (f.S.Has("glyf")) {
            byte[] head = f.S.Get("head"), loca = f.S.Get("loca"), glyf = f.S.Get("glyf");
            bool longLoca = Sfnt.S16(head, 50) == 1;
            for (int i = 0; i < n; i++) {
                int a = longLoca ? (int)Sfnt.U32(loca, i * 4) : Sfnt.U16(loca, i * 2) * 2;
                int b = longLoca ? (int)Sfnt.U32(loca, i * 4 + 4) : Sfnt.U16(loca, i * 2 + 2) * 2;
                f.Glyphs.Add(TtGlyph.Parse(glyf, a, b - a));
            }
        } else if (f.S.Has("CFF ")) {
            f.Glyphs.AddRange(CffReader.ReadGlyphs(f.S.Get("CFF ")));
            if (f.Glyphs.Count != n) throw new Exception(path + ": CFF com número de glifos diferente do maxp");
            // Vira uma fonte TrueType: maxp 1.0 (32 bytes), sem CFF, glyf/loca criadas no Save
            var mp = new byte[32];
            Sfnt.W32(mp, 0, 0x00010000); Sfnt.W16(mp, 4, n); Sfnt.W16(mp, 14, 2);
            f.S.Tables["maxp"] = mp;
            f.S.Tables.Remove("CFF "); f.S.Tables.Remove("VORG");
            f.S.Version = 0x00010000;
            f.SetSmoothGasp();
        } else throw new Exception(path + ": fonte sem contornos glyf nem CFF");
        int nh = Sfnt.U16(hhea, 34);
        for (int i = 0; i < n; i++) {
            if (i < nh) { f.Adv.Add(Sfnt.U16(hmtx, i * 4)); f.Lsb.Add(Sfnt.S16(hmtx, i * 4 + 2)); }
            else { f.Adv.Add(f.Adv[nh - 1]); f.Lsb.Add(Sfnt.S16(hmtx, nh * 4 + (i - nh) * 2)); }
        }
        f.loadedCount = n;
        f.ParseCmap();
        return f;
    }

    void ParseCmap() {
        byte[] c = S.Get("cmap");
        int nt = Sfnt.U16(c, 2), best4 = -1, best12 = -1;
        for (int i = 0; i < nt; i++) {
            int pid = Sfnt.U16(c, 4 + i * 8), eid = Sfnt.U16(c, 6 + i * 8), off = (int)Sfnt.U32(c, 8 + i * 8);
            int fmt = Sfnt.U16(c, off);
            bool unicode = pid == 0 || (pid == 3 && (eid == 1 || eid == 10));
            if (fmt == 12 && unicode) best12 = off;
            if (fmt == 4 && unicode) best4 = off;
        }
        if (best12 >= 0) {
            int o = best12;
            uint groups = Sfnt.U32(c, o + 12);
            for (int g = 0; g < groups; g++) {
                int start = (int)Sfnt.U32(c, o + 16 + g * 12), end = (int)Sfnt.U32(c, o + 20 + g * 12);
                int gid = (int)Sfnt.U32(c, o + 24 + g * 12);
                for (int cp = start; cp <= end; cp++) if (gid + cp - start != 0) Cmap[cp] = gid + cp - start;
            }
        } else if (best4 >= 0) {
            int o = best4, segX2 = Sfnt.U16(c, o + 6), seg = segX2 / 2;
            for (int s = 0; s < seg; s++) {
                int end = Sfnt.U16(c, o + 14 + s * 2), start = Sfnt.U16(c, o + 16 + segX2 + s * 2);
                int delta = Sfnt.S16(c, o + 16 + segX2 * 2 + s * 2);
                int roPos = o + 16 + segX2 * 3 + s * 2, ro = Sfnt.U16(c, roPos);
                for (int cp = start; cp <= end && cp != 0xFFFF; cp++) {
                    int gid;
                    if (ro == 0) gid = (cp + delta) & 0xFFFF;
                    else {
                        int gi = Sfnt.U16(c, roPos + ro + (cp - start) * 2);
                        gid = gi == 0 ? 0 : (gi + delta) & 0xFFFF;
                    }
                    if (gid != 0) Cmap[cp] = gid;
                }
            }
        } else throw new Exception("fonte sem cmap Unicode");
    }

    // Glifo com componentes resolvidos em contornos simples (coordenadas absolutas)
    public TtGlyph Flatten(int gid) {
        var r = new TtGlyph();
        FlattenInto(gid, 1, 0, 0, 1, 0, 0, r, 0);
        return r;
    }

    void FlattenInto(int gid, double a, double b, double c, double d, double dx, double dy, TtGlyph r, int depth) {
        if (depth > 8 || gid < 0 || gid >= Glyphs.Count) return;
        var g = Glyphs[gid];
        if (g.IsComposite) {
            foreach (var k in g.Components) {
                double ox = k.ArgsAreXY ? k.Arg1 : 0, oy = k.ArgsAreXY ? k.Arg2 : 0;
                FlattenInto(k.Gid,
                    a * k.A + c * k.B, b * k.A + d * k.B,
                    a * k.C + c * k.D, b * k.C + d * k.D,
                    a * ox + c * oy + dx, b * ox + d * oy + dy, r, depth + 1);
            }
        } else {
            int baseIdx = r.X.Count;
            for (int i = 0; i < g.X.Count; i++) {
                r.X.Add((int)Math.Round(a * g.X[i] + c * g.Y[i] + dx));
                r.Y.Add((int)Math.Round(b * g.X[i] + d * g.Y[i] + dy));
                r.On.Add(g.On[i]);
            }
            foreach (int e in g.EndPts) r.EndPts.Add(e + baseIdx);
        }
    }

    // xMin, yMin, xMax, yMax ou null se vazio
    public int[] Bounds(int gid) {
        var g = Glyphs[gid];
        var f = g.IsComposite ? Flatten(gid) : g;
        if (f.X.Count == 0) return null;
        return new[] { f.X.Min(), f.Y.Min(), f.X.Max(), f.Y.Max() };
    }

    int Depth(int gid, int level) {
        var g = Glyphs[gid];
        if (!g.IsComposite || level > 8) return level;
        int m = level;
        foreach (var k in g.Components) if (k.Gid < Glyphs.Count) m = Math.Max(m, Depth(k.Gid, level + 1));
        return m;
    }

    public int CodepointGlyph(int cp) { int g; return Cmap.TryGetValue(cp, out g) ? g : -1; }

    // Pontos em que o contorno cruza a linha horizontal y (para medir espessura de haste)
    public List<double> Crossings(int gid, double y) {
        var g = Flatten(gid);
        var xs = new List<double>();
        int start = 0;
        foreach (int end in g.EndPts) {
            for (int i = start; i <= end; i++) {
                int j = i == end ? start : i + 1;
                double y1 = g.Y[i], y2 = g.Y[j];
                if ((y1 <= y && y2 > y) || (y2 <= y && y1 > y))
                    xs.Add(g.X[i] + (y - y1) * (g.X[j] - g.X[i]) / (y2 - y1));
            }
            start = end + 1;
        }
        xs.Sort();
        return xs;
    }

    // Códigos usados pelos ícones Nerd Fonts: área de uso privado (E000-F8FF), planos 15/16
    // (Material Design) e os símbolos de energia/coração/raio fora dessas faixas.
    public List<int> NerdCodepoints() {
        var extra = new HashSet<int> { 0x23FB, 0x23FC, 0x23FD, 0x23FE, 0x2665, 0x26A1, 0x2B58 };
        return Cmap.Keys.Where(cp => (cp >= 0xE000 && cp <= 0xF8FF) || cp >= 0xF0000 || extra.Contains(cp)).ToList();
    }

    // Copia ícones de uma fonte Nerd Font Mono, desfazendo o encolhimento para a célula:
    // cada ícone que cabia num quadrado de boxSrc vira um quadrado de boxDst; ícones largos
    // (achatados pela célula) crescem até a altura normal, no máximo 2x a largura da célula.
    public int MergeIcons(TtFont src, double boxSrc, double boxDst, double maxH, double centerY, double pad) {
        int added = 0;
        foreach (int cp in src.NerdCodepoints()) {
            if (Cmap.ContainsKey(cp)) continue;
            int sg = src.CodepointGlyph(cp);
            int[] bb = src.Bounds(sg);
            if (bb == null) continue;
            double w = Math.Max(1, bb[2] - bb[0]), h = Math.Max(1, bb[3] - bb[1]);
            double s = boxDst / boxSrc;
            if (w >= boxSrc * 0.97 && h < w) s *= Math.Min(boxSrc / h, 2.0 * boxSrc / w);
            s = Math.Min(s, maxH / h);
            double dx = pad - bb[0] * s, dy = centerY - (bb[1] + bb[3]) / 2.0 * s;
            int g = ImportGlyph(src, sg, s, dx, dy, (int)Math.Round(w * s + 2 * pad));
            Glyphs[g].Instructions = new byte[0];
            Cmap[cp] = g;
            added++;
        }
        return added;
    }

    // Altura do centro de massa da tinta de um texto (centroide da área preenchida dos contornos,
    // buracos descontados pelo sinal da área). Mede onde o "peso visual" do texto fica.
    public double InkCentroidY(string text) {
        double area = 0, moment = 0;
        foreach (char ch in text) {
            int gid = CodepointGlyph(ch);
            if (gid < 0) continue;
            var g = Flatten(gid);
            int start = 0;
            foreach (int end in g.EndPts) {
                for (int i = start; i <= end; i++) {
                    int j = i == end ? start : i + 1;
                    double cross = (double)g.X[i] * g.Y[j] - (double)g.X[j] * g.Y[i];
                    area += cross / 2;
                    moment += (g.Y[i] + g.Y[j]) * cross / 6;
                }
                start = end + 1;
            }
        }
        return area == 0 ? 0 : moment / area;
    }

    // Menor y e maior y dos caracteres entre os códigos first e last (ex.: 0x20-0xFF = Latin-1)
    public int[] TextVerticalExtent(int first, int last) {
        int yMin = 0, yMax = 0;
        foreach (var kv in Cmap) {
            if (kv.Key < first || kv.Key > last) continue;
            int[] bb = Bounds(kv.Value);
            if (bb != null) { yMin = Math.Min(yMin, bb[1]); yMax = Math.Max(yMax, bb[3]); }
        }
        return new[] { yMin, yMax };
    }

    // Sem hinting: pede suavização em todos os tamanhos
    public void SetSmoothGasp() {
        var gasp = new byte[8];
        Sfnt.W16(gasp, 0, 1); Sfnt.W16(gasp, 2, 1); Sfnt.W16(gasp, 4, 0xFFFF); Sfnt.W16(gasp, 6, 0x000F);
        S.Tables["gasp"] = gasp;
    }

    // ------------------------------------------------------------ transformações

    // Fonte monoespaçada: troca a largura de todos os caracteres, centralizando o desenho na
    // célula nova. Glifos compostos acompanham os componentes, que já foram deslocados.
    public void SetMonospaceAdvance(int advance) {
        for (int i = 0; i < Glyphs.Count; i++) {
            if (Adv[i] <= 0) continue;
            int dx = (advance - Adv[i]) / 2;
            var g = Glyphs[i];
            if (!g.IsComposite) for (int p = 0; p < g.X.Count; p++) g.X[p] += dx;
            Adv[i] = advance;
        }
    }

    // Remove o contorno de menor área de um glifo simples (ex.: o ponto dentro do zero)
    public bool RemoveSmallestContour(int gid) {
        var g = Glyphs[gid];
        if (g.IsComposite || g.EndPts.Count < 2) return false;
        int best = -1, start = 0; double bestArea = double.MaxValue;
        for (int c = 0; c < g.EndPts.Count; c++) {
            int end = g.EndPts[c]; double a = 0;
            for (int i = start; i <= end; i++) {
                int j = i == end ? start : i + 1;
                a += (double)g.X[i] * g.Y[j] - (double)g.X[j] * g.Y[i];
            }
            if (Math.Abs(a) < bestArea) { bestArea = Math.Abs(a); best = c; }
            start = end + 1;
        }
        int from = best == 0 ? 0 : g.EndPts[best - 1] + 1, count = g.EndPts[best] - from + 1;
        g.X.RemoveRange(from, count); g.Y.RemoveRange(from, count); g.On.RemoveRange(from, count);
        g.EndPts.RemoveAt(best);
        for (int c = best; c < g.EndPts.Count; c++) g.EndPts[c] -= count;
        g.Instructions = new byte[0];
        return true;
    }

    public void StripInstructions() {
        foreach (var g in Glyphs) g.Instructions = new byte[0];
    }

    // Engrossa (strength > 0) ou afina (< 0) os traços, como FT_Outline_EmboldenXY do FreeType.
    // A base e a lateral esquerda ficam no lugar; a largura cresce strengthX e a altura strengthY.
    public void Embolden(double strengthX, double strengthY) { Embolden(strengthX, strengthY, false); }

    // keepAdvance: engrossa para os dois lados sem mudar a largura do caractere (fontes monoespaçadas)
    public void Embolden(double strengthX, double strengthY, bool keepAdvance) {
        double xs = strengthX / 2, ys = strengthY / 2;
        double shiftX = keepAdvance ? 0 : xs;
        for (int gi = 0; gi < Glyphs.Count; gi++) {
            var g = Glyphs[gi];
            if (!g.IsComposite && g.X.Count > 0) {
                double area = 0;
                int start = 0;
                foreach (int end in g.EndPts) {
                    for (int i = start; i <= end; i++) {
                        int j = i == end ? start : i + 1;
                        area += (double)g.X[i] * g.Y[j] - (double)g.X[j] * g.Y[i];
                    }
                    start = end + 1;
                }
                bool tt = area < 0; // horário = orientação TrueType
                var nx = new int[g.X.Count]; var ny = new int[g.X.Count];
                start = 0;
                foreach (int end in g.EndPts) {
                    int cnt = end - start + 1;
                    for (int i = start; i <= end; i++) {
                        double sx = 0, sy = 0;
                        int prev = i, next = i;
                        for (int k = 1; k < cnt; k++) { prev = start + ((i - start - k) % cnt + cnt) % cnt; if (g.X[prev] != g.X[i] || g.Y[prev] != g.Y[i]) break; }
                        for (int k = 1; k < cnt; k++) { next = start + (i - start + k) % cnt; if (g.X[next] != g.X[i] || g.Y[next] != g.Y[i]) break; }
                        double inx = g.X[i] - g.X[prev], iny = g.Y[i] - g.Y[prev];
                        double outx = g.X[next] - g.X[i], outy = g.Y[next] - g.Y[i];
                        double lin = Math.Sqrt(inx * inx + iny * iny), lout = Math.Sqrt(outx * outx + outy * outy);
                        if (lin > 0 && lout > 0) {
                            inx /= lin; iny /= lin; outx /= lout; outy /= lout;
                            double d = inx * outx + iny * outy;
                            if (d > -0.9375) {
                                d += 1;
                                double shx = iny + outy, shy = inx + outx;
                                if (tt) shx = -shx; else shy = -shy;
                                double q = outx * iny - outy * inx;
                                if (tt) q = -q;
                                double l = Math.Min(lin, lout);
                                sx = (Math.Abs(xs) * q <= l * d) ? shx * xs / d : shx * l / q * Math.Sign(xs);
                                sy = (Math.Abs(ys) * q <= l * d) ? shy * ys / d : shy * l / q * Math.Sign(ys);
                            }
                        }
                        nx[i] = (int)Math.Round(g.X[i] + shiftX + sx);
                        ny[i] = (int)Math.Round(g.Y[i] + ys + sy);
                    }
                    start = end + 1;
                }
                for (int i = 0; i < nx.Length; i++) { g.X[i] = nx[i]; g.Y[i] = ny[i]; }
            }
            if (Adv[gi] > 0 && !keepAdvance) Adv[gi] = (int)Math.Round(Adv[gi] + strengthX);
        }
    }

    // Itálico sintético (oblíquo): inclina em torno da altura pivotY
    public void Oblique(double degrees, double pivotY) {
        double t = Math.Tan(degrees * Math.PI / 180);
        foreach (var g in Glyphs) {
            if (g.IsComposite) {
                foreach (var k in g.Components) if (k.ArgsAreXY) k.Arg1 = (int)Math.Round(k.Arg1 + k.Arg2 * t);
            } else {
                for (int i = 0; i < g.X.Count; i++) g.X[i] = (int)Math.Round(g.X[i] + (g.Y[i] - pivotY) * t);
            }
        }
        byte[] post = S.Get("post");
        Sfnt.W32(post, 4, (uint)(int)Math.Round(-degrees * 65536));
        byte[] hhea = S.Get("hhea");
        Sfnt.W16(hhea, 18, 1000); Sfnt.W16(hhea, 20, (int)Math.Round(1000 * t));
    }

    // Copia um glifo de outra fonte (componentes resolvidos), escalado e deslocado
    public int ImportGlyph(TtFont src, int sgid, double scale, double dx, double dy, int advance) {
        var g = src.Flatten(sgid);
        for (int i = 0; i < g.X.Count; i++) {
            g.X[i] = (int)Math.Round(g.X[i] * scale + dx);
            g.Y[i] = (int)Math.Round(g.Y[i] * scale + dy);
        }
        Glyphs.Add(g); Adv.Add(advance); Lsb.Add(0);
        return Glyphs.Count - 1;
    }

    public void SetStyle(int weight, bool bold, bool italic) {
        byte[] os2 = S.Get("OS/2"), head = S.Get("head");
        Sfnt.W16(os2, 4, weight);
        int sel = Sfnt.U16(os2, 62) & ~(0x01 | 0x20 | 0x40);
        if (italic) sel |= 0x01;
        if (bold) sel |= 0x20;
        if (!italic && !bold) sel |= 0x40;
        Sfnt.W16(os2, 62, sel);
        Sfnt.W16(head, 44, (bold ? 1 : 0) | (italic ? 2 : 0));
    }

    // ------------------------------------------------------------ gravação

    byte[] BuildCmap() {
        // formato 4 (BMP): segmentos de códigos seguidos com delta constante
        var segs = new List<int[]>(); // start, end, delta
        foreach (var kv in Cmap) {
            if (kv.Key >= 0xFFFF) break;
            var last = segs.Count > 0 ? segs[segs.Count - 1] : null;
            if (last != null && last[1] + 1 == kv.Key && last[2] == kv.Value - kv.Key) last[1] = kv.Key;
            else segs.Add(new[] { kv.Key, kv.Key, kv.Value - kv.Key });
        }
        segs.Add(new[] { 0xFFFF, 0xFFFF, 1 });
        int segX2 = segs.Count * 2, len4 = 16 + segX2 * 4;
        if (len4 > 0xFFFF) throw new Exception("cmap formato 4 grande demais");
        int sr = 2, es = 0; while (sr * 2 <= segX2) { sr *= 2; es++; }
        var f4 = new byte[len4];
        Sfnt.W16(f4, 0, 4); Sfnt.W16(f4, 2, len4); Sfnt.W16(f4, 6, segX2);
        Sfnt.W16(f4, 8, sr); Sfnt.W16(f4, 10, es); Sfnt.W16(f4, 12, segX2 - sr);
        for (int s = 0; s < segs.Count; s++) {
            Sfnt.W16(f4, 14 + s * 2, segs[s][1]);
            Sfnt.W16(f4, 16 + segX2 + s * 2, segs[s][0]);
            Sfnt.W16(f4, 16 + segX2 * 2 + s * 2, segs[s][2] & 0xFFFF);
        }
        // formato 12: tudo, inclusive acima de U+FFFF (ícones Material Design ficam no plano 15)
        var groups = new List<int[]>(); // start, end, startGid
        foreach (var kv in Cmap) {
            var last = groups.Count > 0 ? groups[groups.Count - 1] : null;
            if (last != null && last[1] + 1 == kv.Key && last[2] + (kv.Key - last[0]) == kv.Value) last[1] = kv.Key;
            else groups.Add(new[] { kv.Key, kv.Key, kv.Value });
        }
        int len12 = 16 + groups.Count * 12;
        var f12 = new byte[len12];
        Sfnt.W16(f12, 0, 12); Sfnt.W32(f12, 4, (uint)len12); Sfnt.W32(f12, 12, (uint)groups.Count);
        for (int g = 0; g < groups.Count; g++) {
            Sfnt.W32(f12, 16 + g * 12, (uint)groups[g][0]);
            Sfnt.W32(f12, 20 + g * 12, (uint)groups[g][1]);
            Sfnt.W32(f12, 24 + g * 12, (uint)groups[g][2]);
        }
        var o = new byte[20 + len4 + len12];
        Sfnt.W16(o, 2, 2);
        Sfnt.W16(o, 4, 3); Sfnt.W16(o, 6, 1); Sfnt.W32(o, 8, 20);
        Sfnt.W16(o, 12, 3); Sfnt.W16(o, 14, 10); Sfnt.W32(o, 16, (uint)(20 + len4));
        Buffer.BlockCopy(f4, 0, o, 20, len4);
        Buffer.BlockCopy(f12, 0, o, 20 + len4, len12);
        return o;
    }

    public void Save(string path) {
        int n = Glyphs.Count;
        var glyf = new List<byte>();
        var loca = new byte[(n + 1) * 4];
        int hxMin = int.MaxValue, hyMin = int.MaxValue, hxMax = int.MinValue, hyMax = int.MinValue;
        int advMax = 0, minL = int.MaxValue, minR = int.MaxValue, maxExt = int.MinValue;
        int maxPts = 0, maxCont = 0, maxCPts = 0, maxCCont = 0, maxElems = 0, maxDepth = 0;
        long avgSum = 0; int avgN = 0;
        for (int i = 0; i < n; i++) {
            var g = Glyphs[i];
            int[] bb = Bounds(i);
            if (bb != null) {
                Lsb[i] = bb[0];
                hxMin = Math.Min(hxMin, bb[0]); hyMin = Math.Min(hyMin, bb[1]);
                hxMax = Math.Max(hxMax, bb[2]); hyMax = Math.Max(hyMax, bb[3]);
                minL = Math.Min(minL, bb[0]); minR = Math.Min(minR, Adv[i] - bb[2]); maxExt = Math.Max(maxExt, bb[2]);
            } else Lsb[i] = 0;
            Sfnt.W32(loca, i * 4, (uint)glyf.Count);
            glyf.AddRange(g.Encode(bb ?? new int[4]));
            advMax = Math.Max(advMax, Adv[i]);
            if (Adv[i] > 0) { avgSum += Adv[i]; avgN++; }
            if (g.IsComposite) {
                var fl = Flatten(i);
                maxCPts = Math.Max(maxCPts, fl.X.Count); maxCCont = Math.Max(maxCCont, fl.EndPts.Count);
                maxElems = Math.Max(maxElems, g.Components.Count); maxDepth = Math.Max(maxDepth, Depth(i, 0));
            } else { maxPts = Math.Max(maxPts, g.X.Count); maxCont = Math.Max(maxCont, g.EndPts.Count); }
        }
        Sfnt.W32(loca, n * 4, (uint)glyf.Count);
        S.Tables["glyf"] = glyf.ToArray();
        S.Tables["loca"] = loca;

        byte[] head = S.Get("head");
        Sfnt.W16(head, 50, 1);
        if (hxMin != int.MaxValue) { Sfnt.W16(head, 36, hxMin); Sfnt.W16(head, 38, hyMin); Sfnt.W16(head, 40, hxMax); Sfnt.W16(head, 42, hyMax); }

        var hmtx = new byte[n * 4];
        for (int i = 0; i < n; i++) { Sfnt.W16(hmtx, i * 4, Adv[i]); Sfnt.W16(hmtx, i * 4 + 2, Lsb[i]); }
        S.Tables["hmtx"] = hmtx;
        byte[] hhea = S.Get("hhea");
        Sfnt.W16(hhea, 34, n); Sfnt.W16(hhea, 10, advMax);
        if (minL != int.MaxValue) { Sfnt.W16(hhea, 12, minL); Sfnt.W16(hhea, 14, minR); Sfnt.W16(hhea, 16, maxExt); }

        byte[] maxp = S.Get("maxp");
        Sfnt.W16(maxp, 4, n);
        if (maxp.Length >= 32) {
            Sfnt.W16(maxp, 6, maxPts); Sfnt.W16(maxp, 8, maxCont);
            Sfnt.W16(maxp, 10, maxCPts); Sfnt.W16(maxp, 12, maxCCont);
            Sfnt.W16(maxp, 28, maxElems); Sfnt.W16(maxp, 30, maxDepth);
        }
        if (S.Has("OS/2") && avgN > 0) Sfnt.W16(S.Get("OS/2"), 2, (int)(avgSum / avgN));

        S.Tables["cmap"] = BuildCmap();
        if (S.Has("OS/2")) {
            byte[] os2 = S.Get("OS/2");
            Sfnt.W16(os2, 64, Math.Min(Cmap.Keys.First(), 0xFFFF));
            Sfnt.W16(os2, 66, Math.Min(Cmap.Keys.Last(), 0xFFFF));
        }
        // Nomes de glifo da 'post' v2 não cobrem glifos novos
        byte[] post = S.Get("post");
        if (n != loadedCount && Sfnt.U32(post, 0) == 0x00020000) {
            var p3 = new byte[32]; Buffer.BlockCopy(post, 0, p3, 0, 32); Sfnt.W32(p3, 0, 0x00030000);
            S.Tables["post"] = p3;
        }
        foreach (var t in new[] { "hdmx", "LTSH", "VDMX", "DSIG" }) S.Tables.Remove(t);
        S.Save(path);
    }
}
