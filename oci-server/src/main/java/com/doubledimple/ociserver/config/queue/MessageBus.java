package com.doubledimple.ociserver.config.queue;

import org.springframework.stereotype.Component;

import javax.annotation.PostConstruct;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * @version 1.0.0
 * @ClassName MessageBus
 * @Description 消息总线
 * @Author doubleDimple
 * @Date 2025-09-22 09:20
 */
/*@Component
public class MessageBus<T> {

    private final BlockingQueue<Message<T>> queue = new LinkedBlockingQueue<>();

    private final ExecutorService executor = Executors.newFixedThreadPool(4); // 4个消费者线程

    private final List<MessageHandler<T>> handlers;

    // 构造注入多个 handler
    public MessageBus(List<MessageHandler<T>> handlers) {
        this.handlers = handlers;
    }

    // 启动消费者
    @PostConstruct
    public void start() {
        for (int i = 0; i < 4; i++) {
            executor.submit(this::consumeLoop);
        }
    }

    // 消费循环
    private void consumeLoop() {
        while (true) {
            try {
                Message<T> msg = queue.take();
                for (MessageHandler<T> handler : handlers) {
                    try {
                        handler.onMessage(msg);
                    } catch (Exception e) {
                        System.err.println("处理消息异常: " + e.getMessage());
                    }
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
    }

    // 发布消息
    public void publish(T payload) {
        queue.offer(new Message<>(payload));
    }
}*/
