package com.doubledimple.ociserver;

import org.java_websocket.client.WebSocketClient;
import org.java_websocket.handshake.ServerHandshake;

import java.net.URI;

/**
 * @version 1.0.0
 * @ClassName PingSocketClient
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-28 20:51
 */
public class PingSocketClient extends WebSocketClient {

    public PingSocketClient(URI serverUri) {
        super(serverUri);
    }

    @Override
    public void onOpen(ServerHandshake serverHandshake) {
        System.out.println("已连接 WebSocket");

    }

    @Override
    public void onMessage(String message) {
    // 这里就能收到服务器的消息。和前端JS里的 onmessage 类似
        System.out.println("收到消息: " + message);
    }

    @Override
    public void onClose(int code, String reason, boolean remote) {
        System.out.println("连接关闭。code=" + code + ", reason=" + reason);
    }

    @Override
    public void onError(Exception e) {
        e.printStackTrace();
    }


}
