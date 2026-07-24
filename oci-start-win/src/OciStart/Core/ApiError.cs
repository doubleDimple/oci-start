namespace OciStart.Core;

public sealed class ApiError : Exception
{
    public enum Kind
    {
        Network,
        Unauthorized,
        ServerMessage,
        InvalidResponse,
        Decoding
    }

    public Kind ErrorKind { get; }

    public ApiError(Kind kind, string message, Exception? inner = null)
        : base(message, inner)
    {
        ErrorKind = kind;
    }

    public static ApiError Network(Exception ex) =>
        new(Kind.Network, "网络错误：" + ex.Message, ex);

    public static ApiError Unauthorized() =>
        new(Kind.Unauthorized, "登录已失效，请重新登录");

    public static ApiError Server(string message) =>
        new(Kind.ServerMessage, message);

    public static ApiError InvalidResponse() =>
        new(Kind.InvalidResponse, "无效的服务器响应");

    public static ApiError Decoding(string message) =>
        new(Kind.Decoding, "数据解析失败：" + message);
}
