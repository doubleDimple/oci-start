using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace OciStart.Features.Login;

public readonly record struct Point3D(double Vx, double Vy, double Vz, int Continent = 0);

public readonly record struct Project3D(double Sx, double Sy, double Z);

public sealed class RouteArc
{
    public required LoginPublicRegion A { get; init; }
    public required LoginPublicRegion B { get; init; }
    public required List<Point3D> Samples { get; init; }
}

public sealed class LoginPublicRegion
{
    public required string Id { get; init; }
    public required string Zh { get; init; }
    public required string En { get; init; }
    public required double Latitude { get; init; }
    public required double Longitude { get; init; }

    public string Coordinates =>
        string.Format(CultureInfo.InvariantCulture, "{0:F4}° {1} · {2:F4}° {3}",
            Math.Abs(Latitude), Latitude < 0 ? "S" : "N",
            Math.Abs(Longitude), Longitude < 0 ? "W" : "E");

    public const double Rad = Math.PI / 180.0;
    public const double AxialTilt = -0.409; // ~23.44° real Earth axial tilt

    public static Project3D Project3D(double vx, double vy, double vz, double spinY, double pitchX, double cx, double cy, double radius)
    {
        double cosSpin = Math.Cos(spinY), sinSpin = Math.Sin(spinY);
        double cosTilt = Math.Cos(AxialTilt), sinTilt = Math.Sin(AxialTilt);
        double cosPitch = Math.Cos(pitchX), sinPitch = Math.Sin(pitchX);

        // 1. Spin around polar Y axis
        double x1 = vx * cosSpin + vz * sinSpin;
        double y1 = vy;
        double z1 = -vx * sinSpin + vz * cosSpin;

        // 2. 23.44° axial tilt around Z axis
        double x2 = x1 * cosTilt - y1 * sinTilt;
        double y2 = x1 * sinTilt + y1 * cosTilt;
        double z2 = z1;

        // 3. View pitch tilt around X axis
        double x3 = x2;
        double y3 = y2 * cosPitch - z2 * sinPitch;
        double z3 = y2 * sinPitch + z2 * cosPitch;

        return new Project3D(
            cx + x3 * radius,
            cy - y3 * radius,
            z3
        );
    }

    public static List<LoginPublicRegion> All { get; } = new()
    {
        new LoginPublicRegion { Id = "ap-sydney-1", Zh = "悉尼", En = "Sydney", Latitude = -33.8688, Longitude = 151.2093 },
        new LoginPublicRegion { Id = "ap-melbourne-1", Zh = "墨尔本", En = "Melbourne", Latitude = -37.8136, Longitude = 144.9631 },
        new LoginPublicRegion { Id = "sa-saopaulo-1", Zh = "圣保罗", En = "São Paulo", Latitude = -23.5505, Longitude = -46.6333 },
        new LoginPublicRegion { Id = "sa-vinhedo-1", Zh = "维涅杜", En = "Vinhedo", Latitude = -23.0304, Longitude = -46.9834 },
        new LoginPublicRegion { Id = "ca-montreal-1", Zh = "蒙特利尔", En = "Montréal", Latitude = 45.5017, Longitude = -73.5673 },
        new LoginPublicRegion { Id = "ca-toronto-1", Zh = "多伦多", En = "Toronto", Latitude = 43.6532, Longitude = -79.3832 },
        new LoginPublicRegion { Id = "sa-santiago-1", Zh = "圣地亚哥", En = "Santiago", Latitude = -33.4489, Longitude = -70.6693 },
        new LoginPublicRegion { Id = "sa-valparaiso-1", Zh = "瓦尔帕莱索", En = "Valparaíso", Latitude = -33.0472, Longitude = -71.6127 },
        new LoginPublicRegion { Id = "sa-bogota-1", Zh = "波哥大", En = "Bogotá", Latitude = 4.711, Longitude = -74.0721 },
        new LoginPublicRegion { Id = "eu-paris-1", Zh = "巴黎", En = "Paris", Latitude = 48.8566, Longitude = 2.3522 },
        new LoginPublicRegion { Id = "eu-marseille-1", Zh = "马赛", En = "Marseille", Latitude = 43.2965, Longitude = 5.3698 },
        new LoginPublicRegion { Id = "eu-frankfurt-1", Zh = "法兰克福", En = "Frankfurt", Latitude = 50.1109, Longitude = 8.6821 },
        new LoginPublicRegion { Id = "ap-hyderabad-1", Zh = "海得拉巴", En = "Hyderabad", Latitude = 17.385, Longitude = 78.4867 },
        new LoginPublicRegion { Id = "ap-mumbai-1", Zh = "孟买", En = "Mumbai", Latitude = 19.076, Longitude = 72.8777 },
        new LoginPublicRegion { Id = "ap-batam-1", Zh = "巴淡", En = "Batam", Latitude = 1.1074, Longitude = 104.03 },
        new LoginPublicRegion { Id = "il-jerusalem-1", Zh = "耶路撒冷", En = "Jerusalem", Latitude = 31.7683, Longitude = 35.2137 },
        new LoginPublicRegion { Id = "eu-milan-1", Zh = "米兰", En = "Milan", Latitude = 45.4642, Longitude = 9.19 },
        new LoginPublicRegion { Id = "eu-turin-1", Zh = "都灵", En = "Turin", Latitude = 45.0703, Longitude = 7.6869 },
        new LoginPublicRegion { Id = "ap-osaka-1", Zh = "大阪", En = "Osaka", Latitude = 34.6937, Longitude = 135.5023 },
        new LoginPublicRegion { Id = "ap-tokyo-1", Zh = "东京", En = "Tokyo", Latitude = 35.6762, Longitude = 139.6503 },
        new LoginPublicRegion { Id = "ap-kulai-2", Zh = "古来", En = "Kulai", Latitude = 1.6629, Longitude = 103.5999 },
        new LoginPublicRegion { Id = "mx-queretaro-1", Zh = "克雷塔罗", En = "Querétaro", Latitude = 20.5888, Longitude = -100.3899 },
        new LoginPublicRegion { Id = "mx-monterrey-1", Zh = "蒙特雷", En = "Monterrey", Latitude = 25.6866, Longitude = -100.3161 },
        new LoginPublicRegion { Id = "af-casablanca-1", Zh = "卡萨布兰卡", En = "Casablanca", Latitude = 33.5731, Longitude = -7.5898 },
        new LoginPublicRegion { Id = "eu-amsterdam-1", Zh = "阿姆斯特丹", En = "Amsterdam", Latitude = 52.3676, Longitude = 4.9041 },
        new LoginPublicRegion { Id = "me-riyadh-1", Zh = "利雅得", En = "Riyadh", Latitude = 24.7136, Longitude = 46.6753 },
        new LoginPublicRegion { Id = "me-jeddah-1", Zh = "吉达", En = "Jeddah", Latitude = 21.4858, Longitude = 39.1925 },
        new LoginPublicRegion { Id = "eu-jovanovac-1", Zh = "乔万诺瓦茨", En = "Jovanovac", Latitude = 44.0501, Longitude = 20.9507 },
        new LoginPublicRegion { Id = "ap-singapore-1", Zh = "新加坡", En = "Singapore", Latitude = 1.3521, Longitude = 103.8198 },
        new LoginPublicRegion { Id = "ap-singapore-2", Zh = "新加坡西部", En = "Singapore West", Latitude = 1.3521, Longitude = 103.8198 },
        new LoginPublicRegion { Id = "af-johannesburg-1", Zh = "约翰内斯堡", En = "Johannesburg", Latitude = -26.2041, Longitude = 28.0473 },
        new LoginPublicRegion { Id = "ap-seoul-1", Zh = "首尔", En = "Seoul", Latitude = 37.5665, Longitude = 126.978 },
        new LoginPublicRegion { Id = "ap-chuncheon-1", Zh = "春川", En = "Chuncheon", Latitude = 37.8747, Longitude = 127.7342 },
        new LoginPublicRegion { Id = "eu-madrid-1", Zh = "马德里", En = "Madrid", Latitude = 40.4168, Longitude = -3.7038 },
        new LoginPublicRegion { Id = "eu-madrid-3", Zh = "马德里 3", En = "Madrid 3", Latitude = 40.4168, Longitude = -3.7038 },
        new LoginPublicRegion { Id = "eu-stockholm-1", Zh = "斯德哥尔摩", En = "Stockholm", Latitude = 59.3293, Longitude = 18.0686 },
        new LoginPublicRegion { Id = "eu-zurich-1", Zh = "苏黎世", En = "Zurich", Latitude = 47.3769, Longitude = 8.5417 },
        new LoginPublicRegion { Id = "me-abudhabi-1", Zh = "阿布扎比", En = "Abu Dhabi", Latitude = 24.4539, Longitude = 54.3773 },
        new LoginPublicRegion { Id = "me-dubai-1", Zh = "迪拜", En = "Dubai", Latitude = 25.2048, Longitude = 55.2708 },
        new LoginPublicRegion { Id = "uk-london-1", Zh = "伦敦", En = "London", Latitude = 51.5074, Longitude = -0.1278 },
        new LoginPublicRegion { Id = "uk-cardiff-1", Zh = "纽波特", En = "Newport", Latitude = 51.5877, Longitude = -2.9984 },
        new LoginPublicRegion { Id = "us-ashburn-1", Zh = "阿什本", En = "Ashburn", Latitude = 39.0438, Longitude = -77.4874 },
        new LoginPublicRegion { Id = "us-chicago-1", Zh = "芝加哥", En = "Chicago", Latitude = 41.8781, Longitude = -87.6298 },
        new LoginPublicRegion { Id = "us-phoenix-1", Zh = "凤凰城", En = "Phoenix", Latitude = 33.4484, Longitude = -112.074 },
        new LoginPublicRegion { Id = "us-sanjose-1", Zh = "圣何塞", En = "San Jose", Latitude = 37.3382, Longitude = -121.8863 },
    };

    public static List<LoginPublicRegion> Locations { get; } = All
        .GroupBy(r => (r.Latitude, r.Longitude))
        .Select(g => g.First())
        .ToList();

    public static double[][][] Land { get; } = new double[][][]
    {
        // 0: 北美洲
        new double[][] { new double[]{-168,65}, new double[]{-165,60}, new double[]{-158,57}, new double[]{-152,58}, new double[]{-146,60}, new double[]{-138,59}, new double[]{-131,53}, new double[]{-125,49}, new double[]{-124,42}, new double[]{-120,34}, new double[]{-117,32}, new double[]{-110,24}, new double[]{-105,20}, new double[]{-97,16}, new double[]{-92,15}, new double[]{-88,16}, new double[]{-87,21}, new double[]{-91,21}, new double[]{-95,19}, new double[]{-97,23}, new double[]{-97,26}, new double[]{-94,29}, new double[]{-89,29}, new double[]{-84,30}, new double[]{-81,25}, new double[]{-80,32}, new double[]{-76,35}, new double[]{-70,42}, new double[]{-67,45}, new double[]{-60,47}, new double[]{-56,51}, new double[]{-56,54}, new double[]{-64,60}, new double[]{-78,62}, new double[]{-78,55}, new double[]{-82,55}, new double[]{-86,66}, new double[]{-95,68}, new double[]{-105,68}, new double[]{-115,70}, new double[]{-125,70}, new double[]{-135,69}, new double[]{-145,70}, new double[]{-156,71}, new double[]{-166,68} },
        // 1: 格陵兰
        new double[][] { new double[]{-45,60}, new double[]{-52,64}, new double[]{-53,68}, new double[]{-62,70}, new double[]{-68,76}, new double[]{-62,82}, new double[]{-40,83}, new double[]{-24,80}, new double[]{-20,73}, new double[]{-30,68}, new double[]{-42,61} },
        // 2: 南美洲
        new double[][] { new double[]{-81,-4}, new double[]{-79,0}, new double[]{-77,8}, new double[]{-72,12}, new double[]{-62,10}, new double[]{-60,8}, new double[]{-52,5}, new double[]{-50,0}, new double[]{-44,-2}, new double[]{-38,-5}, new double[]{-35,-8}, new double[]{-39,-13}, new double[]{-39,-18}, new double[]{-48,-25}, new double[]{-53,-34}, new double[]{-58,-38}, new double[]{-62,-40}, new double[]{-65,-45}, new double[]{-68,-50}, new double[]{-70,-54}, new double[]{-75,-52}, new double[]{-74,-45}, new double[]{-73,-37}, new double[]{-71,-30}, new double[]{-70,-20}, new double[]{-75,-15}, new double[]{-81,-6} },
        // 3: 非洲
        new double[][] { new double[]{-17,15}, new double[]{-16,20}, new double[]{-12,28}, new double[]{-10,32}, new double[]{-5,36}, new double[]{10,37}, new double[]{20,32}, new double[]{28,31}, new double[]{33,28}, new double[]{35,23}, new double[]{38,18}, new double[]{43,12}, new double[]{51,12}, new double[]{51,5}, new double[]{42,-1}, new double[]{40,-10}, new double[]{35,-20}, new double[]{32,-26}, new double[]{27,-34}, new double[]{20,-35}, new double[]{18,-30}, new double[]{13,-20}, new double[]{9,-1}, new double[]{3,6}, new double[]{-8,4}, new double[]{-13,9} },
        // 4: 欧亚大陆
        new double[][] { new double[]{-10,36}, new double[]{-9,43}, new double[]{-2,48}, new double[]{3,51}, new double[]{6,53}, new double[]{9,54}, new double[]{11,58}, new double[]{16,60}, new double[]{22,60}, new double[]{30,60}, new double[]{28,66}, new double[]{21,70}, new double[]{32,71}, new double[]{46,68}, new double[]{62,70}, new double[]{76,73}, new double[]{92,75}, new double[]{106,77}, new double[]{116,74}, new double[]{132,72}, new double[]{146,70}, new double[]{160,70}, new double[]{170,66}, new double[]{179,65}, new double[]{172,60}, new double[]{162,58}, new double[]{155,52}, new double[]{142,48}, new double[]{135,43}, new double[]{130,35}, new double[]{122,32}, new double[]{120,25}, new double[]{110,20}, new double[]{105,10}, new double[]{100,6}, new double[]{97,16}, new double[]{90,22}, new double[]{82,17}, new double[]{77,8}, new double[]{72,20}, new double[]{66,25}, new double[]{57,25}, new double[]{50,30}, new double[]{45,37}, new double[]{36,36}, new double[]{30,41}, new double[]{26,38}, new double[]{22,40}, new double[]{16,38}, new double[]{13,45}, new double[]{8,44}, new double[]{3,42}, new double[]{-2,37} },
        // 5: 东南亚
        new double[][] { new double[]{95,5}, new double[]{105,-6}, new double[]{115,-9}, new double[]{125,-9}, new double[]{135,-5}, new double[]{141,-3}, new double[]{141,-9}, new double[]{131,-8}, new double[]{120,-10}, new double[]{110,-8}, new double[]{100,0} },
        // 6: 大洋洲
        new double[][] { new double[]{113,-22}, new double[]{114,-35}, new double[]{118,-35}, new double[]{129,-32}, new double[]{137,-35}, new double[]{141,-38}, new double[]{147,-39}, new double[]{151,-37}, new double[]{153,-28}, new double[]{145,-15}, new double[]{142,-11}, new double[]{136,-12}, new double[]{130,-11}, new double[]{125,-14}, new double[]{118,-20} },
        // 7: 新西兰
        new double[][] { new double[]{172,-41}, new double[]{174,-37}, new double[]{178,-38}, new double[]{176,-41}, new double[]{174,-46}, new double[]{168,-46}, new double[]{167,-44} },
        // 8: 日本
        new double[][] { new double[]{130,31}, new double[]{134,34}, new double[]{139,35}, new double[]{141,39}, new double[]{145,44}, new double[]{142,42}, new double[]{137,37}, new double[]{132,34} },
        // 9: 英国
        new double[][] { new double[]{-5,50}, new double[]{-6,55}, new double[]{-3,58}, new double[]{-1,56}, new double[]{1,53}, new double[]{1,51}, new double[]{-4,50} },
        // 10: 马达加斯加
        new double[][] { new double[]{43,-12}, new double[]{50,-15}, new double[]{50,-25}, new double[]{45,-25}, new double[]{43,-17} },
        // 11: 菲律宾/台湾等岛屿
        new double[][] { new double[]{120,18}, new double[]{124,18}, new double[]{126,10}, new double[]{122,6}, new double[]{119,11} }
    };

    public static int GetLandContinentIndex(double longitude, double latitude)
    {
        for (int k = 0; k < Land.Length; k++)
        {
            var polygon = Land[k];
            bool inside = false;
            int j = polygon.Length - 1;
            for (int i = 0; i < polygon.Length; i++)
            {
                var a = polygon[i];
                var b = polygon[j];
                if ((a[1] > latitude) != (b[1] > latitude) &&
                    longitude < (b[0] - a[0]) * (latitude - a[1]) / (b[1] - a[1]) + a[0])
                {
                    inside = !inside;
                }
                j = i;
            }
            if (inside) return k;
        }
        return -1;
    }

    public static List<Point3D> LandDots { get; } = BuildLandDots();

    private static List<Point3D> BuildLandDots()
    {
        var points = new List<Point3D>();
        for (double lat = -72; lat <= 76; lat += 2.4)
        {
            double phi = lat * Rad;
            double cosPhi = Math.Cos(phi);
            if (cosPhi < 0.05) continue;
            double lngStep = 2.4 / cosPhi;
            for (double lng = -180; lng <= 180; lng += lngStep)
            {
                int cIdx = GetLandContinentIndex(lng, lat);
                if (cIdx >= 0)
                {
                    double lam = lng * Rad;
                    points.Add(new Point3D(cosPhi * Math.Sin(lam), Math.Sin(phi), cosPhi * Math.Cos(lam), cIdx));
                }
            }
        }
        for (int k = 0; k < Land.Length; k++)
        {
            var polygon = Land[k];
            foreach (var pt in polygon)
            {
                double lng = pt[0], lat = pt[1];
                double phi = lat * Rad, lam = lng * Rad;
                double cosPhi = Math.Cos(phi);
                points.Add(new Point3D(cosPhi * Math.Sin(lam), Math.Sin(phi), cosPhi * Math.Cos(lam), k));
            }
        }
        return points;
    }

    public static List<List<Point3D>> Graticules { get; } = BuildGraticules();

    private static List<List<Point3D>> BuildGraticules()
    {
        var lines = new List<List<Point3D>>();
        double[] lats = { -60.0, -30.0, 0.0, 30.0, 60.0 };
        foreach (double lat in lats)
        {
            var line = new List<Point3D>();
            double phi = lat * Rad;
            double cosPhi = Math.Cos(phi), sinPhi = Math.Sin(phi);
            for (double lng = -180; lng <= 180; lng += 8.0)
            {
                double lam = lng * Rad;
                line.Add(new Point3D(cosPhi * Math.Sin(lam), sinPhi, cosPhi * Math.Cos(lam)));
            }
            lines.Add(line);
        }
        for (double lng = -180; lng <= 180; lng += 30.0)
        {
            var line = new List<Point3D>();
            double lam = lng * Rad;
            double sinLam = Math.Sin(lam), cosLam = Math.Cos(lam);
            for (double lat = -80; lat <= 80; lat += 8.0)
            {
                double phi = lat * Rad;
                double cosPhi = Math.Cos(phi);
                line.Add(new Point3D(cosPhi * sinLam, Math.Sin(phi), cosPhi * cosLam));
            }
            lines.Add(line);
        }
        return lines;
    }

    private static readonly (string, string)[] RoutePairs = new[]
    {
        ("us-phoenix-1", "us-ashburn-1"), ("us-ashburn-1", "uk-london-1"),
        ("uk-london-1", "eu-frankfurt-1"), ("eu-frankfurt-1", "me-jeddah-1"),
        ("me-jeddah-1", "ap-mumbai-1"), ("ap-mumbai-1", "ap-singapore-1"),
        ("ap-singapore-1", "ap-tokyo-1"), ("ap-tokyo-1", "ap-sydney-1")
    };

    public static List<RouteArc> Routes { get; } = BuildRoutes();

    private static List<RouteArc> BuildRoutes()
    {
        var result = new List<RouteArc>();
        foreach (var pair in RoutePairs)
        {
            var rA = All.FirstOrDefault(r => r.Id == pair.Item1);
            var rB = All.FirstOrDefault(r => r.Id == pair.Item2);
            if (rA == null || rB == null) continue;

            double phiA = rA.Latitude * Rad, lamA = rA.Longitude * Rad;
            double phiB = rB.Latitude * Rad, lamB = rB.Longitude * Rad;
            double cosPhiA = Math.Cos(phiA), cosPhiB = Math.Cos(phiB);

            var vA = new Point3D(cosPhiA * Math.Sin(lamA), Math.Sin(phiA), cosPhiA * Math.Cos(lamA));
            var vB = new Point3D(cosPhiB * Math.Sin(lamB), Math.Sin(phiB), cosPhiB * Math.Cos(lamB));

            var samples = new List<Point3D>();
            int numSamples = 24;
            double dotVal = Math.Max(-1.0, Math.Min(1.0, vA.Vx * vB.Vx + vA.Vy * vB.Vy + vA.Vz * vB.Vz));
            double omega = Math.Acos(dotVal);
            double sinOmega = Math.Sin(omega);

            for (int s = 0; s <= numSamples; s++)
            {
                double t = (double)s / numSamples;
                double scaleA = sinOmega > 0.001 ? Math.Sin((1 - t) * omega) / sinOmega : (1 - t);
                double scaleB = sinOmega > 0.001 ? Math.Sin(t * omega) / sinOmega : t;
                double vx = vA.Vx * scaleA + vB.Vx * scaleB;
                double vy = vA.Vy * scaleA + vB.Vy * scaleB;
                double vz = vA.Vz * scaleA + vB.Vz * scaleB;
                double h = 1.0 + 0.18 * Math.Sin(Math.PI * t);
                samples.Add(new Point3D(vx * h, vy * h, vz * h));
            }
            result.Add(new RouteArc { A = rA, B = rB, Samples = samples });
        }
        return result;
    }
}
