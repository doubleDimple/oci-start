package com.doubledimple.ociserver.service.security;

import com.doubledimple.dao.entity.BanRecord;
import com.doubledimple.dao.repository.BanRecordRepository;
import com.doubledimple.ociserver.config.exception.IpBannedException;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import javax.annotation.PostConstruct;

/**
 * 统一旧封禁记录中的 IPv6 写法，保证上线后仍能命中原有封禁。
 * 仓库初始化完成（包括建表）后执行；登录处理显式依赖本迁移完成。
 */
@Slf4j
@Component
@Lazy(false)
public class BanRecordAddressMigration {

    private final BanRecordRepository repository;
    private final TransactionTemplate transaction;

    public BanRecordAddressMigration(BanRecordRepository repository,
                                     PlatformTransactionManager transactionManager) {
        this.repository = repository;
        this.transaction = new TransactionTemplate(transactionManager);
        this.transaction.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    @PostConstruct
    public void normalizeExistingAddresses() {
        Integer updated = transaction.execute(status -> {
            int changed = 0;
            for (BanRecord record : repository.findAll()) {
                String normalized;
                try {
                    normalized = LoginIpTransactions.normalizeIp(record.getIpAddress());
                } catch (IpBannedException invalidAddress) {
                    // 不输出旧字段内容，避免脏数据进入日志，也不删除或改动历史记录。
                    log.warn("保留无效 IP 的历史封禁记录，记录ID={}", record.getId());
                    continue;
                }
                if (!normalized.equals(record.getIpAddress())) {
                    record.setIpAddress(normalized);
                    changed++;
                }
            }
            return changed;
        });
        if (updated != null && updated > 0) {
            log.info("已规范化历史封禁记录的 IP 地址，记录数={}", updated);
        }
    }
}
