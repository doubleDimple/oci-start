package com.doubledimple.ociserver.service.security;

import com.doubledimple.ociserver.config.exception.IpBannedException;
import com.google.common.net.InetAddresses;
import org.springframework.context.annotation.DependsOn;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.net.InetAddress;
import java.util.function.Function;
import java.util.function.Supplier;

/**
 * 登录计数、自动封禁和人工封禁共用同一把 IP 锁。
 * 锁一直持有到独立事务提交完成，防止外层登录异常回滚计数或并发请求漏计。
 */
@Component
@DependsOn("banRecordAddressMigration")
public class LoginIpTransactions {

    private static final int LOCK_COUNT = 256;

    private final Object[] locks = new Object[LOCK_COUNT];
    private final Object[] recordLocks = new Object[LOCK_COUNT];
    private final TransactionTemplate transaction;

    public LoginIpTransactions(PlatformTransactionManager transactionManager) {
        this.transaction = new TransactionTemplate(transactionManager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
        for (int i = 0; i < locks.length; i++) {
            locks[i] = new Object();
            recordLocks[i] = new Object();
        }
    }

    /**
     * 仅用于清理无法转换为 IP 字面量的历史记录，不与合法 IP 的计数混用。
     */
    public <T> T executeRecord(long recordId, Supplier<T> operation) {
        int hash = Long.hashCode(recordId);
        Object lock = recordLocks[(hash & Integer.MAX_VALUE) % recordLocks.length];
        synchronized (lock) {
            return transaction.execute(status -> operation.get());
        }
    }

    public <T> T execute(String ip, Function<String, T> operation) {
        String address = normalizeIp(ip);
        Object lock = locks[(address.hashCode() & Integer.MAX_VALUE) % locks.length];
        synchronized (lock) {
            return transaction.execute(status -> operation.apply(address));
        }
    }

    /**
     * 只接受 IP 字面量，不解析主机名；IPv6 等价写法使用同一个计数和封禁记录。
     */
    public static String normalizeIp(String ip) {
        if (ip == null) {
            throw new IpBannedException("无法识别IP来源，拒绝访问。");
        }
        try {
            InetAddress address = InetAddresses.forString(ip.trim());
            if (address.isLoopbackAddress()) {
                return "127.0.0.1";
            }
            return InetAddresses.toAddrString(address);
        } catch (IllegalArgumentException e) {
            throw new IpBannedException("无法识别IP来源，拒绝访问。");
        }
    }
}
