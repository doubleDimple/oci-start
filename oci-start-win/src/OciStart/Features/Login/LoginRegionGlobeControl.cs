using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace OciStart.Features.Login;

public sealed class LoginRegionGlobeControl : FrameworkElement
{
    private double _rotY = 0.3;
    private double _rotX = 0.28;
    private double _velY = 0;
    private double _velX = 0;
    private bool _isDragging = false;
    private Point _lastMousePos;

    private readonly DispatcherTimer _timer;
    private DateTime _startTime = DateTime.UtcNow;

    // Multi-color continent brushes (Dark mode matching oci-start-mac & oci-web-vue)
    private static readonly SolidColorBrush[] ContinentBrushes = new SolidColorBrush[]
    {
        CreateBrush("#38bdf8"), // 0: 北美洲 Sky Blue
        CreateBrush("#67e8f9"), // 1: 格陵兰 Ice Cyan
        CreateBrush("#fbbf24"), // 2: 南美洲 Amber Gold
        CreateBrush("#eab308"), // 3: 非洲 Sun Gold
        CreateBrush("#34d399"), // 4: 欧亚大陆 Emerald Green
        CreateBrush("#a3e635"), // 5: 东南亚 Lime Green
        CreateBrush("#c084fc"), // 6: 大洋洲 Purple
        CreateBrush("#e879f9"), // 7: 新西兰 Orchid
        CreateBrush("#fb7185"), // 8: 日本 Rose Pink
        CreateBrush("#2dd4bf"), // 9: 英国 Teal
        CreateBrush("#eab308"), // 10: 马达加斯加
        CreateBrush("#34d399")  // 11: 岛屿
    };

    private static readonly SolidColorBrush FlareOrangeBrush = CreateBrush("#FF6600");
    private static readonly SolidColorBrush WhiteCoreBrush = CreateBrush("#FFFFFF");
    private static readonly SolidColorBrush OceanColorBrush = CreateBrush("#0B1219");
    private static readonly SolidColorBrush OceanEdgeBrush = CreateBrush("#162330");
    private static readonly SolidColorBrush GraticuleBrush = CreateBrush("#78A5C8", 0.22);
    private static readonly SolidColorBrush LineBrush = CreateBrush("#FF6600", 0.55);

    private static SolidColorBrush CreateBrush(string hex, double opacity = 1.0)
    {
        var color = (Color)ColorConverter.ConvertFromString(hex);
        var brush = new SolidColorBrush(color) { Opacity = opacity };
        brush.Freeze();
        return brush;
    }

    public LoginRegionGlobeControl()
    {
        ClipToBounds = true;

        _timer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromMilliseconds(33) // ~30 FPS
        };
        _timer.Tick += OnTimerTick;

        Loaded += (_, _) => _timer.Start();
        Unloaded += (_, _) => _timer.Stop();
    }

    private void OnTimerTick(object? sender, EventArgs e)
    {
        if (!_isDragging)
        {
            _rotY += 0.0025 + _velY;
            _rotX += _velX;
            _velY *= 0.94;
            _velX *= 0.94;
            _rotX = Math.Max(-0.8, Math.Min(0.8, _rotX));
        }
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        _isDragging = true;
        _lastMousePos = e.GetPosition(this);
        _velX = 0;
        _velY = 0;
        CaptureMouse();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        Point currentPos = e.GetPosition(this);
        if (_isDragging)
        {
            double dx = currentPos.X - _lastMousePos.X;
            double dy = currentPos.Y - _lastMousePos.Y;
            _rotY += dx * 0.006;
            _rotX = Math.Max(-0.8, Math.Min(0.8, _rotX + dy * 0.006));
            _velY = dx * 0.002;
            _velX = dy * 0.002;
            _lastMousePos = currentPos;
            InvalidateVisual();
        }
        else
        {
            // Hit test for region node tooltip
            double width = ActualWidth;
            double height = ActualHeight;
            if (width > 20 && height > 20)
            {
                double cx = width / 2;
                double cy = height / 2;
                double radius = Math.Min(width, height) * 0.40;

                string? matchedTooltip = null;
                foreach (var region in LoginPublicRegion.Locations)
                {
                    double phi = region.Latitude * LoginPublicRegion.Rad;
                    double lam = region.Longitude * LoginPublicRegion.Rad;
                    double cosPhi = Math.Cos(phi);
                    var p = LoginPublicRegion.Project3D(cosPhi * Math.Sin(lam), Math.Sin(phi), cosPhi * Math.Cos(lam),
                        _rotY, _rotX, cx, cy, radius);

                    if (p.Z > 0.05)
                    {
                        double dist = Math.Sqrt(Math.Pow(currentPos.X - p.Sx, 2) + Math.Pow(currentPos.Y - p.Sy, 2));
                        if (dist <= 10.0)
                        {
                            var names = LoginPublicRegion.All
                                .Where(r => r.Latitude == region.Latitude && r.Longitude == region.Longitude)
                                .Select(r => $"{r.Zh} ({r.En}) · {r.Id}\n{r.Coordinates}");
                            matchedTooltip = string.Join("\n", names);
                            break;
                        }
                    }
                }
                ToolTip = matchedTooltip;
            }
        }
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        if (_isDragging)
        {
            _isDragging = false;
            ReleaseMouseCapture();
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);

        double width = ActualWidth;
        double height = ActualHeight;
        if (width < 20 || height < 20) return;

        double cx = width / 2;
        double cy = height / 2;
        double radius = Math.Min(width, height) * 0.40;

        double seconds = (DateTime.UtcNow - _startTime).TotalSeconds;

        // 1. Atmosphere Outer Glow
        var glowBrush = new RadialGradientBrush
        {
            Center = new Point(0.5, 0.5),
            GradientOrigin = new Point(0.5, 0.5),
            RadiusX = 0.5,
            RadiusY = 0.5,
            GradientStops = new GradientStopCollection
            {
                new GradientStop(Color.FromArgb(35, 255, 102, 0), 0.70),
                new GradientStop(Color.FromArgb(0, 255, 102, 0), 1.0)
            }
        };
        dc.DrawEllipse(glowBrush, null, new Point(cx, cy), radius * 1.22, radius * 1.22);

        // 2. 3D Globe Surface Fill
        var bodyBrush = new RadialGradientBrush
        {
            Center = new Point(0.5, 0.5),
            GradientOrigin = new Point(0.35, 0.35),
            RadiusX = 0.5,
            RadiusY = 0.5,
            GradientStops = new GradientStopCollection
            {
                new GradientStop((Color)ColorConverter.ConvertFromString("#0B1219"), 0.0),
                new GradientStop((Color)ColorConverter.ConvertFromString("#0B1219"), 0.65),
                new GradientStop((Color)ColorConverter.ConvertFromString("#162330"), 1.0)
            }
        };
        dc.DrawEllipse(bodyBrush, new Pen(CreateBrush("#FF6600", 0.35), 1.2), new Point(cx, cy), radius, radius);

        // 3. Tilted Polar Axis Line (23.44°)
        var poleNorth = LoginPublicRegion.Project3D(0, 1.13, 0, _rotY, _rotX, cx, cy, radius);
        var poleSouth = LoginPublicRegion.Project3D(0, -1.13, 0, _rotY, _rotX, cx, cy, radius);
        var axisPen = new Pen(CreateBrush("#FF6600", 0.3), 1.0)
        {
            DashStyle = new DashStyle(new double[] { 4, 4 }, 0)
        };
        dc.DrawLine(axisPen, new Point(poleNorth.Sx, poleNorth.Sy), new Point(poleSouth.Sx, poleSouth.Sy));

        // 4. Graticule Lines (Parallels & Meridians)
        var graticulePen = new Pen(GraticuleBrush, 0.95);
        foreach (var line in LoginPublicRegion.Graticules)
        {
            Point? lastPt = null;
            foreach (var pt in line)
            {
                var p = LoginPublicRegion.Project3D(pt.Vx, pt.Vy, pt.Vz, _rotY, _rotX, cx, cy, radius);
                if (p.Z > 0.02)
                {
                    var current = new Point(p.Sx, p.Sy);
                    if (lastPt.HasValue)
                    {
                        dc.DrawLine(graticulePen, lastPt.Value, current);
                    }
                    lastPt = current;
                }
                else
                {
                    lastPt = null;
                }
            }
        }

        // 5. Land Dots (Multi-Color Continents)
        double baseDotR = Math.Max(0.9, radius * 0.009);
        foreach (var dot in LoginPublicRegion.LandDots)
        {
            var p = LoginPublicRegion.Project3D(dot.Vx, dot.Vy, dot.Vz, _rotY, _rotX, cx, cy, radius);
            if (p.Z > 0.02)
            {
                double r = baseDotR * (0.65 + p.Z * 0.45);
                var brush = dot.Continent >= 0 && dot.Continent < ContinentBrushes.Length
                    ? ContinentBrushes[dot.Continent]
                    : ContinentBrushes[4];
                dc.DrawEllipse(brush, null, new Point(p.Sx, p.Sy), r, r);
            }
        }

        // 6. 3D Great-Circle Network Arcs & Traveling Light Particles
        var arcPen = new Pen(LineBrush, 1.1);
        for (int rIdx = 0; rIdx < LoginPublicRegion.Routes.Count; rIdx++)
        {
            var route = LoginPublicRegion.Routes[rIdx];
            Point? lastPt = null;
            foreach (var pt in route.Samples)
            {
                var p = LoginPublicRegion.Project3D(pt.Vx, pt.Vy, pt.Vz, _rotY, _rotX, cx, cy, radius);
                if (p.Z > 0.02)
                {
                    var current = new Point(p.Sx, p.Sy);
                    if (lastPt.HasValue)
                    {
                        dc.DrawLine(arcPen, lastPt.Value, current);
                    }
                    lastPt = current;
                }
                else
                {
                    lastPt = null;
                }
            }

            // Traveling Light Particle
            if (route.Samples.Count > 0)
            {
                double progress = (seconds / 3.0 + rIdx * 0.22) % 1.0;
                int sampleIdx = (int)(progress * (route.Samples.Count - 1));
                var pt = route.Samples[sampleIdx];
                var p = LoginPublicRegion.Project3D(pt.Vx, pt.Vy, pt.Vz, _rotY, _rotX, cx, cy, radius);
                if (p.Z > 0.05)
                {
                    double alpha = Math.Sin(Math.PI * progress) * Math.Min(1.0, p.Z * 2.0);
                    var particleBrush = CreateBrush("#FF6600", alpha);
                    dc.DrawEllipse(particleBrush, null, new Point(p.Sx, p.Sy), 2.5, 2.5);
                }
            }
        }

        // 7. Project & Render OCI Region Nodes (Enlarged Orange Nodes + Bright White Center)
        foreach (var region in LoginPublicRegion.Locations)
        {
            double phi = region.Latitude * LoginPublicRegion.Rad;
            double lam = region.Longitude * LoginPublicRegion.Rad;
            double cosPhi = Math.Cos(phi);
            var p = LoginPublicRegion.Project3D(cosPhi * Math.Sin(lam), Math.Sin(phi), cosPhi * Math.Cos(lam),
                _rotY, _rotX, cx, cy, radius);

            if (p.Z <= 0.05) continue;

            double depthAlpha = Math.Min(1.0, p.Z * 2.2);

            // Outer Pulsing Ring
            int hash = Math.Abs(region.Id.GetHashCode());
            double ringProgress = (seconds * 0.45 + (hash & 0xFFFF) * 0.001) % 1.0;
            double ringR = 4.0 + ringProgress * 12.0;
            var ringPen = new Pen(CreateBrush("#FF6600", (1.0 - ringProgress) * 0.45 * depthAlpha), 1.3);
            dc.DrawEllipse(null, ringPen, new Point(p.Sx, p.Sy), ringR, ringR);

            // Glowing Halo
            double glowR = 12.0;
            var haloBrush = new RadialGradientBrush
            {
                Center = new Point(0.5, 0.5),
                GradientOrigin = new Point(0.5, 0.5),
                RadiusX = 0.5,
                RadiusY = 0.5,
                GradientStops = new GradientStopCollection
                {
                    new GradientStop(Color.FromArgb((byte)(80 * depthAlpha), 255, 102, 0), 0.0),
                    new GradientStop(Color.FromArgb(0, 255, 102, 0), 1.0)
                }
            };
            dc.DrawEllipse(haloBrush, null, new Point(p.Sx, p.Sy), glowR, glowR);

            // Outer Orange Core (Enlarged)
            var nodeBrush = CreateBrush("#FF6600", depthAlpha);
            dc.DrawEllipse(nodeBrush, null, new Point(p.Sx, p.Sy), 3.8, 3.8);

            // Bright White Inner Beacon Center
            var coreBrush = CreateBrush("#FFFFFF", depthAlpha);
            dc.DrawEllipse(coreBrush, null, new Point(p.Sx, p.Sy), 1.8, 1.8);
        }
    }
}
