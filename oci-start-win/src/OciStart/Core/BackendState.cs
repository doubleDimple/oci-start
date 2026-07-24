namespace OciStart.Core;

public enum BackendStatus
{
    Idle,
    Starting,
    Ready,
    Failed
}

public sealed class BackendState
{
    public BackendStatus Status { get; init; } = BackendStatus.Idle;
    public string? ErrorMessage { get; init; }

    public static BackendState Idle { get; } = new() { Status = BackendStatus.Idle };
    public static BackendState Starting { get; } = new() { Status = BackendStatus.Starting };
    public static BackendState Ready { get; } = new() { Status = BackendStatus.Ready };

    public static BackendState Failed(string message) =>
        new() { Status = BackendStatus.Failed, ErrorMessage = message };

    public bool IsReady => Status == BackendStatus.Ready;
}
