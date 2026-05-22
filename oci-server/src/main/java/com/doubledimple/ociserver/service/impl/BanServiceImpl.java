package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.BanRecord;
import com.doubledimple.dao.repository.BanRecordRepository;
import com.doubledimple.ociserver.service.BanService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName BanServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-01 08:55
 */
@Slf4j
@Service
public class BanServiceImpl implements BanService {

    @Resource
    private BanRecordRepository banRecordRepository;

    @Override
    @Transactional
    public boolean banIp(String ip, String reason) {
        try {
            BanRecord existing = banRecordRepository.findTopByIpAddress(ip);

            if (existing != null) {
                existing.setStatus(1);
                existing.setReason(reason);
                banRecordRepository.save(existing);
                log.info("更新封禁记录成功：{}", ip);
            } else {
                BanRecord record = new BanRecord();
                record.setIpAddress(ip);
                record.setSource("系统封禁");
                record.setOperatorName("system");
                record.setReason(reason);
                record.setStatus(1);
                banRecordRepository.save(record);
                log.info("新增封禁记录成功：{}", ip);
            }
            return true;
        } catch (Exception e) {
            log.error("封禁 IP 失败: {}", e.getMessage(), e);
            return false;
        }
    }

    @Override
    @Transactional
    public boolean unbanIp(String ip,String reason) {
        try {
            BanRecord existing = banRecordRepository.findTopByIpAddress(ip);
            if (existing == null || existing.getStatus() == 0) {
                log.warn("解封失败，IP [{}] 未找到或未被封禁", ip);
                return false;
            }
            existing.setStatus(0);
            existing.setUnbanTime(LocalDateTime.now());
            existing.setOperatorName("system");
            existing.setReason("手动解封");
            banRecordRepository.save(existing);

            log.info("解封成功：{}", ip);
            return true;
        } catch (Exception e) {
            log.error("解封 IP 失败: {}", e.getMessage(), e);
            return false;
        }
    }
}
