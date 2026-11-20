namespace InputBridge.Protocol;

/// <summary>Pure grid topology; local device occupies the origin.</summary>
public sealed class DeviceLayout
{
    public readonly record struct Position(int X, int Y);
    public enum Direction { Left, Right, Up, Down }
    public const string LocalDevice = "local";
    private readonly Dictionary<string, Position> positions = new(StringComparer.Ordinal) { [LocalDevice] = new(0, 0) };

    public void Add(string device, Position position)
    {
        if (string.IsNullOrWhiteSpace(device) || System.Text.Encoding.UTF8.GetByteCount(device) > 128 || device == LocalDevice)
            throw new ArgumentException("Invalid device ID", nameof(device));
        if (position.X is < -100 or > 100 || position.Y is < -100 or > 100) throw new ArgumentOutOfRangeException(nameof(position));
        if (positions.ContainsKey(device)) throw new InvalidOperationException("Duplicate device");
        if (positions.Count > DeviceRouter.MaximumPeers) throw new InvalidOperationException("Device limit reached");
        if (positions.ContainsValue(position)) throw new InvalidOperationException("Position occupied");
        positions.Add(device, position);
    }

    public void Remove(string device) { if (device != LocalDevice) positions.Remove(device); }

    public string? Neighbor(string device, Direction direction)
    {
        if (!positions.TryGetValue(device, out Position point)) return null;
        Position target = direction switch
        {
            Direction.Left => point with { X = point.X - 1 }, Direction.Right => point with { X = point.X + 1 },
            Direction.Up => point with { Y = point.Y - 1 }, Direction.Down => point with { Y = point.Y + 1 },
            _ => throw new ArgumentOutOfRangeException(nameof(direction))
        };
        foreach (var pair in positions) if (pair.Value == target) return pair.Key;
        return null;
    }
}
