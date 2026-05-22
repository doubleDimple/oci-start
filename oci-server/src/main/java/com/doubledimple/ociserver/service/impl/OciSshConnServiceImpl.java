package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.ociserver.service.OciSshConnService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import javax.annotation.Resource;
import java.util.Optional;

/**
 * @version 1.0.0
 * @ClassName OciSshConnServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-04-02 14:41
 */
@Service
@Slf4j
public class OciSshConnServiceImpl implements OciSshConnService {

    @Resource
    CloudSshConnRepository cloudSshConnRepository;


    @Override
    @Transactional
    public void saveOrUpdate(InstanceDetails instanceDetails) {
        Optional<CloudSshConn> ociSshConnDetail = cloudSshConnRepository.findByInstanceId(instanceDetails.getInstanceId());
        if (ociSshConnDetail.isPresent()){
            CloudSshConn cloudSshConn = ociSshConnDetail.get();
            cloudSshConn.setUsername(instanceDetails.getUsername());
            cloudSshConn.setPort(instanceDetails.getPort());
            cloudSshConn.setPassword(instanceDetails.getPassword());
            cloudSshConnRepository.save(cloudSshConn);
        }else{
            String host = instanceDetails.getPublicIps() == null ? "127.0.0.1" : instanceDetails.getPublicIps();
            String user = (instanceDetails.getUsername() == null) ? "root" : instanceDetails.getUsername();
            String remark = "Auto-synced from OCI";
            try {
                cloudSshConnRepository.save(CloudSshConn.builder()
                        .instanceId(instanceDetails.getInstanceId())
                        .remark(remark)
                        .name(user)
                        .username(user)
                        .port(instanceDetails.getPort() == null ? 22 : instanceDetails.getPort())
                        .password(instanceDetails.getPassword())
                        .host(host)
                        .build());
            } catch (Exception e) {
                log.error("save or update cloud ssh conn error for instance {}: {}", instanceDetails.getInstanceId(), e.getMessage());            }
        }
    }
}
