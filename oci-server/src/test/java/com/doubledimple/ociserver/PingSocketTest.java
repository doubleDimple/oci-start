package com.doubledimple.ociserver;

import java.net.URI;
import java.net.URISyntaxException;

/**
 * @version 1.0.0
 * @ClassName PingSocketTest
 * @Description TODO
 * @Author renyx
 * @Date 2025-11-30 08:36
 */
public class PingSocketTest {

    public static void main(String[] args) throws URISyntaxException, InterruptedException  {
        // 这里就是 wss://www.itdog.cn/websockets
        // 但注意 Java-WebSocket 默认不支持wss，需要另外处理SSL
        // 或者换用其他支持 wss 的库
        URI uri = new URI("wss://www.itdog.cn/websockets");
        PingSocketClient client = new PingSocketClient(uri);
        client.connectBlocking();

        // 等连接成功后，可能需要再发一些鉴权/初始化的消息
        // 模拟前端 create_websocket(...) 时发给服务器的东西
        // 具体要发什么，要去分析前端JS的实现
        // client.send("...");

        // 等待看 onMessage()
        Thread.sleep(30000);

        // 关闭连接
        client.close();
    }
}
