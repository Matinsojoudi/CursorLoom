namespace InputBridge.Protocol;

/// <summary>Preserves high-resolution Windows wheel deltas until a full detent.</summary>
public sealed class WheelAccumulator
{
    private int remainder;
    public int Push(int delta)
    {
        // WM_MOUSEWHEEL carries a signed 16-bit delta. Bound inputs before arithmetic.
        if (delta is < short.MinValue or > short.MaxValue) throw new ArgumentOutOfRangeException(nameof(delta));
        int total = remainder + delta;
        int lines = total / 120;
        remainder = total % 120;
        return lines;
    }
    public void Reset() => remainder = 0;
}
